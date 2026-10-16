import Foundation
import CoreLocation

// Usage: wakevote-cli [--no-tolls] [lat,lon | "street address"]
// Prints every early-voting site ranked by drive + wait + drive back.

func minutes(_ t: TimeInterval?) -> String {
    guard let t else { return "  --" }
    return String(format: "%4d", Int((t / 60).rounded()))
}

/// Honors https_proxy like curl does, so the tool works behind an explicit proxy (URLSession ignores the env var).
final class ProxyAuth: NSObject, URLSessionDelegate {
    let user: String, password: String
    init(user: String, password: String) { self.user = user; self.password = password }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.isProxy() {
            completionHandler(.useCredential, URLCredential(user: user, password: password, persistence: .forSession))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

func makeSession() -> URLSession {
    let env = ProcessInfo.processInfo.environment
    guard let raw = env["https_proxy"] ?? env["HTTPS_PROXY"], let proxy = URL(string: raw),
          let host = proxy.host, let port = proxy.port else { return .shared }
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPSEnable as String: 1,
        kCFNetworkProxiesHTTPSProxy as String: host,
        kCFNetworkProxiesHTTPSPort as String: port,
    ]
    var delegate: URLSessionDelegate?
    if let user = proxy.user, let password = proxy.password {
        delegate = ProxyAuth(user: user, password: password)
        config.connectionProxyDictionary?[kCFProxyUsernameKey as String] = user
        config.connectionProxyDictionary?[kCFProxyPasswordKey as String] = password
    }
    return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
}

func run() async {
    var args = Array(CommandLine.arguments.dropFirst())
    let avoidTolls = args.contains("--no-tolls")
    args.removeAll { $0 == "--no-tolls" }
    var origin = CLLocationCoordinate2D(latitude: 35.7796, longitude: -78.6382) // downtown Raleigh default
    var originLabel = "downtown Raleigh (default)"
    if let arg = args.first {
        let parts = arg.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 {
            origin = CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1]); originLabel = arg
        } else {
            do {
                guard let loc = try await CLGeocoder().geocodeAddressString(arg).first?.location else {
                    print("Could not geocode: \(arg)"); exit(2)
                }
                origin = loc.coordinate; originLabel = arg
            } catch { print("Geocode failed: \(error.localizedDescription)"); exit(2) }
        }
    }
    print("Origin: \(originLabel) (\(origin.latitude), \(origin.longitude))\(avoidTolls ? ", avoiding tolls" : "")")

    let t0 = Date()
    let sites: [VotingSite]
    do {
        if let fixture = ProcessInfo.processInfo.environment["WAKEVOTE_FIXTURE"] {
            sites = await SiteLocations.resolve(try WaitTimeService.parse(Data(contentsOf: URL(fileURLWithPath: fixture))))
        } else {
            sites = await SiteLocations.resolve(try await WaitTimeService(session: makeSession()).fetchSites())
        }
    } catch { print("Wait-time fetch failed: \(error.localizedDescription)"); exit(1) }
    print("Fetched \(sites.count) sites in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s; " +
          "\(sites.filter { $0.coordinate == nil }.count) without coordinates")

    let now = Date()
    let t1 = Date()
    let close = EarlyVotingSchedule.wake2026General.hours(on: now)?.close
    let batch = await Planner.roundTrips(from: origin, to: sites, departing: now, closingAt: close,
                                         travel: TravelService(avoidTolls: avoidTolls))
    let trips = batch.trips, etaError = batch.firstError
    let exact = trips.values.filter { !$0.inboundIsEstimate }.count
    print("Computed \(trips.count) round trips (\(trips.count + exact) ETA requests, \(exact) exact return legs) in \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
    if let etaError { print("ETA error (\(batch.failedOutbound) outbound, \(batch.failedInbound) return legs failed): \(etaError.localizedDescription)") }

    let plans = Planner.plans(for: sites, trips: trips, departing: now, schedule: .wake2026General, hasOrigin: true)
    let fmt = DateFormatter(); fmt.timeStyle = .short; fmt.timeZone = TimeZone(identifier: "America/New_York")
    print("")
    print(" #  total  drive  wait  back  status                 updated  site      (~ = return leg estimated)")
    for (i, p) in plans.enumerated() {
        let status: String
        switch p.status {
        case .open: status = "open, closes \(fmt.string(from: p.hours!.close))"
        case .opensLater(let d): status = "opens \(fmt.string(from: d))"
        case .closesBeforeArrival: status = "CLOSES BEFORE ARRIVAL"
        case .closedForDay: status = "closed for the day"
        case .noVotingToday: status = "no early voting today"
        case .noRoute: status = "no route"
        }
        let updated = p.site.waitUpdatedAt.map { "\(Int(-$0.timeIntervalSinceNow / 60))m ago" } ?? "?"
        print(String(format: "%2d  %@   %@  %@  %@  %-22@ %7@  %@ [%@]",
                     i + 1, minutes(p.total), minutes(p.trip?.outbound), minutes(p.waitMinutes.map { $0 * 60 }),
                     minutes(p.trip?.inbound) + ((p.trip?.inboundIsEstimate ?? false) ? "~" : " "), status, updated, p.site.name, p.site.waitDisplay))
    }
    exit(0)
}

Task { await run() }
dispatchMain()
