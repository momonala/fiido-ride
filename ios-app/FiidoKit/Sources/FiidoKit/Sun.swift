import Foundation

/// Sun position from the low-precision formulas in the Astronomical Almanac, good to about 0.1°.
public enum Sun {
    /// Below this the sun has set: its upper edge is under the horizon, allowing for refraction.
    public static let horizonDegrees = -0.833

    public static func isDown(at date: Date, latitude: Double, longitude: Double) -> Bool {
        elevationDegrees(at: date, latitude: latitude, longitude: longitude) < horizonDegrees
    }

    public static func elevationDegrees(at date: Date, latitude: Double, longitude: Double) -> Double {
        let daysSinceJ2000 = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let meanLongitude = 280.460 + 0.9856474 * daysSinceJ2000
        let meanAnomaly = radians(357.528 + 0.9856003 * daysSinceJ2000)
        let eclipticLongitude = radians(meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly))
        let obliquity = radians(23.439 - 0.0000004 * daysSinceJ2000)

        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let siderealDegrees = 280.46061837 + 360.98564736629 * daysSinceJ2000 + longitude
        let hourAngle = radians(siderealDegrees) - rightAscension
        let lat = radians(latitude)
        return degrees(asin(sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)))
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
