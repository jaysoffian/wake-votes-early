import Foundation
import CoreLocation

public struct SitePlan: Identifiable, Sendable {
    public enum Status: Sendable, Equatable {
        case open
        case opensLater(Date)
        case closesBeforeArrival
        case closedForDay
        case noVotingToday
        case noRoute
    }

    public let site: VotingSite
    public let trip: RoundTrip?
    public let hours: EarlyVotingSchedule.Hours?
    public let status: Status
    public let departure: Date

    public var id: String { site.id }
    public var waitMinutes: Double? { site.waitMinutes }

    /// Outbound + wait + inbound, when all are known.
    public var total: TimeInterval? {
        guard let trip, let wait = waitMinutes else { return nil }
        return trip.outbound + wait * 60 + trip.inbound
    }

    public var arrival: Date? { trip.map { departure.addingTimeInterval($0.outbound) } }

    /// False when the site is closed or will be closed by the time you get there.
    public var isViable: Bool {
        switch status {
        case .open, .opensLater, .noRoute: return true
        default: return false
        }
    }
}

/// Result of one drive-time batch.
public struct RoundTripBatch: Sendable {
    public var trips: [String: RoundTrip]
    public var firstError: Error?
    /// Sites whose outbound ETA failed (they have no trip at all).
    public var failedOutbound: Int
    /// Candidates whose exact return ETA failed (they keep the estimate).
    public var failedInbound: Int
    public var wasCancelled: Bool
}

public enum Planner {
    /// Time spent inside once you reach the front of the line (check-in, ballot, scanner).
    /// Added to the return leg's departure time so its traffic prediction is for when you'd actually leave.
    public static let votingDuration: TimeInterval = 15 * 60

    /// Computes round trips, spending as few MapKit requests as possible.
    ///
    /// Phase 1 fetches the outbound ETA for every site. Phase 2 fetches the exact return ETA only for the
    /// `exactInboundCount` most promising sites; the rest reuse the outbound time as an estimate.
    /// The return leg departs at now + drive + wait + `votingDuration`, so MapKit predicts traffic for that time.
    /// Sites that would already be closed on arrival (`closingAt`) never get an exact return leg.
    public static func roundTrips(from origin: CLLocationCoordinate2D, to sites: [VotingSite], departing: Date,
                                  closingAt close: Date? = nil,
                                  travel: TravelService = TravelService(), maxConcurrent: Int = 4,
                                  exactInboundCount: Int = 8,
                                  skipping cached: [String: RoundTrip] = [:],
                                  onProgress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil)
        async -> RoundTripBatch {
        var results = cached
        var firstError: Error?
        let byID = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0) })

        // Phase 1: outbound for every uncached site.
        let needOutbound = sites.filter { $0.coordinate != nil && cached[$0.id] == nil }
        var done = 0
        var total = needOutbound.count + exactInboundCount
        onProgress?(done, total)
        let outbound = await runLimited(needOutbound, maxConcurrent: maxConcurrent, id: \.id) { site in
            try await travel.eta(from: origin, to: site.coordinate!, departing: departing)
        } each: {
            done += 1
            onProgress?(done, total)
        }
        if firstError == nil { firstError = outbound.firstError }
        for (id, time) in outbound.values {
            results[id] = RoundTrip(outbound: time, inbound: time, inboundIsEstimate: true, computedAt: departing)
        }
        let failedOutbound = needOutbound.count - outbound.values.count
        if Task.isCancelled {
            return RoundTripBatch(trips: results, firstError: firstError, failedOutbound: failedOutbound,
                                  failedInbound: 0, wasCancelled: true)
        }

        // Phase 2: exact return leg for the best candidates that still have an estimate.
        let candidates = results.compactMap { id, trip -> (site: VotingSite, trip: RoundTrip)? in
            guard trip.inboundIsEstimate, let site = byID[id] else { return nil }
            if let close, departing.addingTimeInterval(trip.outbound) >= close { return nil }
            return (site, trip)
        }
        .sorted { score($0) < score($1) }
        .prefix(exactInboundCount)
        total = needOutbound.count + candidates.count
        onProgress?(done, total)
        let inbound = await runLimited(Array(candidates), maxConcurrent: maxConcurrent, id: \.site.id) { candidate in
            let leave = departing.addingTimeInterval(candidate.trip.outbound + (candidate.site.waitMinutes ?? 0) * 60 + votingDuration)
            return try await travel.eta(from: candidate.site.coordinate!, to: origin, departing: leave)
        } each: {
            done += 1
            onProgress?(done, total)
        }
        if firstError == nil { firstError = inbound.firstError }
        for (id, time) in inbound.values {
            guard let old = results[id] else { continue }
            results[id] = RoundTrip(outbound: old.outbound, inbound: time, inboundIsEstimate: false, computedAt: old.computedAt)
        }
        return RoundTripBatch(trips: results, firstError: firstError, failedOutbound: failedOutbound,
                              failedInbound: candidates.count - inbound.values.count, wasCancelled: Task.isCancelled)
    }

    private static func score(_ c: (site: VotingSite, trip: RoundTrip)) -> TimeInterval {
        c.trip.outbound * 2 + (c.site.waitMinutes ?? 0) * 60
    }

    /// Runs `work` over `items` with at most `maxConcurrent` in flight, collecting results by id.
    private static func runLimited<T: Sendable>(_ items: [T], maxConcurrent: Int, id: KeyPath<T, String>,
                                                work: @escaping @Sendable (T) async throws -> TimeInterval,
                                                each: () -> Void)
        async -> (values: [String: TimeInterval], firstError: Error?) {
        var values: [String: TimeInterval] = [:]
        var firstError: Error?
        await withTaskGroup(of: (String, Result<TimeInterval, Error>).self) { group in
            var iterator = items.makeIterator()
            func enqueue(_ item: T) {
                group.addTask {
                    do { return (item[keyPath: id], .success(try await work(item))) }
                    catch { return (item[keyPath: id], .failure(error)) }
                }
            }
            for _ in 0..<max(1, maxConcurrent) { if let item = iterator.next() { enqueue(item) } }
            for await (key, outcome) in group {
                switch outcome {
                case .success(let value): values[key] = value
                case .failure(is CancellationError): break
                case .failure(let error): if firstError == nil { firstError = error }
                }
                each()
                if !Task.isCancelled, let next = iterator.next() { enqueue(next) }
            }
        }
        return (values, firstError)
    }

    /// Ranks sites by total time, pushing closed or unreachable sites to the bottom.
    public static func plans(for sites: [VotingSite], trips: [String: RoundTrip], departing now: Date,
                             schedule: EarlyVotingSchedule, hasOrigin: Bool) -> [SitePlan] {
        let hours = schedule.hours(on: now)
        let plans = sites.map { site -> SitePlan in
            let trip = trips[site.id]
            let status: SitePlan.Status
            if let hours {
                let arrival = now.addingTimeInterval(trip?.outbound ?? 0)
                if now >= hours.close {
                    status = .closedForDay
                } else if arrival >= hours.close {
                    status = .closesBeforeArrival
                } else if hasOrigin && trip == nil {
                    status = .noRoute
                } else if now < hours.open {
                    status = .opensLater(hours.open)
                } else {
                    status = .open
                }
            } else {
                status = .noVotingToday
            }
            return SitePlan(site: site, trip: trip, hours: hours, status: status, departure: now)
        }
        return plans.sorted { a, b in
            if a.isViable != b.isViable { return a.isViable }
            switch (a.total, b.total) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                switch (a.waitMinutes, b.waitMinutes) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.site.name < b.site.name
                }
            }
        }
    }
}
