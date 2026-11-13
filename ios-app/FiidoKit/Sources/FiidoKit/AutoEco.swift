import Foundation

public struct AutoEcoConfig: Equatable, Sendable {
    public var thresholdKmh: Double
    public var hysteresisKmh: Double
    public var dwell: TimeInterval
    public var confirmTimeout: TimeInterval
    public var maxAttempts: Int
    public var boostDuration: TimeInterval = 10

    public init(
        thresholdKmh: Double = 20,
        hysteresisKmh: Double = 2,
        dwell: TimeInterval = 2,
        confirmTimeout: TimeInterval = 3,
        maxAttempts: Int = 2
    ) {
        self.thresholdKmh = thresholdKmh
        self.hysteresisKmh = hysteresisKmh
        self.dwell = dwell
        self.confirmTimeout = confirmTimeout
        self.maxAttempts = maxAttempts
    }
}

/// Keeps the bike in Eco above the threshold and in Normal below threshold minus
/// hysteresis. A boost holds Normal for `boostDuration` whatever the speed. Any level
/// change it didn't make, or a write the bike keeps ignoring, hands control back to the rider.
public struct AutoEco: Sendable {
    public enum Action: Equatable, Sendable {
        case write(AssistLevel)
        case handBack
    }

    private struct PendingWrite: Sendable {
        let from: AssistLevel
        let target: AssistLevel
        var sentAt: Date
        var attempts: Int
        /// Set when the write is a boost: once confirmed, Normal is held until then.
        var boostUntil: Date?
    }

    private enum State: Sendable {
        /// No confirmed level yet: the controller is off, or this is the first sample.
        case unsynced
        case holding(AssistLevel, conditionSince: Date?)
        case boosting(until: Date)
        case writing(PendingWrite)
    }

    public var config: AutoEcoConfig
    private var state = State.unsynced

    public init(config: AutoEcoConfig = AutoEcoConfig()) {
        self.config = config
    }

    /// Normal for `boostDuration` from now, then back to the speed rule. Nil when there's nothing to write.
    public mutating func boost(at now: Date) -> Action? {
        let until = now.addingTimeInterval(config.boostDuration)
        switch state {
        case .unsynced:
            return nil
        case .boosting, .holding(.normal, _):
            state = .boosting(until: until)
            return nil
        case .holding(let level, _):
            state = .writing(PendingWrite(from: level, target: .normal, sentAt: now, attempts: 1, boostUntil: until))
            return .write(.normal)
        case .writing(var write) where write.target == .normal:
            write.boostUntil = until
            state = .writing(write)
            return nil
        case .writing(let write):
            state = .writing(PendingWrite(from: write.target, target: .normal, sentAt: now, attempts: 1, boostUntil: until))
            return .write(.normal)
        }
    }

    public var isBoosting: Bool {
        switch state {
        case .boosting: true
        case .writing(let write): write.boostUntil != nil
        case .unsynced, .holding: false
        }
    }

    /// Feed every STATS sample.
    public mutating func update(_ stats: Stats, at now: Date) -> Action? {
        guard stats.controllerOn, let level = stats.level else {
            state = .unsynced
            return nil
        }
        switch state {
        case .writing(let write):
            return resolve(write, level: level, at: now)
        case .boosting(let until):
            guard level == .normal else {
                state = .unsynced
                return .handBack
            }
            guard now >= until else { return nil }
            state = .holding(.normal, conditionSince: nil)
            return update(stats, at: now)
        case .unsynced:
            if level == .eco || level == .normal {
                state = .holding(level, conditionSince: nil)
                return nil
            }
            return send(stats.speedKmh > config.thresholdKmh ? .eco : .normal, from: level, at: now)
        case .holding(let expected, let conditionSince):
            guard level == expected else {
                state = .unsynced
                return .handBack
            }
            let target: AssistLevel? = switch level {
            case .normal where stats.speedKmh > config.thresholdKmh: .eco
            case .eco where stats.speedKmh <= config.thresholdKmh - config.hysteresisKmh: .normal
            default: nil
            }
            guard let target else {
                state = .holding(level, conditionSince: nil)
                return nil
            }
            let since = conditionSince ?? now
            state = .holding(level, conditionSince: since)
            guard now.timeIntervalSince(since) >= config.dwell else { return nil }
            return send(target, from: level, at: now)
        }
    }

    private mutating func send(_ target: AssistLevel, from level: AssistLevel, at now: Date) -> Action {
        state = .writing(PendingWrite(from: level, target: target, sentAt: now, attempts: 1, boostUntil: nil))
        return .write(target)
    }

    private mutating func resolve(_ write: PendingWrite, level: AssistLevel, at now: Date) -> Action? {
        if level == write.target {
            state = write.boostUntil.map { .boosting(until: $0) } ?? .holding(level, conditionSince: nil)
            return nil
        }
        guard level == write.from else {
            state = .unsynced
            return .handBack
        }
        guard now.timeIntervalSince(write.sentAt) >= config.confirmTimeout else { return nil }
        guard write.attempts < config.maxAttempts else {
            state = .unsynced
            return .handBack
        }
        var retry = write
        retry.attempts += 1
        retry.sentAt = now
        state = .writing(retry)
        return .write(retry.target)
    }
}
