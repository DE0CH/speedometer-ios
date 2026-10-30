import CoreLocation
import XCTest

/// The phone replica: every flow on the simulator, with simulated GPS fixes carrying a speed.
final class SpeedometerUITests: XCTestCase {
    func testEveryFlow() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "location") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        allowLocation()
        // The screen is a web page: its texts show up as static texts labelled with what they say.
        func shows(_ text: String) -> Bool { app.staticTexts[text].exists }
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10), "no screen")
        XCTAssertTrue(wait(10) { shows("KM/H") || shows("MPH") }, "no unit on screen")
        shot(app, "launch")
        if shows("MPH") { app.tap() }   // a previous run left mph on

        // 87 km/h.
        drive(24.17)
        XCTAssertTrue(wait(15) { shows("87") }, "no 87: \(texts(app))")
        XCTAssertTrue(shows("KM/H"))
        XCTAssertTrue(shows("±2 KM/H"), "speed accuracy: \(texts(app))")
        shot(app, "87-kmh")

        // Tap: mph, and back.
        app.tap()
        XCTAssertTrue(wait(5) { shows("MPH") && shows("54") && shows("±2 MPH") }, "mph: \(texts(app))")
        shot(app, "54-mph")
        app.tap()
        XCTAssertTrue(wait(5) { shows("KM/H") && shows("87") }, "back to km/h: \(texts(app))")

        // Parked: jitter reads 0.
        drive(0.4)
        XCTAssertTrue(wait(15) { shows("0") }, "parked: \(texts(app))")
        shot(app, "0-parked")

        // Three digits still fit.
        drive(35.56)
        XCTAssertTrue(wait(15) { shows("128") }, "fast: \(texts(app))")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.frame.contains(app.staticTexts["128"].frame), "128 runs off the screen: \(app.staticTexts["128"].frame)")
        shot(app, "128-kmh")

        // Landscape: the number morphs to the new size and stays on screen.
        XCUIDevice.shared.orientation = .landscapeLeft
        drive(35.56)
        _ = wait(2) { false }
        XCTAssertTrue(wait(15) { shows("128") }, "landscape: \(texts(app))")
        XCTAssertTrue(app.frame.contains(app.staticTexts["128"].frame), "128 runs off the landscape screen")
        shot(app, "128-landscape")
        XCUIDevice.shared.orientation = .portrait

        // No new fix for longer than Speedometer.staleAfter: dashes, never a frozen number.
        driving = nil
        XCTAssertTrue(wait(30) { shows("FINDING GPS") }, "stale fix: \(texts(app))")
        shot(app, "finding-gps")

        // The unit choice survives a relaunch.
        app.tap()
        XCTAssertTrue(wait(5) { shows("MPH") })
        app.terminate()
        app.launch()
        XCTAssertTrue(wait(10) { shows("MPH") }, "mph not remembered: \(texts(app))")
    }

    /// The SwiftUI screen against the HTML it was drawn from: the same states, launched once each way (`-reference`
    /// shows Web/index.html), screenshot by screenshot. The number, the rule and the unit row must sit within a pixel of
    /// the HTML's, and almost no pixel may differ.
    func testMatchesReference() throws {
        var shots: [String: [String: XCUIScreenshot]] = [:]
        for mode in ["paper", "html"] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = mode == "html" ? ["-reference"] : []
            addUIInterruptionMonitor(withDescription: "location") { alert in
                guard alert.buttons["Allow While Using App"].exists else { return false }
                alert.buttons["Allow While Using App"].tap()
                return true
            }
            app.launch()
            allowLocation()
            func shows(_ text: String) -> Bool { app.staticTexts[text].exists }
            func take(_ name: String) {
                _ = wait(1.5) { false }   // let any size change finish
                shots[name, default: [:]][mode] = XCUIScreen.main.screenshot()
            }
            XCTAssertTrue(wait(10) { shows("KM/H") || shows("MPH") }, "\(mode): no unit")
            if shows("MPH") { app.tap() }

            drive(24.17)
            XCTAssertTrue(wait(15) { shows("87") }, "\(mode) 87: \(texts(app))")
            take("87")
            app.tap()
            XCTAssertTrue(wait(5) { shows("54") }, "\(mode) 54: \(texts(app))")
            take("54-mph")
            app.tap()
            XCTAssertTrue(wait(5) { shows("87") })
            drive(35.56)
            XCTAssertTrue(wait(15) { shows("128") }, "\(mode) 128: \(texts(app))")
            take("128")
            XCUIDevice.shared.orientation = .landscapeLeft
            _ = wait(2) { false }
            take("128-landscape")
            XCUIDevice.shared.orientation = .portrait
            _ = wait(2) { false }
            driving = nil
            XCTAssertTrue(wait(30) { shows("FINDING GPS") }, "\(mode) stale: \(texts(app))")
            take("finding-gps")
            app.terminate()
        }
        for (name, pair) in shots.sorted(by: { $0.key < $1.key }) {
            guard let paper = pair["paper"], let html = pair["html"] else { XCTFail("\(name): missing a screenshot"); continue }
            compare(name, paper, html)
        }
    }

    /// Ink boxes (number above the rule, the rule, the unit row below it) and the share of differing pixels.
    private func compare(_ name: String, _ paper: XCUIScreenshot, _ html: XCUIScreenshot) {
        let a = Gray(paper.image), b = Gray(html.image)
        guard a.width == b.width, a.height == b.height else { XCTFail("\(name): sizes differ"); return }
        let (pa, pb) = (a.parts(), b.parts())
        var differ = 0
        var diff = [UInt8](repeating: 0, count: a.width * a.height * 4)
        for i in 0..<(a.width * a.height) {
            let (x, y) = (Int(a.pixels[i]), Int(b.pixels[i]))
            let same = abs(x - y) <= 60
            if !same { differ += 1 }
            // Same: the screen faded; only in the SwiftUI screen: red; only in the HTML: blue.
            let v = UInt8(min(255, 170 + x / 3))
            diff[i * 4 + 0] = same ? v : (x < y ? 230 : 30)
            diff[i * 4 + 1] = same ? v : 30
            diff[i * 4 + 2] = same ? v : (x < y ? 30 : 230)
            diff[i * 4 + 3] = 255
        }
        let share = Double(differ) / Double(a.width * a.height)
        print("COMPARE \(name): differing \(String(format: "%.4f", share * 100))% | paper \(pa) | html \(pb)")
        for (label, image) in [("paper", paper.image), ("html", html.image), ("diff", Gray.image(diff, a.width, a.height))] {
            let attachment = XCTAttachment(image: image)
            attachment.name = "cmp-\(name)-\(label)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let px = 3   // 1 pt at 3x
        for (part, x, y) in [("number", pa.number, pb.number), ("rule", pa.rule, pb.rule), ("unit row", pa.unit, pb.unit)] {
            guard let x, let y else { XCTFail("\(name): no \(part) (paper \(String(describing: x)), html \(String(describing: y)))"); continue }
            XCTAssertTrue(abs(x.minX - y.minX) <= px && abs(x.maxX - y.maxX) <= px && abs(x.minY - y.minY) <= px
                          && abs(x.maxY - y.maxY) <= px, "\(name): \(part) at \(x) in SwiftUI, \(y) in the HTML")
        }
        XCTAssertLessThan(share, 0.003, "\(name): \(share * 100)% of pixels differ")
    }

    private func texts(_ app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
    }

    /// The speed being driven: `wait` re-sends it every half second, as a moving phone keeps reporting fixes (one fix
    /// goes stale after Speedometer.staleAfter on a slow simulator).
    private var driving: Double?

    /// A simulated GPS fix moving at `speed` m/s.
    private func drive(_ speed: Double) {
        driving = speed
        send(speed)
    }

    private func send(_ speed: Double) {
        let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 51.7520, longitude: -1.2577), altitude: 60,
                             horizontalAccuracy: 3, verticalAccuracy: 3, course: 90, courseAccuracy: 5,
                             speed: speed, speedAccuracy: 0.5, timestamp: Date())   // ±0.5 m/s = ±2 km/h, ±2 mph
        XCUIDevice.shared.location = XCUILocation(location: fix)
    }

    /// The location prompt is shown by SpringBoard, not the app.
    private func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: label == "Allow While Using App" ? 5 : 1) { button.tap(); return }
        }
    }

    private func wait(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let speed = driving { send(speed) }
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return condition()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}

