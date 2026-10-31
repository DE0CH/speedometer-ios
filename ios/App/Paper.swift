import UIKit

/// index.html's layout, number for number, placed by hand rather than by a layout engine: 20 pt from the sides and 56 pt
/// from the bottom of the safe area, the 12 pt unit row (WebKit's `line-height: normal`), 8 pt, a 2 pt rule, 18 pt, then
/// the number in a CSS line box of 0.8 em, its baseline where WebKit puts it (`Archivo.numberBaseline`).
final class Paper: UIView {
    var reading: Reading? {
        didSet { if reading != oldValue { setNeedsLayout() } }
    }
    /// Set for the length of a rotation: the number is then a scaled drawing going from its old size to the new one,
    /// drawn at the larger of the two so it only ever shrinks (sharp), and real text at the new size once the turn ends.
    var turning = false

    private let number = Label(kern: -0.02) { Archivo.number($0) }
    private let unit = Label(kern: 0.18) { _ in Archivo.unit }
    private let status = Label(kern: 0.18) { _ in Archivo.unit }
    private let rule = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        rule.backgroundColor = .ink
        [number, rule, unit, status].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let reading else { return }
        let scale = window?.screen.scale ?? 3
        func pixel(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let left = safeAreaInsets.left + 20, right = bounds.width - safeAreaInsets.right - 20

        let rowHeight = Archivo.normalLineHeight(12)
        let rowTop = bounds.height - safeAreaInsets.bottom - 56 - rowHeight
        let rowBaseline = pixel(rowTop + Archivo.baseline(12, lineHeight: rowHeight))
        unit.show(reading.unit, size: 12)
        unit.center = CGPoint(x: left, y: rowBaseline)   // a label's center is its baseline-left point
        status.show(reading.status, size: 12)
        status.center = CGPoint(x: pixel(right - status.width), y: rowBaseline)
        rule.frame = CGRect(x: left, y: rowTop - 8 - 2, width: right - left, height: 2)

        let size = Archivo.fit(reading, screen: bounds.size, avail: right - left)
        let boxTop = rule.frame.minY - 18 - 0.8 * size
        let baseline = CGPoint(x: left, y: pixel(boxTop + Archivo.numberBaseline(size)))
        number.alpha = reading.speed ? 1 : 0.25
        if turning {
            let shown = number.size * number.transform.a, big = max(shown, size)
            UIView.performWithoutAnimation {
                number.show(reading.number, size: big)
                number.transform = CGAffineTransform(scaleX: shown / big, y: shown / big)
            }
            number.transform = CGAffineTransform(scaleX: size / big, y: size / big)
        } else {
            number.show(reading.number, size: size)
            number.transform = .identity
        }
        number.center = baseline
    }
}

/// One line of Archivo drawn with Core Text at an exact baseline-left point, which is also the layer's anchor point:
/// `center` places the baseline, and a scale grows or shrinks the text from where it sits.
private final class Label: UIView {
    private(set) var size: CGFloat = 0
    private(set) var width: CGFloat = 0   // the advance, letter spacing included, as CSS measures it
    private let kern: CGFloat             // letter spacing, per em
    private let font: (CGFloat) -> UIFont
    private var text = ""
    private var line: CTLine?
    private var origin = CGPoint.zero

    init(kern: CGFloat, font: @escaping (CGFloat) -> UIFont) {
        (self.kern, self.font) = (kern, font)
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (label: Label, _) in label.setNeedsDisplay() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ text: String, size: CGFloat) {
        guard text != self.text || size != self.size else { return }
        (self.text, self.size) = (text, size)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(size), .kern: kern * size,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        self.line = line
        width = CTLineGetTypographicBounds(line, nil, nil, nil)
        // Whole points of room around the ink, so the drawing stays on the pixel grid wherever the anchor goes.
        let pad = (0.15 * size).rounded(.up)
        origin = CGPoint(x: pad, y: (Archivo.ascent * size).rounded(.up) + pad)
        bounds = CGRect(x: 0, y: 0, width: width.rounded(.up) + 2 * pad,
                        height: origin.y + (Archivo.descent * size).rounded(.up) + pad)
        layer.anchorPoint = CGPoint(x: origin.x / bounds.width, y: origin.y / bounds.height)
        accessibilityLabel = text
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let line, let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.ink.cgColor)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)   // Core Text draws y-up; the view is y-down
        context.textPosition = origin
        CTLineDraw(line, context)
    }

    // The text's own box (ascent to descent), not the padded drawing.
    override var accessibilityFrame: CGRect {
        get {
            let box = CGRect(x: origin.x, y: origin.y - Archivo.ascent * size, width: width,
                             height: (Archivo.ascent + Archivo.descent) * size)
            return UIAccessibility.convertToScreenCoordinates(box, in: self)
        }
        set {}
    }
}

/// The Archivo variable font (OFL, bundled in Web/) at the HTML's settings.
enum Archivo {
    static let ascent: CGFloat = 0.878, descent: CGFloat = 0.210   // hhea / OS2 typo metrics, per em

    /// Where WebKit puts the baseline in a line box: half the leading, (line height − ascent − descent)/2, above the
    /// ascent, with ascent and descent rounded to whole points as WebKit does.
    static func baseline(_ size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let (a, d) = ((ascent * size).rounded(), (descent * size).rounded())
        return (lineHeight - a - d) / 2 + a
    }

    /// The number's baseline in its 0.8 em line box. WebKit keeps the part below the baseline,
    /// (line height − ascent + descent)/2, a whole number of points (measured against the HTML in the replica: 87, 128
    /// and the dashes all land on the same pixel only this way).
    static func numberBaseline(_ size: CGFloat) -> CGFloat {
        let lineHeight = 0.8 * size
        return lineHeight - ((lineHeight - ascent * size + descent * size) / 2).rounded()
    }

    /// CSS `line-height: normal`: the rounded ascent plus the rounded descent (Archivo has no line gap).
    static func normalLineHeight(_ size: CGFloat) -> CGFloat { (ascent * size).rounded() + (descent * size).rounded() }

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

extension UIColor {
    static let ink = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.957, green: 0.949, blue: 0.933, alpha: 1) : UIColor(white: 0.067, alpha: 1) }
    static let paper = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.067, alpha: 1) : UIColor(red: 0.957, green: 0.949, blue: 0.933, alpha: 1) }
}
