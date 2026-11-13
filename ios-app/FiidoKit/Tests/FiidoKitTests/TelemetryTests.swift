import Foundation
import Testing
@testable import FiidoKit

@Test func telemetryRowPerStatsFrameWithLatestGPSFixCarriedForward() {
    let start = Date(timeIntervalSince1970: 1000)
    let stats = c21Stats(speedKmh: 12.5).raw
    let frames = [0, 1, 2].map { StoredFrame(time: start + Double($0), register: Poll.stats.rawValue, payload: stats) }
    let fix = GPSFix(time: start + 0.5, latitude: 52.5, longitude: 13.4, altitude: 40, speedKmh: 12, course: 90, horizontalAccuracy: 5)

    let rows = TelemetryRow.rows(frames: frames, fixes: [fix])

    #expect(rows.count == 3)
    #expect(rows[0].fix == nil, "no fix yet at the first frame")
    #expect(rows[2].fix?.latitude == 52.5)
    #expect(rows[0].values.count == TelemetryRow.columns.count)
    #expect(rows[0].values[0] == .double(12.5))
}
