import Foundation

/// The time format every export uses: ISO 8601 UTC with milliseconds.
extension Date {
    public var exportTimestamp: String {
        formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

/// One stored frame as the app keeps it: when it arrived, which register, the raw payload.
public struct StoredFrame: Sendable {
    public let time: Date
    public let register: UInt8
    public let payload: [UInt8]

    public init(time: Date, register: UInt8, payload: [UInt8]) {
        self.time = time
        self.register = register
        self.payload = payload
    }

    public static let columns = ["register", "poll", "payload"]

    public var values: [ExportValue?] {
        [.text(String(format: "0x%02X", register)),
         Poll(register: register, payloadLength: payload.count).map { .text($0.name) },
         .bytes(payload)]
    }
}

public struct GPSFix: Sendable {
    public let time: Date
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let speedKmh: Double
    public let course: Double
    public let horizontalAccuracy: Double

    public init(time: Date, latitude: Double, longitude: Double, altitude: Double, speedKmh: Double,
                course: Double, horizontalAccuracy: Double) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speedKmh = speedKmh
        self.course = course
        self.horizontalAccuracy = horizontalAccuracy
    }

    public static let columns = ["latitude", "longitude", "altitude_m", "speed_kmh", "course_deg", "horizontal_accuracy_m"]

    public var values: [ExportValue?] {
        [.double(latitude), .double(longitude), .double(altitude), .double(speedKmh), .double(course), .double(horizontalAccuracy)]
    }
}

public enum ExportValue: Sendable, Equatable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case text(String)
    case bytes([UInt8])
}

/// A STATS reading with the latest motor, battery, controller, energy and GPS readings carried forward.
public struct TelemetryRow: Sendable {
    public let time: Date
    public let stats: Stats
    public let energy: Energy?
    public let motor: Motor?
    public let battery: Battery?
    public let controller: Controller?
    public let fix: GPSFix?

    public static let columns = [
        "speed_kmh", "trip_km", "odometer_km", "battery_pct", "battery_bars", "assist_level",
        "controller_on", "light_on", "speed_limit_on",
        "torque_nm", "cadence_rpm", "rider_power_w", "trip_wh", "total_wh", "uptime_s",
        "motor_rated_w", "battery_capacity_ah", "battery_voltage_v", "battery_current_a", "battery_faults",
        "controller_temp_c", "controller_current_a", "latitude", "longitude", "altitude_m", "gps_speed_kmh",
    ]

    /// In `columns` order; nil where that reading hasn't arrived yet.
    public var values: [ExportValue?] {
        [
            .double(stats.speedKmh), .double(stats.tripKm), .double(stats.totalKm),
            motor.map { .int($0.batteryPercent) }, .int(stats.batteryBars),
            stats.level.map { .text($0.name) },
            .bool(stats.controllerOn), .bool(stats.lightOn), .bool(stats.speedLimitOn),
            energy.map { .double($0.torqueNm) }, energy.map { .int($0.cadenceRpm) }, energy.map { .double($0.riderPowerW) },
            energy.map { .double($0.tripWh) }, energy.map { .double($0.totalWh) }, energy.map { .int($0.uptimeSeconds) },
            motor.map { .int($0.ratedPowerW) },
            battery.map { .double($0.capacityAh) }, battery.map { .double($0.voltageV) }, battery.map { .double($0.currentA) },
            battery.map { .int(Int($0.faults)) },
            controller.map { .int($0.temperatureC) }, controller.map { .double($0.currentA) },
            fix.map { .double($0.latitude) }, fix.map { .double($0.longitude) }, fix.map { .double($0.altitude) },
            fix.map { .double($0.speedKmh) },
        ]
    }

    /// One row per STATS frame. Both inputs oldest first.
    public static func rows(frames: [StoredFrame], fixes: [GPSFix]) -> [TelemetryRow] {
        var energy: Energy?
        var motor: Motor?
        var battery: Battery?
        var controller: Controller?
        var fixIndex = -1
        var rows: [TelemetryRow] = []

        for frame in frames {
            switch Poll(register: frame.register, payloadLength: frame.payload.count) {
            case .energy: energy = Energy(payload: frame.payload) ?? energy
            case .motor: motor = Motor(payload: frame.payload) ?? motor
            case .battery: battery = Battery(payload: frame.payload) ?? battery
            case .controller: controller = Controller(payload: frame.payload) ?? controller
            case .stats:
                guard let stats = Stats(payload: frame.payload) else { continue }
                while fixIndex + 1 < fixes.count, fixes[fixIndex + 1].time <= frame.time { fixIndex += 1 }
                rows.append(TelemetryRow(time: frame.time, stats: stats, energy: energy, motor: motor, battery: battery,
                                         controller: controller, fix: fixIndex >= 0 ? fixes[fixIndex] : nil))
            default: continue
            }
        }
        return rows
    }
}
