import Foundation

/// Climb and descent from GPS altitudes, which jitter by several metres from fix to fix.
public struct Elevation: Equatable, Sendable {
    public private(set) var climbMeters = 0.0
    public private(set) var descentMeters = 0.0
    public let smoothed: [Double]

    /// `altitudes` in time order, about one per second.
    public init(altitudes: [Double]) {
        let half = Self.smoothingWindow / 2
        smoothed = altitudes.indices.map { index in
            let window = altitudes[max(0, index - half)...min(altitudes.count - 1, index + half)]
            return window.reduce(0, +) / Double(window.count)
        }
        guard var turn = smoothed.first else { return }
        var extreme = turn
        var rising: Bool?
        for altitude in smoothed.dropFirst() {
            switch rising {
            case nil:
                if abs(altitude - turn) >= Self.deadbandMeters { rising = altitude > turn; extreme = altitude }
            case true?:
                if altitude > extreme { extreme = altitude } else if extreme - altitude >= Self.deadbandMeters {
                    add(from: turn, to: extreme); turn = extreme; extreme = altitude; rising = false
                }
            case false?:
                if altitude < extreme { extreme = altitude } else if altitude - extreme >= Self.deadbandMeters {
                    add(from: turn, to: extreme); turn = extreme; extreme = altitude; rising = true
                }
            }
        }
        add(from: turn, to: extreme)
    }

    private mutating func add(from start: Double, to end: Double) {
        if end > start { climbMeters += end - start } else { descentMeters += start - end }
    }

    private static let smoothingWindow = 15
    private static let deadbandMeters = 3.0
}
