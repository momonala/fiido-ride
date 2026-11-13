import Foundation

public struct AutoPowerConfig: Sendable {
    /// Closer than this (stronger signal) is near: switches on and arms. Further is away: switches off.
    public var thresholdRssi: Double = -70
    public var awayFor: TimeInterval = 3
    public var absenceForArrival: TimeInterval = 60
    public var retryAfter: TimeInterval = 3
    public var maxAttempts = 2
    /// Readings in a row at or above `thresholdRssi` before switching on, so one stray strong reading can't.
    public var nearReadingsToPowerOn = 2

    public init() {}
}

/// Turns the bike on when the phone comes close after being away, and off when it walks away from a parked bike.
public struct AutoPower: Sendable {
    public enum Action: Equatable, Sendable { case powerOn, powerOff, gaveUp }

    public enum Status: Equatable, Sendable {
        /// Off but not Away, or on and since switch-on the phone hasn't been near it and it hasn't moved.
        case waiting
        case armed
        case leaving(since: Date)
        case switchingOff(sentAt: Date, attempts: Int)
        /// Off because the phone was away: auto-off, or the bike dropped out of range for a while.
        case away
    }

    public var config: AutoPowerConfig
    public private(set) var rssi: Double?
    public private(set) var status = Status.waiting
    private var linkLostAt: Date?
    private var nearReadings = 0

    public init(config: AutoPowerConfig = AutoPowerConfig()) {
        self.config = config
    }

    public mutating func record(rssi value: Double) {
        rssi = value
        nearReadings = value >= config.thresholdRssi ? nearReadings + 1 : 0
    }

    /// The bike dropped out of range. Disconnects the app asked for don't count.
    public mutating func linkLost(at time: Date) {
        linkLostAt = time
        rssi = nil
        nearReadings = 0
    }

    public mutating func reset() {
        status = .waiting
    }

    /// `mayPowerOn` false holds back a switch-on (the bike stays Away) without affecting switch-off.
    public mutating func update(_ stats: Stats, at time: Date, mayPowerOn: Bool) -> Action? {
        if let linkLostAt, time.timeIntervalSince(linkLostAt) >= config.absenceForArrival { status = .away }
        linkLostAt = nil
        return stats.controllerOn ? whileOn(stats, at: time) : whileOff(mayPowerOn: mayPowerOn)
    }

    private mutating func whileOff(mayPowerOn: Bool) -> Action? {
        switch status {
        case .switchingOff, .away: status = .away
        case .waiting, .armed, .leaving: status = .waiting
        }
        guard status == .away, mayPowerOn, nearReadings >= config.nearReadingsToPowerOn else { return nil }
        status = .waiting
        return .powerOn
    }

    private mutating func whileOn(_ stats: Stats, at time: Date) -> Action? {
        switch status {
        case .switchingOff(let sentAt, let attempts):
            return retryOrGiveUp(stats, sentAt: sentAt, attempts: attempts, at: time)
        case .away:
            status = .waiting
        case .waiting, .armed, .leaving:
            break
        }
        guard let rssi else { return nil }
        if status == .waiting, rssi >= config.thresholdRssi || stats.speedKmh > 0 { status = .armed }
        guard status != .waiting else { return nil }
        guard stats.speedKmh == 0, rssi < config.thresholdRssi else {
            status = .armed
            return nil
        }
        let since = if case .leaving(let since) = status { since } else { time }
        guard time.timeIntervalSince(since) >= config.awayFor else {
            status = .leaving(since: since)
            return nil
        }
        status = .switchingOff(sentAt: time, attempts: 1)
        return .powerOff
    }

    private mutating func retryOrGiveUp(_ stats: Stats, sentAt: Date, attempts: Int, at time: Date) -> Action? {
        guard time.timeIntervalSince(sentAt) >= config.retryAfter else { return nil }
        if (rssi ?? -.infinity) >= config.thresholdRssi || stats.speedKmh > 0 {
            status = .armed
            return nil
        }
        guard attempts < config.maxAttempts else {
            reset()
            return .gaveUp
        }
        status = .switchingOff(sentAt: time, attempts: attempts + 1)
        return .powerOff
    }
}
