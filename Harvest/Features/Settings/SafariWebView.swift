import SafariServices
import SwiftUI

// In-app Safari presentation for the privacy policy link. Used from both
// SignInView (unauthenticated) and SettingsView (authenticated) — the
// view controller has no dependency on session state.
struct SafariWebView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
