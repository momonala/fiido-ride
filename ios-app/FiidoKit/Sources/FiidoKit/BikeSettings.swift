import Foundation

public enum SpeedLimit: CaseIterable, Sendable {
    case walk, legal, none

    public var name: String {
        switch self {
        case .walk: "6 km/h"
        case .legal: "25 km/h"
        case .none: "No limit"
        }
    }

    var value: UInt8 {
        switch self {
        case .walk: 6
        case .legal: 25
        case .none: 100
        }
    }

    var flagOn: Bool { self != .none }

    /// Register 0x3C plus the limit flag in 0x27. Other combinations are a resting
    /// state the bike re-arms after a ride and say nothing about the setting.
    public init?(value: UInt8, flagOn: Bool) {
        switch (value, flagOn) {
        case (100, _): self = .none
        case (6, true): self = .walk
        case (25, true): self = .legal
        default: return nil
        }
    }
}

public struct SpeedLimitWrite: Sendable {
    public let first: [Data]
    public let then: [Data]
    /// Clearing the PAS cap makes the bike write 0x3C = 25 by itself, so `then` has to land after it.
    public let delayThen: Bool
}

extension Stats {
    public var hornOn: Bool { raw[51] & 0x0C == 0 }
    public var keySoundOn: Bool { raw[39] & 0x10 == 0 }

    public func hornWriteFrame(on: Bool) -> Data {
        let cleared = raw[51] & ~0x0C
        return Frame.write(0x38, payload: [on ? cleared : cleared | 0x04])
    }

    public func keySoundWriteFrame(on: Bool) -> Data {
        Frame.write(0x2C, payload: [on ? raw[39] & ~0x10 : raw[39] | 0x10])
    }

    public func speedLimitWrite(_ limit: SpeedLimit) -> SpeedLimitWrite {
        let pasOn = raw[39] & 0x80 != 0
        let first = pasOn == limit.flagOn
            ? []
            : [Frame.write(0x2C, payload: [limit.flagOn ? raw[39] | 0x80 : raw[39] & ~0x80])]
        let flags = limit.flagOn ? raw[34] | 0x20 : raw[34] & ~0x20
        return SpeedLimitWrite(
            first: first,
            then: [Frame.write(0x3C, payload: [limit.value]), Frame.write(0x27, payload: [flags])],
            delayThen: !limit.flagOn
        )
    }
}

/// Hardware and software version bytes, the first two of the payload in each block.
public struct FirmwareVersion: Equatable, Sendable {
    public let hardware: UInt8
    public let software: UInt8

    public init?(payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        hardware = payload[0]
        software = payload[1]
    }
}