/// A screenshot as 8-bit grey pixels.
private struct Gray {
    let width: Int, height: Int
    var pixels: [UInt8]

    init(_ image: UIImage) {
        let cg = image.cgImage!
        width = cg.width; height = cg.height
        pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    struct Box: CustomStringConvertible {
        var minX, minY, maxX, maxY: Int
        var description: String { "(\(minX),\(minY))–(\(maxX),\(maxY))" }
    }

    /// The rule is the lowest run of rows more than half inked (a row through the digits can be too); the number is the
    /// ink above it, the unit row below.
    func parts() -> (number: Box?, rule: Box?, unit: Box?) {
        let paper = Int(pixels[0])
        func ink(_ x: Int, _ y: Int) -> Bool { abs(Int(pixels[y * width + x]) - paper) > 30 }
        let rows = (0..<height).map { y in (0..<width).reduce(0) { $0 + (ink($1, y) ? 1 : 0) } }
        guard let bottom = rows.lastIndex(where: { $0 > width / 2 }) else { return (nil, nil, nil) }
        var top = bottom
        while top > 0 && rows[top - 1] > width / 2 { top -= 1 }
        func box(_ ys: Range<Int>) -> Box? {
            var b: Box?
            for y in ys where rows[y] > 0 {
                for x in 0..<width where ink(x, y) {
                    b = Box(minX: min(b?.minX ?? x, x), minY: min(b?.minY ?? y, y), maxX: max(b?.maxX ?? x, x), maxY: max(b?.maxY ?? y, y))
                }
            }
            return b
        }
        return (box(0..<top), box(top..<(bottom + 1)), box((bottom + 1)..<height))
    }

    static func image(_ rgba: [UInt8], _ width: Int, _ height: Int) -> UIImage {
        var data = rgba
        let cg = data.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
        }
        return UIImage(cgImage: cg)
    }
}
