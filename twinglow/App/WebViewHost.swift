import SwiftUI
import UIKit
import WebKit

/// Puts an existing WKWebView on screen. The web view itself lives in `WebTab`,
/// so switching accounts only moves views around and never reloads a page.
struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WebHostView {
        WebHostView()
    }

    func updateUIView(_ uiView: WebHostView, context: Context) {
        uiView.host(webView)
    }
}

final class WebHostView: UIView {
    private weak var hosted: WKWebView?

    func host(_ webView: WKWebView) {
        if hosted === webView, webView.superview === self { return }
        if let old = hosted, old !== webView, old.superview === self {
            old.removeFromSuperview()
        }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        hosted = webView
    }
}
