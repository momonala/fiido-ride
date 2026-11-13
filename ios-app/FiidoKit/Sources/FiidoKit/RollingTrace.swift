import Foundation

public struct TracePoint: Equatable, Sendable, Identifiable {
    public let time: Date
    public let speedKmh: Double

    public var id: Date { time }
}

public struct RollingTrace: Sendable {
    public private(set) var points: [TracePoint] = []
    public let window: TimeInterval

    public init(window: TimeInterval = 60) {
        self.window = window
    }

    public mutating func append(speedKmh: Double, at time: Date) {
        points.append(TracePoint(time: time, speedKmh: speedKmh))
        points.removeAll { time.timeIntervalSince($0.time) > window }
    }

    public mutating func clear() {
        points.removeAll()
    }
}
