import Foundation
import MapKit

public struct RoundTrip: Sendable, Hashable {
    /// Driving time from origin to the site, departing now.
    public let outbound: TimeInterval
    /// Driving time back. When `inboundIsEstimate` is true this is a copy of `outbound`.
    public let inbound: TimeInterval
    public let inboundIsEstimate: Bool
    public let computedAt: Date

    public init(outbound: TimeInterval, inbound: TimeInterval, inboundIsEstimate: Bool, computedAt: Date) {
        self.outbound = outbound
        self.inbound = inbound
        self.inboundIsEstimate = inboundIsEstimate
        self.computedAt = computedAt
    }
}

/// Traffic-aware driving ETAs via Apple MapKit. No API key required.
public struct TravelService: Sendable {
    public var avoidTolls: Bool
    public var throttle: RequestThrottle

    public init(avoidTolls: Bool = false, throttle: RequestThrottle = .mapKit) {
        self.avoidTolls = avoidTolls
        self.throttle = throttle
    }

    public func eta(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D,
                    departing: Date) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.tollPreference = avoidTolls ? .avoid : .any
        request.departureDate = departing
        var attempt = 0
        while true {
            await throttle.acquire()
            do {
                return try await MKDirections(request: request).calculateETA().expectedTravelTime
            } catch where Self.isThrottle(error) && attempt < 2 {
                attempt += 1
                let delay = min(Self.resetDelay(from: error) ?? Double(attempt) * 3, 20)
                await throttle.backOff(for: delay)
                try await Task.sleep(for: .seconds(delay + 0.5))
            }
        }
    }

    // MARK: - Throttle detection

    static func isThrottle(_ error: Error) -> Bool {
        if let mk = error as? MKError, mk.code == .loadingThrottled { return true }
        return allUserInfo(of: error).contains { info in
            info["timeUntilReset"] != nil || (info["requestKindString"] as? String) != nil
        }
    }

    /// Seconds until MapKit's throttle window resets, read from the nested GEO error if present.
    static func resetDelay(from error: Error) -> TimeInterval? {
        for info in allUserInfo(of: error) {
            if let n = info["timeUntilReset"] as? NSNumber { return n.doubleValue + 0.5 }
            if let s = info["timeUntilReset"] as? String, let d = Double(s) { return d + 0.5 }
        }
        return nil
    }

    private static func allUserInfo(of error: Error) -> [[String: Any]] {
        let ns = error as NSError
        var infos: [[String: Any]] = [ns.userInfo]
        if let geo = ns.userInfo["MKErrorGEOErrorUserInfo"] as? [String: Any] {
            infos.append(geo)
            if let details = geo["details"] as? [[String: Any]] { infos += details }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            infos += allUserInfo(of: underlying)
        }
        return infos
    }
}
