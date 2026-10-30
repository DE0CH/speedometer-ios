import SwiftUI

@main
struct SpeedometerApp: App {
    @StateObject private var meter = Speedometer()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(meter)
        }
        .onChange(of: phase) { _, phase in
            // The screen stays on while the app is open; GPS runs only while it is on screen.
            UIApplication.shared.isIdleTimerDisabled = phase == .active
            if phase == .active { meter.start() } else if phase == .background { meter.stop() }
        }
    }
}
