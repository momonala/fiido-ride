import Foundation
import Testing
@testable import FiidoKit

private let berlin = (latitude: 52.52, longitude: 13.405)

private func utc(_ text: String) -> Date {
    try! Date(text, strategy: .iso8601)
}

@Test func midsummerNoonInBerlinIsHighSun() {
    let elevation = Sun.elevationDegrees(at: utc("2026-06-21T11:10:00Z"), latitude: berlin.latitude, longitude: berlin.longitude)
    #expect(abs(elevation - 60.9) < 0.5)
}

@Test func berlinSunsetOnTheLongestDayFallsBetween1930And1940Utc() {
    #expect(!Sun.isDown(at: utc("2026-06-21T19:30:00Z"), latitude: berlin.latitude, longitude: berlin.longitude))
    #expect(Sun.isDown(at: utc("2026-06-21T19:40:00Z"), latitude: berlin.latitude, longitude: berlin.longitude))
}

@Test func winterEveningIsDark() {
    #expect(Sun.isDown(at: utc("2026-12-21T16:00:00Z"), latitude: berlin.latitude, longitude: berlin.longitude))
    #expect(!Sun.isDown(at: utc("2026-12-21T11:00:00Z"), latitude: berlin.latitude, longitude: berlin.longitude))
}
