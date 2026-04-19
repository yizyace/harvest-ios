import SwiftUI
import WebKit

// Renders server-extracted article HTML. The server's `cached_content` is a
// full HTML document — we don't wrap it. A minimal stylesheet is injected so
// the reader matches the app's dynamic type + dark-mode.
struct ReaderWebView: UIViewRepresentable {

    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(styled(html: html), baseURL: nil)
    }

    private func styled(html: String) -> String {
        let css = """
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          :root { color-scheme: light dark; }
          body {
            font: -apple-system-body;
            line-height: 1.55;
            padding: 0 16px 24px;
            margin: 0;
            background: transparent;
            color: -apple-system-label;
          }
          img, video { max-width: 100%; height: auto; }
          pre, code { font-family: ui-monospace, monospace; }
          a { color: -apple-system-link; }
          h1, h2, h3 { line-height: 1.25; }
        </style>
        """
        if html.lowercased().contains("<head>") {
            return html.replacingOccurrences(
                of: "<head>",
                with: "<head>\(css)",
                options: .caseInsensitive
            )
        }
        return "<!doctype html><html><head>\(css)</head><body>\(html)</body></html>"
    }
}
