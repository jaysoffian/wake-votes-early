import MapKit
import SwiftUI

enum Directions {
    /// Opens Apple Maps with driving directions to the site.
    static func open(_ site: VotingSite) {
        guard let coordinate = site.coordinate else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = site.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

enum Format {
    static func minutes(_ interval: TimeInterval?) -> String {
        guard let interval else { return "–" }
        let m = Int((interval / 60).rounded())
        if m >= 60 { return "\(m / 60) hr \(m % 60) min" }
        return "\(m) min"
    }

    /// Return leg, prefixed with ≈ when it is estimated from the outbound time rather than fetched.
    static func inbound(_ trip: RoundTrip) -> String {
        (trip.inboundIsEstimate ? "≈" : "") + minutes(trip.inbound) + " back"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

enum WaitColor {
    static func color(for minutes: Double?) -> Color {
        guard let minutes else { return .gray }
        switch minutes {
        case ..<1: return .green
        case ..<16: return .teal
        case ..<31: return .orange
        default: return .red
        }
    }

    static func color(forTotal total: TimeInterval?) -> Color {
        guard let total else { return .gray }
        switch total / 60 {
        case ..<30: return .green
        case ..<50: return .teal
        case ..<80: return .orange
        default: return .red
        }
    }
}
