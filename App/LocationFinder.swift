import CoreLocation

enum LocationFinder {
    enum Error: Swift.Error, LocalizedError {
        case timeout
        case unavailable

        var errorDescription: String? {
            switch self {
            case .timeout: return "timed out waiting for a location fix."
            case .unavailable: return "location access is not available. Check System Settings › Privacy & Security › Location Services."
            }
        }
    }

    private static let manager = CLLocationManager()

    /// One current-location fix, prompting for permission if needed.
    static func currentLocation(timeout: Duration = .seconds(20)) async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location { return location }
                }
                throw Error.unavailable
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Error.timeout
            }
            guard let first = try await group.next() else { throw Error.unavailable }
            group.cancelAll()
            return first
        }
    }
}
