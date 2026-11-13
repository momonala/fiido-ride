import CoreLocation
import Observation

@MainActor @Observable
final class LocationTracker: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    @ObservationIgnored var onLocation: ((CLLocation) -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var pendingFix: CheckedContinuation<CLLocation?, Never>?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    var lastKnown: CLLocation? { manager.location }

    /// A fresh fix, or nil if iOS can't get one.
    func currentLocation() async -> CLLocation? {
        pendingFix?.resume(returning: nil)
        return await withCheckedContinuation { continuation in
            pendingFix = continuation
            manager.requestLocation()
        }
    }

    func isNear(_ place: CLLocationCoordinate2D, within meters: CLLocationDistance) -> Bool {
        guard let lastKnown else { return false }
        return lastKnown.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) <= meters
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func start() {
        guard !running else { return }
        running = true
        manager.startUpdatingLocation()
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopUpdatingLocation()
    }
}

extension LocationTracker {
    private func resolvePendingFix(_ fix: CLLocation?) {
        pendingFix?.resume(returning: fix)
        pendingFix = nil
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            locations.forEach { onLocation?($0) }
            if let last = locations.last { resolvePendingFix(last) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { resolvePendingFix(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorization = self.manager.authorizationStatus
        }
    }
}
