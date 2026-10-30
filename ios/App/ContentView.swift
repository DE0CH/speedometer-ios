import SwiftUI
import WebKit

/// The whole app: the "Paper" screen, one number over a rule with the unit and the speed's ± error. Tap anywhere to
/// switch km/h and mph. `Paper` is SwiftUI; Web/index.html is the approved mock's HTML, the reference it must match: the
/// replica draws every state both ways (`-reference` shows the HTML) and compares the screenshots pixel by pixel.
struct ContentView: View {
    @EnvironmentObject private var meter: Speedometer
    @AppStorage("mph") private var mph = false
    @Environment(\.colorScheme) private var scheme
    private let reference = ProcessInfo.processInfo.arguments.contains("-reference")

    var body: some View {
        Group {
            if reference {
                Reference(reading: reading.json, onTap: tap).ignoresSafeArea()
            } else {
                Paper(reading: reading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: tap)
                    .accessibilityElement(children: .contain)   // the texts stay separate elements for the replica
            }
        }
        .background((scheme == .dark ? Color(white: 0.067) : Color(red: 0.957, green: 0.949, blue: 0.933)).ignoresSafeArea())
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

    private var reading: Reading {
        let unit = mph ? "MPH" : "KM/H"
        switch meter.reading {
        case .waiting: return Reading(number: "– –", unit: unit, status: "FINDING GPS", speed: false)
        case .denied: return Reading(number: "– –", unit: unit, status: "LOCATION OFF · TAP", speed: false)
        case .speed(let ms, let accuracy):
            let factor = mph ? 2.236936 : 3.6
            // The speed's own error, in the shown unit, rounded up.
            let status = accuracy.map { "±\(max(1, Int(($0 * factor).rounded(.up)))) \(unit)" } ?? "GPS"
            return Reading(number: String(Int((ms * factor).rounded())), unit: unit, status: status, speed: true)
        }
    }
}

struct Reading: Equatable {
    var number, unit, status: String
    var speed: Bool
    var json: [String: Any] { ["number": number, "unit": unit, "status": status, "speed": speed] }
}

/// index.html's layout in SwiftUI, number for number: bottom-left, 20 pt from the sides and 56 pt from the bottom of the
/// safe area; the number in a CSS line box of 0.8 em over an 18 pt gap, a 2 pt rule, 8 pt, then the 12 pt unit row.
private struct Paper: View {
    let reading: Reading

    var body: some View {
        GeometryReader { geo in
            let screen = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            let size = Archivo.fit(reading, screen: screen, avail: geo.size.width - 40)
            VStack(alignment: .leading, spacing: 0) {
                Number(text: reading.number, size: size)
                    .opacity(reading.speed ? 1 : 0.25)
                    .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.35), value: screen)   // CSS `ease`, only on a resize
                Rectangle().frame(height: 2).padding(.top, 18)
                HStack(spacing: 0) {
                    Text(reading.unit)
                    Spacer(minLength: 0)
                    Text(reading.status)
                }
                .font(Font(Archivo.unit as CTFont))
                .tracking(12 * 0.18)
                .padding(.top, 8)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 56)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
    }
}

/// The number at an animatable font size, so a rotation morphs it the way the HTML's `transition: font-size` does.
private struct Number: View, Animatable {
    let text: String
    var size: CGFloat
    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    var body: some View {
        Text(text)
            .font(Font(Archivo.number(size) as CTFont))
            .tracking(-0.02 * size)
            .fixedSize()
            // CSS puts the baseline (line-height − ascent − descent)/2 + ascent below the top of the 0.8 em line box.
            .alignmentGuide(.top) { $0[.firstTextBaseline] - Archivo.baselineInLineBox * size }
            .frame(height: 0.8 * size, alignment: .topLeading)
    }
}

/// The Archivo variable font (OFL, bundled in Web/) at the HTML's settings.
enum Archivo {
    static let ascent: CGFloat = 0.878, descent: CGFloat = 0.210   // hhea / OS2 typo metrics, per em
    static let baselineInLineBox = (0.8 - ascent - descent) / 2 + ascent

    static func number(_ size: CGFloat) -> UIFont { font(size, weight: 900, width: 68, tabular: true) }
    static let unit = font(12, weight: 700, width: 100, tabular: false)

    /// The HTML's fit(): 82% of the screen width, at most 60% of its height, shrunk until the digits fit; the dashes
    /// a third of that.
    static func fit(_ reading: Reading, screen: CGSize, avail: CGFloat) -> CGFloat {
        let base = min(screen.width * 0.82, screen.height * 0.6)
        guard reading.speed else { return base / 3 }
        let at100 = (reading.number as NSString).size(withAttributes: [.font: number(100), .kern: -2]).width
        return min(base, avail / (at100 / 100))
    }

    private static let registered: Void = {
        if let url = Bundle.main.url(forResource: "Archivo", withExtension: "ttf", subdirectory: "Web") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    private static func font(_ size: CGFloat, weight: Int, width: Int, tabular: Bool) -> UIFont {
        _ = registered
        var attributes: [UIFontDescriptor.AttributeName: Any] = [
            .name: "Archivo-SemiBold",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):
                [0x7767_6874: weight, 0x7764_7468: width],   // 'wght', 'wdth'
        ]
        if tabular {
            attributes[.featureSettings] = [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                             UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]]
        }
        return UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
    }
}

private extension Color {
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.957, green: 0.949, blue: 0.933, alpha: 1) : UIColor(white: 0.067, alpha: 1) })
}

/// Web/index.html in a WKWebView, fed the same reading: the reference the replica compares `Paper` with.
private struct Reference: UIViewRepresentable {
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
