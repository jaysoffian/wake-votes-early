import Foundation

/// Client-side rate limiter for MapKit directions requests.
///
/// MapKit allows roughly 50 ETA requests per 60 seconds per app (keyed by bundle ID, so the window
/// survives relaunches) before it returns `loadingThrottled` errors. We stay under that with a
/// sliding window, persisted across launches, and queue the rest.
public actor RequestThrottle {
    public static let mapKit = RequestThrottle(limit: 40, window: 60, storageKey: "RequestThrottle.mapKit")

    private let limit: Int
    private let window: TimeInterval
    private let storageKey: String?
    private var stamps: [Date]

    public init(limit: Int, window: TimeInterval, storageKey: String? = nil) {
        self.limit = limit
        self.window = window
        self.storageKey = storageKey
        let now = Date()
        if let storageKey, let saved = UserDefaults.standard.array(forKey: storageKey) as? [Date] {
            stamps = saved.filter { now.timeIntervalSince($0) < window }
        } else {
            stamps = []
        }
    }

    /// Waits until a request slot is available, then claims it.
    public func acquire() async {
        while true {
            let now = Date()
            stamps.removeAll { now.timeIntervalSince($0) >= window }
            if stamps.count < limit {
                stamps.append(now)
                persist()
                return
            }
            if Task.isCancelled { return }
            let wait = window - now.timeIntervalSince(stamps[0]) + 0.25
            try? await Task.sleep(for: .seconds(max(wait, 0.25)))
        }
    }

    /// The server told us to back off: block new requests for `seconds`.
    public func backOff(for seconds: TimeInterval) {
        let pretend = Date().addingTimeInterval(seconds - window)
        stamps = Array(repeating: pretend, count: limit)
        persist()
    }

    /// Requests that could start right now without waiting.
    public var availableSlots: Int {
        let now = Date()
        return max(0, limit - stamps.filter { now.timeIntervalSince($0) < window }.count)
    }

    /// Seconds until the next slot frees up, or 0 if one is available now.
    public var delayUntilNextSlot: TimeInterval {
        let now = Date()
        let live = stamps.filter { now.timeIntervalSince($0) < window }
        guard live.count >= limit, let oldest = live.first else { return 0 }
        return max(0, window - now.timeIntervalSince(oldest))
    }

    private func persist() {
        guard let storageKey else { return }
        UserDefaults.standard.set(stamps, forKey: storageKey)
    }
}
