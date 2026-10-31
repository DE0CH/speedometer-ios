import SwiftUI
import UIKit

/// The app is UIKit at the root so the number can ride the rotation: `viewWillTransition` hands over iOS's own
/// rotation animation, and the number's size change goes into it (same start, length and curve as the turn).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let meter = Speedometer()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = Screen(meter: meter)
        window.makeKeyAndVisible()
        self.window = window
    }

    // The screen stays on while the app is open; GPS runs only while it is on screen.
    func sceneDidBecomeActive(_ scene: UIScene) {
        UIApplication.shared.isIdleTimerDisabled = true
        meter.start()
    }

    func sceneWillResignActive(_ scene: UIScene) { UIApplication.shared.isIdleTimerDisabled = false }
    func sceneDidEnterBackground(_ scene: UIScene) { meter.stop() }
}

/// The SwiftUI screen (rule, unit row, taps) with the number drawn above it by `NumberView`.
final class Screen: UIViewController {
    private let meter: Speedometer
    private let number = NumberView()

    init(meter: Speedometer) {
        self.meter = meter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let content = UIHostingController(rootView: ContentView { [number] in number.reading = $0 }.environmentObject(meter))
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(content.view)
        content.didMove(toParent: self)
        guard !reference else { return }   // the HTML draws its own number
        number.frame = view.bounds
        number.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(number)
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        number.turn(with: coordinator)
    }
}

/// The number, where index.html puts it: left on the rule's 20 pt margin, its 0.8 em line box ending 18 pt above the
/// rule, the baseline placed by WebKit's rule (`Archivo.numberBaseline`). Laid out here by those numbers rather than by
/// a layout engine, so the end of a rotation is known before it starts.
final class NumberView: UIView {
    var reading: Reading? {
        didSet {
            guard reading != oldValue else { return }
            glyphs.alpha = reading?.speed == false ? 0.25 : 1
            setNeedsLayout()
        }
    }
    private let glyphs = Glyphs()
    private var turning = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false   // taps go to the SwiftUI screen below
        addSubview(glyphs)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The number's size and baseline-left point for a screen of `bounds` with these insets.
    private func spot(_ reading: Reading, size: CGFloat? = nil) -> (size: CGFloat, baseline: CGPoint) {
        let insets = window?.safeAreaInsets ?? safeAreaInsets
        let size = size ?? Archivo.fit(reading, screen: bounds.size, avail: bounds.width - insets.left - insets.right - 40)
        let boxBottom = bounds.height - insets.bottom - 56 - Archivo.normalLineHeight(12) - 8 - 2 - 18
        let baseline = boxBottom - 0.8 * size + Archivo.numberBaseline(size)
        let scale = window?.screen.scale ?? 3
        return (size, CGPoint(x: insets.left + 20, y: (baseline * scale).rounded() / scale))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !turning, let reading else { return }
        let (size, baseline) = spot(reading)
        glyphs.show(reading.number, size: size)
        glyphs.transform = .identity
        glyphs.center = baseline   // the anchor point is the baseline-left
    }

    /// The rotation: the rule and unit row are at their new place from the first frame of the turn, so the number
    /// stays on them and goes from its old size to the new one, as a scaled drawing, inside iOS's own animation. It is
    /// drawn at the larger size so it only ever shrinks (sharp), and is real text at the new size when the turn ends.
    func turn(with coordinator: UIViewControllerTransitionCoordinator) {
        guard let reading, window != nil else { return }
        let old = glyphs.transform.a * glyphs.size
        turning = true
        coordinator.animate(alongsideTransition: { _ in
            self.superview?.layoutIfNeeded()
            let start = self.spot(reading, size: old), end = self.spot(reading)
            let big = max(old, end.size)
            UIView.performWithoutAnimation {
                self.glyphs.show(reading.number, size: big)
                self.glyphs.transform = CGAffineTransform(scaleX: old / big, y: old / big)
                self.glyphs.center = start.baseline
            }
            self.glyphs.transform = CGAffineTransform(scaleX: end.size / big, y: end.size / big)
            self.glyphs.center = end.baseline
        }, completion: { _ in
            self.turning = false
            self.setNeedsLayout()
            self.layoutIfNeeded()
        })
    }
}

/// The digits drawn with Core Text at an exact baseline-left point (`origin`), which is also the layer's anchor
/// point, so a scale grows or shrinks the number from where it sits on the rule.
private final class Glyphs: UIView {
    private(set) var size: CGFloat = 0
    private var text = ""
    private var line: CTLine?
    private var origin = CGPoint.zero
    private var width: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Glyphs, _) in view.setNeedsDisplay() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ text: String, size: CGFloat) {
        guard text != self.text || size != self.size else { return }
        (self.text, self.size) = (text, size)
        let attributes: [NSAttributedString.Key: Any] = [.font: Archivo.number(size), .kern: -0.02 * size,
                                                         NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        self.line = line
        width = CTLineGetTypographicBounds(line, nil, nil, nil)
        // Whole points around the ink so the drawing lands on the pixel grid wherever the anchor goes.
        let pad = (0.15 * size).rounded(.up)
        origin = CGPoint(x: pad, y: (Archivo.ascent * size).rounded(.up) + pad)
        bounds = CGRect(x: 0, y: 0, width: width.rounded(.up) + 2 * pad, height: origin.y + (Archivo.descent * size).rounded(.up) + pad)
        layer.anchorPoint = CGPoint(x: origin.x / bounds.width, y: origin.y / bounds.height)
        accessibilityLabel = text
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let line, let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.ink.cgColor)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)   // Core Text draws y-up; this view is y-down
        context.textPosition = origin
        CTLineDraw(line, context)
    }

    // The line box, as the SwiftUI and HTML versions report it, not the padded drawing.
    override var accessibilityFrame: CGRect {
        get {
            let top = origin.y - Archivo.numberBaseline(size)
            return UIAccessibility.convertToScreenCoordinates(CGRect(x: origin.x, y: top, width: width, height: 0.8 * size), in: self)
        }
        set {}
    }
}
