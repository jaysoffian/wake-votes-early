import Foundation

/// Reads the public Airtable shared view that Wake County uses for its wait-time tracker.
///
/// The share page embeds a signed URL for an internal JSON endpoint (`readSharedViewData`).
/// We fetch the page, extract that URL, then call it with the headers the Airtable web client sends.
public struct WaitTimeService: Sendable {
    public static let shareURL = URL(string: "https://airtable.com/appAL6KsUEvshj4br/shrQkIIFla4bjdGzh")!
    static let applicationID = "appAL6KsUEvshj4br"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    public enum Error: Swift.Error, LocalizedError {
        case endpointNotFound
        case httpStatus(Int)
        case malformedResponse(String)

        public var errorDescription: String? {
            switch self {
            case .endpointNotFound: return "Could not find the wait-time data endpoint on the Airtable page."
            case .httpStatus(let code): return "Airtable returned HTTP \(code)."
            case .malformedResponse(let what): return "Unexpected Airtable response: \(what)."
            }
        }
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchSites() async throws -> [VotingSite] {
        let endpoint = try await discoverEndpoint()
        var request = URLRequest(url: endpoint)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.applicationID, forHTTPHeaderField: "x-airtable-application-id")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
        request.setValue("America/New_York", forHTTPHeaderField: "x-time-zone")
        request.setValue("en", forHTTPHeaderField: "x-user-locale")
        request.setValue("webClient", forHTTPHeaderField: "x-airtable-inter-service-client")
        request.setValue(Self.shareURL.absoluteString, forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Error.httpStatus(http.statusCode)
        }
        return try Self.parse(data)
    }

    func discoverEndpoint() async throws -> URL {
        var request = URLRequest(url: Self.shareURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { throw Error.endpointNotFound }
        return try Self.extractEndpoint(fromHTML: html)
    }

    /// Finds the signed `readSharedViewData` URL embedded (JS-escaped) in the share page.
    static func extractEndpoint(fromHTML html: String) throws -> URL {
        let slash = #"(?:\\u002F|/)"#
        let pattern = "\(slash)v0\\.3\(slash)view\(slash)viw[A-Za-z0-9]+\(slash)readSharedViewData\\?[^\"'\\\\\\s<]*"
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else { throw Error.endpointNotFound }
        let path = String(html[range])
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: "https://airtable.com" + path) else { throw Error.endpointNotFound }
        return url
    }

    // MARK: - Parsing

    static func parse(_ data: Data) throws -> [VotingSite] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let table = payload["table"] as? [String: Any],
              let columns = table["columns"] as? [[String: Any]],
              let rows = table["rows"] as? [[String: Any]] else {
            throw Error.malformedResponse("missing table")
        }

        var nameCol: String?, waitCol: String?, addressCol: String?, updatedCol: String?, photoCol: String?
        var waitChoices: [String: String] = [:]
        for column in columns {
            guard let id = column["id"] as? String, let name = column["name"] as? String else { continue }
            let type = column["type"] as? String ?? ""
            let lower = name.lowercased()
            if type == "select" && waitCol == nil {
                waitCol = id
                if let options = column["typeOptions"] as? [String: Any],
                   let choices = options["choices"] as? [String: [String: Any]] {
                    for (choiceID, choice) in choices {
                        if let label = choice["name"] as? String { waitChoices[choiceID] = label }
                    }
                }
            } else if lower == "name" || (type == "text" && nameCol == nil && lower.contains("name")) {
                nameCol = id
            } else if lower.contains("address") {
                addressCol = id
            } else if lower.contains("updated") {
                updatedCol = id
            } else if type == "multipleAttachment" {
                photoCol = id
            }
        }
        guard let nameCol, let addressCol else { throw Error.malformedResponse("missing name/address columns") }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let cells = row["cellValuesByColumnId"] as? [String: Any],
                  let name = cells[nameCol] as? String,
                  let address = cells[addressCol] as? String else { return nil }
            var waitLabel: String?
            if let waitCol, let choiceID = cells[waitCol] as? String {
                waitLabel = waitChoices[choiceID] ?? choiceID
            }
            var updated: Date?
            if let updatedCol, let stamp = cells[updatedCol] as? String {
                updated = isoFractional.date(from: stamp) ?? iso.date(from: stamp)
            }
            var photo: URL?
            if let photoCol, let attachments = cells[photoCol] as? [[String: Any]], let first = attachments.first {
                let urlString = (first["largeThumbUrl"] as? String) ?? (first["url"] as? String)
                photo = urlString.flatMap(URL.init(string:))
            }
            return VotingSite(id: id, name: name.trimmingCharacters(in: .whitespaces),
                              address: address.trimmingCharacters(in: .whitespaces),
                              waitLabel: waitLabel, waitUpdatedAt: updated, photoURL: photo)
        }
    }
}
