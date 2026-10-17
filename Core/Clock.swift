import Foundation

/// The app's notion of "now". In debug builds the `WVE_NOW` environment variable (ISO 8601,
/// e.g. `2026-11-01T10:00:00-04:00`) overrides it so the schedule logic can be tested on any date.
public enum Clock {
    public static var now: Date { override ?? Date() }

    private static let override: Date? = {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["WVE_NOW"] else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
        #else
        return nil
        #endif
    }()
}
