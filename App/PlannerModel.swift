import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class PlannerModel {
    private enum Keys {
        static let address = "origin.address"
        static let latitude = "origin.latitude"
        static let longitude = "origin.longitude"
        static let avoidTolls = "routing.avoidTolls"
    }

    static let tripTTL: TimeInterval = 10 * 60
    static let refreshInterval: Duration = .seconds(5 * 60)
    static let schedule = EarlyVotingSchedule.wake2026General

    /// Display label for the starting point. Persisted independently of the coordinates.
    var originAddress: String = "" {
        didSet { UserDefaults.standard.set(originAddress, forKey: Keys.address) }
    }
    var origin: CLLocationCoordinate2D?
    /// Ask MapKit for routes that avoid toll roads. Changing it recomputes drive times.
    var avoidTolls: Bool = false {
        didSet {
            guard avoidTolls != oldValue else { return }
            UserDefaults.standard.set(avoidTolls, forKey: Keys.avoidTolls)
            Task { await recomputePlans() }
        }
    }
    var sites: [VotingSite] = []
    var plans: [SitePlan] = []
    var isRefreshing = false
    var isComputingTrips = false
    /// Progress of the current drive-time batch, as (requests done, requests planned).
    var tripProgress: (done: Int, total: Int)?
    /// Seconds the current batch is paused for MapKit's rate limit, if any.
    var throttleWait: TimeInterval = 0
    var isLocating = false
    var errorMessage: String?
    var lastRefresh: Date?
    /// When drive times were last actually fetched from MapKit (not served from cache).
    var lastTripFetch: Date?
    var now = Clock.now

    private let waitService = WaitTimeService()
    /// Round trips cached per origin and toll setting, so toggling tolls back and forth is free.
    private var tripCaches: [String: [String: RoundTrip]] = [:]
    private var autoRefreshTask: Task<Void, Never>?
    private var recomputeTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        originAddress = defaults.string(forKey: Keys.address) ?? ""
        avoidTolls = defaults.bool(forKey: Keys.avoidTolls)
        if defaults.object(forKey: Keys.latitude) != nil, defaults.object(forKey: Keys.longitude) != nil {
            let restored = CLLocationCoordinate2D(latitude: defaults.double(forKey: Keys.latitude),
                                                  longitude: defaults.double(forKey: Keys.longitude))
            origin = restored
            if originAddress.trimmingCharacters(in: .whitespaces).isEmpty {
                originAddress = String(format: "Saved location (%.4f, %.4f)", restored.latitude, restored.longitude)
            }
        }
    }

    var hasOrigin: Bool { origin != nil }

    // MARK: - Refresh loop

    func start() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    /// Re-fetches wait times and re-ranks. With `userInitiated`, drive times are also re-fetched
    /// instead of served from cache, but only if MapKit's request budget can absorb the whole batch
    /// without pausing.
    func refresh(userInitiated: Bool = false) async {
        guard !isRefreshing else { return }
        now = Clock.now
        if Self.schedule.hasEnded(at: now) {
            autoRefreshTask?.cancel()
            return   // the UI shows the "early voting ended" screen; nothing to fetch
        }
        isRefreshing = true
        errorMessage = nil
        do {
            sites = await SiteLocations.resolve(try await Self.fixtureSites() ?? waitService.fetchSites())
            lastRefresh = Clock.now
        } catch {
            errorMessage = "Wait times unavailable: \(error.localizedDescription)"
        }
        isRefreshing = false
        await recomputePlans(forceFreshTrips: userInitiated)
    }

    /// Recomputes drive times and the ranking. A new call cancels any batch still in flight;
    /// whatever that batch already fetched stays cached.
    func recomputePlans(forceFreshTrips: Bool = false) async {
        recomputeTask?.cancel()
        let task = Task { await computePlans(forceFreshTrips: forceFreshTrips) }
        recomputeTask = task
        await task.value
    }

    /// Requests a full batch would make: one outbound per site plus the exact return legs.
    private var fullBatchRequestCount: Int {
        let routable = sites.filter { $0.coordinate != nil }.count
        return routable + min(8, routable)
    }

    private func computePlans(forceFreshTrips: Bool) async {
        now = Clock.now
        var trips: [String: RoundTrip] = [:]
        if let origin {
            isComputingTrips = true
            tripProgress = nil
            // Tick the rate-limit countdown once a second while the batch runs; nothing else
            // updates it while the limiter is holding requests back.
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    let wait = await RequestThrottle.mapKit.delayUntilNextSlot
                    await MainActor.run { self?.throttleWait = wait }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            defer { ticker.cancel() }
            let key = Self.cacheKey(origin, avoidTolls: avoidTolls)
            var fresh = (tripCaches[key] ?? [:]).filter { now.timeIntervalSince($0.value.computedAt) < Self.tripTTL }
            if forceFreshTrips, await RequestThrottle.mapKit.availableSlots >= fullBatchRequestCount {
                fresh = [:]   // budget allows a full re-fetch with no waiting
            }
            // Show what we already know right away (cached trips, or wait-only ranking); the batch
            // below can take a while when the rate limiter is pausing.
            plans = Planner.plans(for: sites, trips: fresh, departing: now, schedule: Self.schedule, hasOrigin: false)
            let batch = await Planner.roundTrips(
                from: origin, to: sites, departing: now,
                closingAt: Self.schedule.hours(on: now)?.close,
                travel: TravelService(avoidTolls: avoidTolls),
                skipping: fresh,
                onProgress: { [weak self] done, total in
                    Task { @MainActor in self?.tripProgress = (done, total) }
                }
            )
            throttleWait = 0
            tripCaches[key] = batch.trips
            if batch.wasCancelled { return }   // a newer batch owns the UI now
            if batch.trips.values.contains(where: { $0.computedAt == now }) { lastTripFetch = now }
            isComputingTrips = false
            tripProgress = nil
            trips = batch.trips
            if let error = batch.firstError, errorMessage == nil {
                let reason = error.localizedDescription
                if batch.failedOutbound > 0 {
                    errorMessage = "Drive times unavailable for \(batch.failedOutbound) site\(batch.failedOutbound == 1 ? "" : "s"): \(reason)"
                } else if batch.failedInbound > 0 {
                    errorMessage = "Return-trip traffic unavailable for \(batch.failedInbound) site\(batch.failedInbound == 1 ? "" : "s"), using estimates: \(reason)"
                }
            }
        }
        plans = Planner.plans(for: sites, trips: trips, departing: now, schedule: Self.schedule, hasOrigin: origin != nil)
    }

    // MARK: - Origin

    func setOrigin(address: String) async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLocating = true
        let wakeCounty = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 35.79, longitude: -78.65),
                                          radius: 60_000, identifier: "wake")
        let found: CLLocation?
        do {
            found = try await CLGeocoder().geocodeAddressString(trimmed, in: wakeCounty).first?.location
            if found == nil { errorMessage = "Couldn't find “\(trimmed)”." }
        } catch {
            found = nil
            errorMessage = "Couldn't find “\(trimmed)”: \(error.localizedDescription)"
        }
        isLocating = false
        guard let found else { return }
        originAddress = trimmed
        setOrigin(found.coordinate)
        errorMessage = nil
        await recomputePlans()
    }

    func useCurrentLocation() async {
        isLocating = true
        let location: CLLocation
        do {
            location = try await LocationFinder.currentLocation()
        } catch {
            isLocating = false
            errorMessage = "Couldn't get your location: \(error.localizedDescription)"
            return
        }
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
            originAddress = [street, placemark.locality].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            if originAddress.isEmpty { originAddress = "Current location" }
        } else {
            originAddress = "Current location"
        }
        isLocating = false
        setOrigin(location.coordinate)
        errorMessage = nil
        await recomputePlans()
    }

    private func setOrigin(_ coordinate: CLLocationCoordinate2D) {
        origin = coordinate
        let defaults = UserDefaults.standard
        defaults.set(coordinate.latitude, forKey: Keys.latitude)
        defaults.set(coordinate.longitude, forKey: Keys.longitude)
    }

    /// Debug builds: `WVE_FIXTURE=/path/to/airtable.json` serves a saved Airtable response instead of
    /// fetching, so realistic rows can be screenshotted outside voting hours (pair with `WVE_NOW`).
    private static func fixtureSites() throws -> [VotingSite]? {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["WVE_FIXTURE"], !path.isEmpty else { return nil }
        return try WaitTimeService.parse(Data(contentsOf: URL(fileURLWithPath: path)))
        #else
        return nil
        #endif
    }

    private static func cacheKey(_ c: CLLocationCoordinate2D, avoidTolls: Bool) -> String {
        String(format: "%.4f,%.4f|%@", c.latitude, c.longitude, avoidTolls ? "notolls" : "any")
    }
}
