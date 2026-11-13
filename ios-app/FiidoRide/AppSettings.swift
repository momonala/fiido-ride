import CoreLocation
import FiidoKit
import Foundation
import Observation

@MainActor @Observable
final class AppSettings {
    private enum Key: String {
        case autoAssist, thresholdKmh, hysteresisKmh, ridingPollInterval, keepScreenOn, discoveryMode, autoPower, autoPowerDbm, lightsAfterDark, home
    }

    var autoAssist: Bool { didSet { store(autoAssist, .autoAssist) } }
    var thresholdKmh: Double { didSet { store(thresholdKmh, .thresholdKmh) } }
    var hysteresisKmh: Double { didSet { store(hysteresisKmh, .hysteresisKmh) } }
    var ridingPollInterval: Double { didSet { store(ridingPollInterval, .ridingPollInterval) } }
    var keepScreenOn: Bool { didSet { store(keepScreenOn, .keepScreenOn) } }
    var discoveryMode: Bool { didSet { store(discoveryMode, .discoveryMode) } }
    var autoPower: Bool { didSet { store(autoPower, .autoPower) } }
    var autoPowerDbm: Double { didSet { store(autoPowerDbm, .autoPowerDbm) } }
    var lightsAfterDark: Bool { didSet { store(lightsAfterDark, .lightsAfterDark) } }
    /// Auto power never switches the bike on while the phone is within `homeRadiusMeters` of this.
    var home: CLLocationCoordinate2D? {
        didSet {
            if let home { store([home.latitude, home.longitude], .home) } else { defaults.removeObject(forKey: Key.home.rawValue) }
        }
    }
    static let homeRadiusMeters: CLLocationDistance = 100

    static let purchaseOdometerKm = kilometres(infoKey: "FiidoPurchaseOdometerKm")
    static let oldDisplayAtSwapKm = kilometres(infoKey: "FiidoOldDisplayKm")

    /// Set in Local.xcconfig; 0 when it isn't.
    private static func kilometres(infoKey: String) -> Double {
        (Bundle.main.object(forInfoDictionaryKey: infoKey) as? String).flatMap(Double.init) ?? 0
    }

    func bikeTotalKm(displayKm: Double) -> Double {
        Self.oldDisplayAtSwapKm + displayKm
    }

    func myKm(displayKm: Double) -> Double {
        bikeTotalKm(displayKm: displayKm) - Self.purchaseOdometerKm
    }

    var autoEcoConfig: AutoEcoConfig {
        AutoEcoConfig(thresholdKmh: thresholdKmh, hysteresisKmh: hysteresisKmh)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let autoEco = AutoEcoConfig()
        autoAssist = defaults.object(forKey: Key.autoAssist.rawValue) as? Bool ?? true
        thresholdKmh = defaults.object(forKey: Key.thresholdKmh.rawValue) as? Double ?? autoEco.thresholdKmh
        hysteresisKmh = defaults.object(forKey: Key.hysteresisKmh.rawValue) as? Double ?? autoEco.hysteresisKmh
        ridingPollInterval = defaults.object(forKey: Key.ridingPollInterval.rawValue) as? Double ?? 0.5
        keepScreenOn = defaults.object(forKey: Key.keepScreenOn.rawValue) as? Bool ?? true
        discoveryMode = defaults.object(forKey: Key.discoveryMode.rawValue) as? Bool ?? true
        autoPower = defaults.object(forKey: Key.autoPower.rawValue) as? Bool ?? false
        autoPowerDbm = defaults.object(forKey: Key.autoPowerDbm.rawValue) as? Double ?? AutoPowerConfig().thresholdRssi
        lightsAfterDark = defaults.object(forKey: Key.lightsAfterDark.rawValue) as? Bool ?? true
        home = (defaults.array(forKey: Key.home.rawValue) as? [Double]).flatMap { saved in
            saved.count == 2 ? CLLocationCoordinate2D(latitude: saved[0], longitude: saved[1]) : nil
        }
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
