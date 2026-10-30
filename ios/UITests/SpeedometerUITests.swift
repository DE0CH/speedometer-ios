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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'GPS ±'")).firstMatch.exists, texts(app))
        shot(app, "87-kmh")

        // Tap: mph, and back.
        app.tap()
        XCTAssertTrue(wait(5) { shows("MPH") && shows("54") }, "mph: \(texts(app))")
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
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(wait(15) { shows("128") }, "landscape: \(texts(app))")
        XCTAssertTrue(app.frame.contains(app.staticTexts["128"].frame), "128 runs off the landscape screen")
        shot(app, "128-landscape")
        XCUIDevice.shared.orientation = .portrait

        // No new fix for longer than Speedometer.staleAfter: dashes, never a frozen number.
        XCTAssertTrue(wait(30) { shows("FINDING GPS") }, "stale fix: \(texts(app))")
        shot(app, "finding-gps")

        // The unit choice survives a relaunch.
        app.tap()
        XCTAssertTrue(wait(5) { shows("MPH") })
        app.terminate()
        app.launch()
        XCTAssertTrue(wait(10) { shows("MPH") }, "mph not remembered: \(texts(app))")
    }

    private func texts(_ app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
    }

    /// A simulated GPS fix moving at `speed` m/s.
    private func drive(_ speed: Double) {
        let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 51.7520, longitude: -1.2577), altitude: 60,
                             horizontalAccuracy: 3, verticalAccuracy: 3, course: 90, speed: speed, timestamp: Date())
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
