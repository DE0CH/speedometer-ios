import CoreLocation
import UIKit

/// GPS speed from Core Location. The speed is the receiver's Doppler measurement (`CLLocation.speed`), not distance
/// over time, so it is right within a second of a fix and doesn't lag.
final class Speedometer: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Reading: Equatable {
        case waiting                                  // no fix yet, or the last one is stale
        case denied                                   // location is off for the app
        case speed(metresPerSecond: Double, accuracy: Double?)   // ± m/s, nil when GPS gives none
    }

    @Published private(set) var reading: Reading = .waiting

    /// Below this, GPS jitter on a parked phone (a few tenths of a m/s) shows as 0 instead of flickering 1–3.
    static let standstill = 0.8
    /// A fix older than this no longer counts: the number goes back to dashes rather than freeze on an old speed.
    static let staleAfter: TimeInterval = 10

    private let manager = CLLocationManager()
    private var lastFix = Date.distantPast
    private var staleTimer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func start() {
        staleTimer?.invalidate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkStale() }
        apply(manager.authorizationStatus)
    }

    func stop() {
        manager.stopUpdatingLocation()
        staleTimer?.invalidate()
        staleTimer = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        apply(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last(where: { $0.speed >= 0 && $0.horizontalAccuracy >= 0 }) else { return }
        lastFix = Date()
        let speed = fix.speed < Self.standstill ? 0 : fix.speed
        reading = .speed(metresPerSecond: speed, accuracy: fix.speedAccuracy >= 0 ? fix.speedAccuracy : nil)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { reading = .denied }
    }

    private func apply(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            reading = .denied
        default:
            if reading == .denied { reading = .waiting }
            manager.startUpdatingLocation()
        }
    }

    private func checkStale() {
        if case .speed = reading, Date().timeIntervalSince(lastFix) > Self.staleAfter { reading = .waiting }
    }
}
