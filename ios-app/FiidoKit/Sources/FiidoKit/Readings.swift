import Foundation

public enum AssistLevel: UInt8, CaseIterable, Sendable {
    case off = 0, eco, normal, sport, turbo, turboPlus

    public var name: String {
        switch self {
        case .off: "Off"
        case .eco: "Eco"
        case .normal: "Normal"
        case .sport: "Sport"
        case .turbo: "Turbo"
        case .turboPlus: "Turbo+"
        }
    }

    /// Only valid in 5-level mode, and only accepted while the controller is on.
    public var writeFrame: Data {
        Frame.write(0x26, payload: [rawValue])
    }
}

/// The STATS poll: one frame carrying registers 0x05...0x39. A field at register `r`
/// sits at payload offset `r - 0x05`; multi-byte fields are big-endian.
public struct Stats: Equatable, Sendable {
    public let totalKm: Double
    public let tripKm: Double
    public let speedKmh: Double
    /// The display's battery bars as a percent: coarse steps, and 90 on a full battery.
    public let batteryBars: Int
    public let levelCount: Int?
    public let level: AssistLevel?
    public let controllerOn: Bool
    public let lightOn: Bool
    public let speedLimitOn: Bool
    public let raw: [UInt8]

    public init?(payload p: [UInt8]) {
        guard p.count == Int(Poll.stats.length) else { return nil }
        let total = Double(p.u32(23)) / 10
        let trip = Double(p.u16(27)) / 10
        let speed = Double(p.u16(29)) / 10
        let bars = Int(p[31])
        guard total <= 200_000, trip <= 1_000, speed <= 100, bars <= 100 else { return nil }

        totalKm = total
        tripKm = trip
        speedKmh = speed
        batteryBars = bars
        let count = max(p[32] >> 4, p[32] & 0x0F)
        levelCount = (count == 3 || count == 5) ? Int(count) : nil
        level = levelCount == 5 ? AssistLevel(rawValue: p[33]) : nil
        controllerOn = p[34] & 0x80 != 0
        lightOn = p[34] & 0x08 != 0
        speedLimitOn = p[34] & 0x20 != 0
        raw = p
    }

    /// Register 0x27 also holds controller power, so the light is written back with every other bit unchanged.
    public func lightWriteFrame(on: Bool) -> Data {
        Frame.write(0x27, payload: [on ? raw[34] | 0x08 : raw[34] & ~0x08])
    }

    public func powerWriteFrame(on: Bool) -> Data {
        Frame.write(0x27, payload: [on ? raw[34] | 0x80 : raw[34] & ~0x80])
    }

    /// Capability bits 0x2D...0x34. Only these four have a known meaning.
    public var hasTorqueSensor: Bool { raw[40] & 0x02 != 0 }
    public var hasEnergyMeter: Bool { raw[40] & 0x01 != 0 }
    public var hasBatteryCurrentSensor: Bool { raw[43] & 0x20 != 0 }
    public var hasBatteryLink: Bool { raw[46] & 0x10 != 0 }
}

public struct Energy: Equatable, Sendable {
    public let torqueNm: Double
    public let cadenceRpm: Int
    public let tripWh: Double
    public let totalWh: Double
    public let uptimeSeconds: Int

    public init?(payload p: [UInt8]) {
        guard p.count == Int(Poll.energy.length) else { return nil }
        torqueNm = Double(p.u16(0)) / 10
        cadenceRpm = Int(p.u16(2))
        tripWh = Double(p.u16(4)) / 10
        totalWh = Double(p.u32(6)) / 10
        uptimeSeconds = Int(p.u16(10))
    }

    public var riderPowerW: Double {
        torqueNm * Double(cadenceRpm) * 2 * .pi / 60
    }
}

public struct Motor: Equatable, Sendable {
    public let version: UInt8
    /// Registers 0x9D...0x9E. Sags under load and recovers at rest; 99 on a full battery.
    public let batteryPercent: Int
    public let ratedPowerW: Int

    public init?(payload p: [UInt8]) {
        guard p.count == Int(Poll.motor.length) else { return nil }
        let battery = Int(p.u16(7))
        guard battery <= 100 else { return nil }
        version = p[0]
        batteryPercent = battery
        ratedPowerW = Int(p.u16(9))
    }
}

public struct Controller: Equatable, Sendable {
    public let temperatureC: Int
    public let currentA: Double

    public init?(payload p: [UInt8]) {
        guard p.count == Int(Poll.controller.length) else { return nil }
        temperatureC = Int(Int8(bitPattern: p[9]))
        currentA = Double(p.u16(7)) / 10
    }
}

public struct Battery: Equatable, Sendable {
    public let capacityAh: Double
    public let voltageV: Double
    public let currentA: Double
    /// Byte 11, `failureList` in the official app. Non-zero bits are faults; their meanings are unknown.
    public let faults: UInt8

    public init?(payload p: [UInt8]) {
        guard p.count == Int(Poll.battery.length) else { return nil }
        capacityAh = Double(p.u16(2)) / 10
        voltageV = Double(p.u16(4)) / 10
        currentA = Double(Int16(bitPattern: p.u16(9))) / 10
        faults = p[11]
    }
}

extension [UInt8] {
    func u16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) << 16 | UInt32(u16(offset + 2))
    }
}
