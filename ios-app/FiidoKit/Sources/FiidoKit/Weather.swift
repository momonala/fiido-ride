import Foundation

public struct Weather: Equatable, Sendable {
    public let temperatureC: Double
    /// WMO weather interpretation code.
    public let code: Int
    public let isDay: Bool
    public let rainChancePercent: Int?

    public init(temperatureC: Double, code: Int, isDay: Bool, rainChancePercent: Int?) {
        self.temperatureC = temperatureC
        self.code = code
        self.isDay = isDay
        self.rainChancePercent = rainChancePercent
    }

    public init(json: Data) throws {
        let response = try JSONDecoder().decode(Response.self, from: json)
        self.init(temperatureC: response.current.temperature_2m,
                  code: response.current.weather_code,
                  isDay: response.current.is_day == 1,
                  rainChancePercent: response.hourly.precipitation_probability.first ?? nil)
    }

    public static func url(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "forecast_hours", value: "1"),
        ]
        return components.url!
    }

    public var symbol: String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61, 63, 80, 81: "cloud.rain.fill"
        case 65, 66, 67, 82: "cloud.heavyrain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }

        struct Hourly: Decodable {
            let precipitation_probability: [Int?]
        }

        let current: Current
        let hourly: Hourly
    }
}
