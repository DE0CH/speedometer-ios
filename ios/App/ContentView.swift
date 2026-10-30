import SwiftUI
import WebKit

/// The whole app: the "Paper" screen drawn by Web/index.html (the mock's own HTML and CSS), fed the GPS reading.
/// Tap anywhere to switch km/h and mph.
struct ContentView: View {
    @EnvironmentObject private var meter: Speedometer
    @AppStorage("mph") private var mph = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Screen(reading: reading, onTap: tap)
            .background((scheme == .dark ? Color(white: 0.067) : Color(red: 0.957, green: 0.949, blue: 0.933))
                .ignoresSafeArea())
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
    }

    private func tap() {
        if meter.reading == .denied {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        } else {
            mph.toggle()
        }
    }

    private var reading: [String: Any] {
        var number = "– –", status = "FINDING GPS", speed = false
        switch meter.reading {
        case .waiting: break
        case .denied: status = "LOCATION OFF · TAP"
        case .speed(let ms, let accuracy):
            number = String(Int((ms * (mph ? 2.236936 : 3.6)).rounded()))
            status = "GPS ±\(Int(accuracy.rounded())) M"
            speed = true
        }
        return ["number": number, "unit": mph ? "MPH" : "KM/H", "status": status, "speed": speed]
    }
}

/// A WKWebView showing Web/index.html; every new reading goes to the page's `update()`.
private struct Screen: UIViewRepresentable {
    let reading: [String: Any]
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "tap")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web")!
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.send(reading, to: web)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onTap: () -> Void = {}
        private var latest: [String: Any] = [:]
        private var loaded = false

        func send(_ reading: [String: Any], to web: WKWebView) {
            latest = reading
            guard loaded, let json = try? JSONSerialization.data(withJSONObject: reading),
                  let text = String(data: json, encoding: .utf8) else { return }
            web.evaluateJavaScript("update(\(text))")
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            send(latest, to: web)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            onTap()
        }
    }
}
