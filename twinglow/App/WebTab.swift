import Combine
import UIKit
import WebKit

/// A window a page opened (sign-in pop-ups, links with target="_blank").
struct PopupWindow: Identifiable {
    let id = UUID()
    let webView: WKWebView
}

/// The live web view for one account, plus the bits of its state the toolbar shows.
@MainActor
final class WebTab: NSObject, ObservableObject {
    let accountID: UUID
    let webView: WKWebView
    private(set) var home: URL

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentURL: URL?
    @Published private(set) var loadError: String?
    @Published var popup: PopupWindow?

    private let refreshControl = UIRefreshControl()

    /// Look like Safari, so sites don't treat this as an unknown in-app browser.
    static var userAgentSuffix: String {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return "Version/\(major).0 Mobile/15E148 Safari/604.1"
    }

    private static let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "javascript", "file"]

    init(account: Account) {
        accountID = account.id
        home = account.home

        let configuration = WKWebViewConfiguration()
        // The heart of the app: a separate, persistent cookie jar for every account.
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.id)
        configuration.applicationNameForUserAgent = WebTab.userAgentSuffix
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground

        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
        webView.publisher(for: \.isLoading).assign(to: &$isLoading)
        webView.publisher(for: \.estimatedProgress).assign(to: &$progress)
        webView.publisher(for: \.url).assign(to: &$currentURL)

        webView.load(URLRequest(url: home))
    }

    // MARK: Actions

    func goHome() {
        loadError = nil
        webView.load(URLRequest(url: home))
    }

    func updateHome(_ url: URL) {
        home = url
    }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else {
            retry()
        }
    }

    func retry() {
        loadError = nil
        if webView.url == nil {
            goHome()
        } else {
            webView.reload()
        }
    }

    func openInSafari(_ url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func closePopup() {
        popup?.webView.stopLoading()
        popup = nil
    }

    func tearDown() {
        closePopup()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    @objc private func pullToRefresh() {
        retry()
    }

    private func finishedLoading() {
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
    }

    private func handle(_ error: Error, in view: WKWebView) {
        finishedLoading()
        guard view === webView else { return }
        let nsError = error as NSError
        // Cancelled loads and downloads WebKit hands off are not real failures.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        loadError = nsError.localizedDescription
    }
}

// MARK: - Navigation

extension WebTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased() else { return .allow }
        if WebTab.webSchemes.contains(scheme) { return .allow }
        // mailto:, tel:, App Store links and other apps' links go to the system.
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView {
            loadError = nil
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishedLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error, in: webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS may stop a page that sat in the background for a long time; bring it back.
        webView.reload()
    }
}

// MARK: - Pop-ups and page dialogs

extension WebTab: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Must use the configuration WebKit hands over: it carries this account's
        // data store and the link back to the page that opened the window.
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.navigationDelegate = self
        child.uiDelegate = self
        child.allowsBackForwardNavigationGestures = true
        popup = PopupWindow(webView: child)
        return child
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup?.webView {
            popup = nil
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await Dialogs.alert(title: frame.request.url?.host(), message: message)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await Dialogs.confirm(title: frame.request.url?.host(), message: message)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        await Dialogs.prompt(title: frame.request.url?.host(), message: prompt, defaultText: defaultText)
    }
}
