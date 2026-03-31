import CoreLocation
import Foundation

/// LocationKeepAliveManager
/// ─────────────────────────────────────────────────────────────────────────
/// Strategy: Significant-location-change monitoring keeps the app registered
/// with the system and allows relaunch even after force-quit.
///
/// Additionally, standard location updates (accuracy: kCLLocationAccuracyThreeKilometers)
/// are used while the app is in the background — iOS does NOT kill apps that
/// hold an active CLLocationManager with background location permission.
///
/// Key points:
///   • Uses "always" authorization + background mode "location" in Info.plist
///   • Accuracy set to lowest power (3km) to minimise battery drain
///   • pausesLocationUpdatesAutomatically = false  ← critical
///   • allowsBackgroundLocationUpdates = true       ← critical
///   • Significant-change monitoring survives app termination + re-launches
///     the app when a coarse location change is detected (cell tower switch)
/// ─────────────────────────────────────────────────────────────────────────
final class LocationKeepAliveManager: NSObject {

    static let shared = LocationKeepAliveManager()

    private let manager: CLLocationManager = {
        let m = CLLocationManager()
        m.desiredAccuracy          = kCLLocationAccuracyThreeKilometers  // lowest power
        m.distanceFilter           = 10                                   // metres
        m.pausesLocationUpdatesAutomatically = false                      // NEVER pause
        m.allowsBackgroundLocationUpdates   = true                        // REQUIRED
        m.showsBackgroundLocationIndicator  = true                        // shows blue bar (honest to user)
        return m
    }()

    private override init() { super.init() }

    // ── Public API ────────────────────────────────────────────────────────

    func start() {
        manager.delegate = self

        switch manager.authorizationStatus {
        case .notDetermined:
            // Request "always" — this is the only permission that keeps
            // location alive after the user locks the screen.
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            // Upgrade prompt to "always"
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startAllServices()
        default:
            break // denied / restricted — handle in UI
        }
    }

    /// Call when entering background for belt-and-suspenders guarantee
    func beginBackgroundUpdate() {
        manager.startUpdatingLocation()          // standard updates
        manager.startMonitoringSignificantLocationChanges() // survive kill
    }

    func stopBackgroundUpdate() {
        // Stop standard updates in foreground to save battery —
        // significant-change monitoring keeps running.
        manager.stopUpdatingLocation()
    }

    // ── Private ───────────────────────────────────────────────────────────

    private func startAllServices() {
        manager.startMonitoringSignificantLocationChanges()
        manager.startUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationKeepAliveManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            startAllServices()
        case .authorizedWhenInUse:
            // App can still run in foreground; background will be limited.
            // Show an alert prompting user to upgrade to Always.
            NotificationCenter.default.post(name: .locationAuthDowngraded, object: nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        BackgroundActivityLog.shared.recordPing(
            source: "Location update (\(String(format: "%.4f", location.coordinate.latitude)), "
                  + "\(String(format: "%.4f", location.coordinate.longitude)))"
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is benign — ignore it.
        let clError = error as? CLError
        if clError?.code == .locationUnknown { return }
        BackgroundActivityLog.shared.recordPing(source: "Location error: \(error.localizedDescription)")
    }
}

extension Notification.Name {
    static let locationAuthDowngraded = Notification.Name("locationAuthDowngraded")
}
