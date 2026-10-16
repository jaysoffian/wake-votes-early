import Foundation
import CoreLocation

/// Resolves site addresses to coordinates: a baked-in table first, then a persistent cache, then CLGeocoder.
public enum SiteLocations {
    /// Coordinates for the 2026 general election sites, keyed by normalized address.
    static let known: [String: (Double, Double)] = [
        "5900 whittier dr raleigh nc 27609": (35.8624839, -78.643695),
        "3808 edwards mill rd raleigh nc 27612": (35.8302524, -78.6983396),
        "7921 ray rd raleigh nc 27613": (35.8875799, -78.6989812),
        "4011 carya dr raleigh nc 27610": (35.770115, -78.568533),
        "4723 advantage way raleigh nc 27603": (35.650658, -78.699635),
        "7005 beech bluff park dr willow spring nc 27592": (35.5854968, -78.6792927),
        "9950 durant rd raleigh nc 27614": (35.9024286, -78.5796584),
        "601 w 3rd st wendell nc 27591": (35.782528, -78.3813742),
        "301 stinson ave holly springs nc 27540": (35.6465087, -78.8292532),
        "125 avery st garner nc 27529": (35.7121578, -78.6108256),
        "102 lawson ridge rd knightdale nc 27545": (35.8095294, -78.4820347),
        "505 martin luther king jr blvd raleigh nc 27601": (35.7695384, -78.6297234),
        "1220 varsity dr raleigh nc 27606": (35.7843415, -78.6852019),
        "101 wilkinson ave cary nc 27513": (35.7906337, -78.7805514),
        "53 hunter st apex nc 27502": (35.7336229, -78.8461042),
        "120 maury odell pl cary nc 27513": (35.7852061, -78.826136),
        "4621 shady greens dr fuquay varina nc 27526": (35.6323665, -78.7356202),
        "701 harris rd wake forest nc 27587": (35.99957, -78.51703),
    ]

    private static let cacheKey = "SiteLocations.geocodeCache"

    public static func normalize(_ address: String) -> String {
        let cleaned = address.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Fills in coordinates for every site, geocoding any address we don't already know.
    public static func resolve(_ sites: [VotingSite]) async -> [VotingSite] {
        var cache = (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: [Double]]) ?? [:]
        var result: [VotingSite] = []
        var cacheChanged = false
        let geocoder = CLGeocoder()

        for var site in sites {
            if site.coordinate != nil { result.append(site); continue }
            let key = normalize(site.address)
            if let hit = known[key] {
                site.latitude = hit.0; site.longitude = hit.1
            } else if let hit = cache[key], hit.count == 2 {
                site.latitude = hit[0]; site.longitude = hit[1]
            } else if let placemark = try? await geocoder.geocodeAddressString(site.address).first,
                      let loc = placemark.location {
                site.latitude = loc.coordinate.latitude; site.longitude = loc.coordinate.longitude
                cache[key] = [loc.coordinate.latitude, loc.coordinate.longitude]
                cacheChanged = true
                try? await Task.sleep(for: .milliseconds(300))
            }
            result.append(site)
        }
        if cacheChanged { UserDefaults.standard.set(cache, forKey: cacheKey) }
        return result
    }
}
