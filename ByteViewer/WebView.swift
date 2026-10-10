import SwiftUI
import WebKit

/// Live state of the web view, shared with the SwiftUI layer.
final class WebViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var errorMessage: String?

    weak var webView: WKWebView?

    func reload() { webView?.reload() }
    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func load(_ url: URL) { webView?.load(URLRequest(url: url)) }
}

enum UserAgent {
    /// Exact Safari user agent so sites serve the same layout they give Safari.
    /// (The stock WKWebView UA lacks "Version/x Safari/x" and some sites degrade or block it.)
    static func string(desktop: Bool) -> String {
        if desktop {
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        }
        let version = UIDevice.current.systemVersion
        let major = version.split(separator: ".").first.map(String.init) ?? "17"
        let underscored = version.replacingOccurrences(of: ".", with: "_")
        let device = UIDevice.current.userInterfaceIdiom == .pad
            ? "iPad; CPU OS \(underscored)"
            : "iPhone; CPU iPhone OS \(underscored)"
        return "Mozilla/5.0 (\(device) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).0 Mobile/15E148 Safari/604.1"
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let desktopMode: Bool
    let edgeToEdge: Bool
    @ObservedObject var model: WebViewModel
    var onShowControls: () -> Void = {}

    /// Appends `viewport-fit=cover` to the page's viewport meta so it draws under the
    /// notch and home indicator and `env(safe-area-inset-*)` works. Pages that have no
    /// viewport meta at all (desktop-only sites) are left alone.
    private static let edgeToEdgeScript = """
    (function () {
      var meta = document.querySelector('meta[name="viewport"]');
      if (meta && !/viewport-fit/i.test(meta.content)) {
        meta.content = meta.content + ', viewport-fit=cover';
      }
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()          // keeps cookies / logins between launches
        config.defaultWebpagePreferences.preferredContentMode = desktopMode ? .desktop : .mobile
        config.preferences.isElementFullscreenEnabled = true   // lets video players go fullscreen
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        if edgeToEdge {
            config.userContentController.addUserScript(
                WKUserScript(source: Self.edgeToEdgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = UserAgent.string(desktop: desktopMode)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.backgroundColor = .systemBackground
        webView.isOpaque = true

        // The web view is laid out edge-to-edge (see SiteView). Leaving the inset behaviour
        // on `.automatic` makes WebKit treat the safe areas exactly like Safari does:
        // pages without `viewport-fit=cover` are laid out inside the safe area, pages with it
        // get the full screen plus working `env(safe-area-inset-*)` values.
        // Setting `.never` here would push content under the status bar / notch.
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        // Three-finger tap brings the floating controls back after hiding them.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleThreeFingerTap))
        tap.numberOfTouchesRequired = 3
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)

        context.coordinator.observe(webView)
        model.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
        var parent: WebView
        private var observations: [NSKeyValueObservation] = []

        init(_ parent: WebView) {
            self.parent = parent
        }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.estimatedProgress) { [weak self] wv, _ in self?.parent.model.progress = wv.estimatedProgress },
                webView.observe(\.isLoading) { [weak self] wv, _ in self?.parent.model.isLoading = wv.isLoading },
                webView.observe(\.canGoBack) { [weak self] wv, _ in self?.parent.model.canGoBack = wv.canGoBack },
                webView.observe(\.canGoForward) { [weak self] wv, _ in self?.parent.model.canGoForward = wv.canGoForward },
                webView.observe(\.url) { [weak self] wv, _ in self?.parent.model.currentURL = wv.url },
            ]
        }

        func stopObserving() {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
        }

        @objc func handleRefresh() {
            parent.model.webView?.reload()
        }

        @objc func handleThreeFingerTap() {
            parent.onShowControls()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            switch url.scheme?.lowercased() {
            case "http", "https", "about", "blob", "data", "javascript":
                decisionHandler(.allow)
            default:
                // mailto:, tel:, sms:, maps:, app links … hand them to the system.
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.model.errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            parent.model.errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handle(error, in: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handle(error, in: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        private func handle(_ error: Error, in webView: WKWebView) {
            webView.scrollView.refreshControl?.endRefreshing()
            let nsError = error as NSError
            // Cancelled loads and policy-change interruptions are not real errors.
            if nsError.code == NSURLErrorCancelled || nsError.code == 102 { return }
            parent.model.errorMessage = nsError.localizedDescription
        }

        // MARK: Popups & JavaScript dialogs

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // target="_blank" links open in the same view instead of being dropped.
            if navigationAction.targetFrame?.isMainFrame != true {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(alert, fallback: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(alert) { completionHandler(false) }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text ?? "")
            })
            present(alert) { completionHandler(nil) }
        }

        private func present(_ alert: UIAlertController, fallback: @escaping () -> Void) {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            var top = scene?.keyWindow?.rootViewController
            while let presented = top?.presentedViewController {
                top = presented
            }
            guard let presenter = top else {
                fallback()
                return
            }
            presenter.present(alert, animated: true)
        }
    }
}
