import Foundation
import CoreLocation

/// One early-voting site as published by Wake County, plus its resolved coordinate.
public struct VotingSite: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    /// Raw label from the county tracker, e.g. "15-30 Minutes".
    public let waitLabel: String?
    public let waitUpdatedAt: Date?
    public let photoURL: URL?
    public var latitude: Double?
    public var longitude: Double?
    /// The county's "Site Details" PDF (parking, entrance, accessibility), when known.
    public var detailsURL: URL?

    public init(id: String, name: String, address: String, waitLabel: String?, waitUpdatedAt: Date?,
                photoURL: URL?, latitude: Double? = nil, longitude: Double? = nil, detailsURL: URL? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.waitLabel = waitLabel
        self.waitUpdatedAt = waitUpdatedAt
        self.photoURL = photoURL
        self.latitude = latitude
        self.longitude = longitude
        self.detailsURL = detailsURL
    }

    public var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Midpoint of the published wait bucket, in minutes.
    public var waitMinutes: Double? { WaitEstimate.minutes(from: waitLabel) }

    /// Short form of the wait label for display, e.g. "15-30 min".
    public var waitDisplay: String {
        guard let waitLabel, !waitLabel.isEmpty else { return "Wait unknown" }
        return waitLabel
            .replacingOccurrences(of: "Minutes", with: "min")
            .replacingOccurrences(of: "minutes", with: "min")
            .replacingOccurrences(of: "Hours", with: "hr")
            .replacingOccurrences(of: "hours", with: "hr")
    }
}

public enum WaitEstimate {
    /// Converts a bucket label ("No Wait", "5-15 Minutes", "60+ Minutes", "1-2 Hours") to a midpoint in minutes.
    public static func minutes(from label: String?) -> Double? {
        guard let raw = label?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.contains("no wait") || lower.contains("none") { return 0 }
        let numbers = lower.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
        let scale: Double = lower.contains("hour") || lower.contains("hr") ? 60 : 1
        if numbers.count >= 2 { return (numbers[0] + numbers[1]) / 2 * scale }
        if let n = numbers.first {
            let openEnded = lower.contains("+") || lower.contains("over") || lower.contains("more")
            return (openEnded ? n + 15 : n) * scale
        }
        return nil
    }
}
