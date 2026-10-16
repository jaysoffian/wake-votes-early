#if os(iOS)
import SwiftUI
import SafariServices

/// In-app Safari (SFSafariViewController): shows web pages and PDFs without leaving the app,
/// and carries its own "Open in Safari" and share buttons.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif

import Foundation

/// Identifiable wrapper so a URL can drive `.sheet(item:)`.
struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
