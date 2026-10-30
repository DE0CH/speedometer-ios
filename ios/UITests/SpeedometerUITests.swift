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
        let speed = app.descendants(matching: .any)["speed"], unit = app.descendants(matching: .any)["unit"],
            status = app.descendants(matching: .any)["status"]
        XCTAssertTrue(speed.waitForExistence(timeout: 10), "no speed on screen")
        shot(app, "launch")
        if unit.label == "MPH" { app.tap() }   // a previous run left mph on

        // 87 km/h.
        drive(24.17)
        XCTAssertTrue(wait(15) { speed.label == "87" }, "speed \(speed.label), status \(status.label)")
        XCTAssertEqual(unit.label, "KM/H")
        XCTAssertTrue(status.label.hasPrefix("GPS ±"), status.label)
        shot(app, "87-kmh")

        // Tap: mph, and back.
        app.tap()
        XCTAssertTrue(wait(5) { unit.label == "MPH" && speed.label == "54" }, "mph: \(speed.label) \(unit.label)")
        shot(app, "54-mph")
        app.tap()
        XCTAssertTrue(wait(5) { unit.label == "KM/H" && speed.label == "87" }, "back to km/h: \(speed.label)")

        // Parked: jitter reads 0.
        drive(0.4)
        XCTAssertTrue(wait(15) { speed.label == "0" }, "parked shows \(speed.label)")
        shot(app, "0-parked")

        // Three digits still fit.
        drive(35.56)
        XCTAssertTrue(wait(15) { speed.label == "128" }, "fast shows \(speed.label)")
        XCTAssertTrue(speed.frame.maxX <= app.frame.maxX + 0.5, "128 runs off the screen: \(speed.frame)")
        shot(app, "128-kmh")

        // Landscape.
        XCUIDevice.shared.orientation = .landscapeLeft
        drive(35.56)
        XCTAssertTrue(wait(15) { speed.label == "128" }, "landscape shows \(speed.label)")
        shot(app, "128-landscape")
        XCUIDevice.shared.orientation = .portrait

        // No new fix for longer than Speedometer.staleAfter: dashes, never a frozen number.
        XCTAssertTrue(wait(30) { status.label == "FINDING GPS" }, "stale fix still shows \(speed.label)")
        shot(app, "finding-gps")

        // The unit choice survives a relaunch.
        app.tap()
        XCTAssertTrue(wait(5) { unit.label == "MPH" })
        app.terminate()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["unit"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["unit"].label, "MPH", "mph not remembered")
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
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
