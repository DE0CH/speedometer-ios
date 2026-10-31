import WebKit

/// Web/index.html in a WKWebView, fed the same reading: the reference the replica compares `Paper` with.
final class Reference: WKWebView, WKScriptMessageHandler, WKNavigationDelegate {
    private let onTap: () -> Void
    private var latest: [String: Any] = [:]
    private var loaded = false

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
        configuration.userContentController.add(self, name: "tap")
        isOpaque = false
        scrollView.isScrollEnabled = false
        scrollView.contentInsetAdjustmentBehavior = .never
        navigationDelegate = self
        let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web")!
        loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ reading: Reading) {
        latest = reading.json
        guard loaded, let json = try? JSONSerialization.data(withJSONObject: latest),
              let text = String(data: json, encoding: .utf8) else { return }
        evaluateJavaScript("update(\(text))")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        if let json = try? JSONSerialization.data(withJSONObject: latest), let text = String(data: json, encoding: .utf8) {
            evaluateJavaScript("update(\(text))")
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { onTap() }
}
