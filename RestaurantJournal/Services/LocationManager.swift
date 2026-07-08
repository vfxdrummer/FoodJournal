import Foundation
import CoreLocation

/// Minimal wrapper around CLLocationManager for the map's "center on me" button. Requests
/// when-in-use permission on demand and publishes the latest fix.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestOneShotLocation() {
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.lastLocation = location }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent — the button just won't recenter; not worth interrupting the user.
    }
}
