import Combine
import UIKit

/// The app: one screen, the speed as a number over a rule with the unit and the speed's ± error. Tap anywhere to switch
/// km/h and mph. UIKit throughout, so the number can ride iOS's rotation animation (`Paper.turning`).
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

/// `-reference` shows Web/index.html, the approved mock's HTML, instead of `Paper`: the replica draws every state both
/// ways and compares the screenshots pixel by pixel.
let reference = ProcessInfo.processInfo.arguments.contains("-reference")

struct Reading: Equatable {
    var number, unit, status: String
    var speed: Bool
    var json: [String: Any] { ["number": number, "unit": unit, "status": status, "speed": speed] }
}

final class Screen: UIViewController {
    private let meter: Speedometer
    private var latest = Speedometer.Reading.waiting
    private var mph = UserDefaults.standard.bool(forKey: "mph") {
        didSet { UserDefaults.standard.set(mph, forKey: "mph") }
    }
    private let paper = Paper()
    private lazy var html = Reference { [weak self] in self?.tap() }
    private var watching: AnyCancellable?

    init(meter: Speedometer) {
        self.meter = meter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = reference ? html : paper
        view.backgroundColor = .paper
        if !reference { view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap))) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        watching = meter.$reading.sink { [weak self] in   // fires before the property changes: use the value
            self?.latest = $0
            self?.show()
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    /// The rotation: everything is laid out again inside iOS's own animation for the turn, so the rule and the unit row
    /// move with it and the number goes from its old size to the new one on the same clock.
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        paper.turning = true
        coordinator.animate(alongsideTransition: { _ in
            self.paper.setNeedsLayout()
            self.paper.layoutIfNeeded()
        }, completion: { _ in
            self.paper.turning = false
            self.paper.setNeedsLayout()
        })
    }

    @objc private func tap() {
        if latest == .denied {
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        } else {
            mph.toggle()
            show()
        }
    }

    private func show() {
        let unit = mph ? "MPH" : "KM/H"
        let reading: Reading
        switch latest {
        case .waiting: reading = Reading(number: "– –", unit: unit, status: "FINDING GPS", speed: false)
        case .denied: reading = Reading(number: "– –", unit: unit, status: "LOCATION OFF · TAP", speed: false)
        case .speed(let ms, let accuracy):
            let factor = mph ? 2.236936 : 3.6
            // The speed's own error, in the shown unit, rounded up.
            let status = accuracy.map { "±\(max(1, Int(($0 * factor).rounded(.up)))) \(unit)" } ?? "GPS"
            reading = Reading(number: String(Int((ms * factor).rounded())), unit: unit, status: status, speed: true)
        }
        if reference { html.show(reading) } else { paper.reading = reading }
    }
}
