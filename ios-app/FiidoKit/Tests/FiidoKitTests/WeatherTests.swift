import Foundation
import Testing
@testable import FiidoKit

@Test func decodesOpenMeteoCurrentConditionsAndRainChance() throws {
    let json = """
    {"current":{"time":"2026-11-14T11:00","interval":900,"temperature_2m":6.3,"weather_code":61,"is_day":1},
     "hourly":{"time":["2026-11-14T11:00"],"precipitation_probability":[40]}}
    """

    let weather = try Weather(json: Data(json.utf8))

    #expect(weather == Weather(temperatureC: 6.3, code: 61, isDay: true, rainChancePercent: 40))
    #expect(weather.symbol == "cloud.rain.fill")
}

@Test func clearSkyShowsMoonAtNight() {
    #expect(Weather(temperatureC: 2, code: 0, isDay: false, rainChancePercent: 0).symbol == "moon.stars.fill")
}

@Test func requestRoundsLocationToAboutAKilometre() throws {
    let url = Weather.url(latitude: 52.517_389, longitude: 13.388_861)
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

    #expect(items.first { $0.name == "latitude" }?.value == "52.52")
    #expect(items.first { $0.name == "longitude" }?.value == "13.39")
}
