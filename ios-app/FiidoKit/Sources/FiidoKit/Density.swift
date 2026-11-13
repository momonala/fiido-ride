import Foundation

/// Gaussian kernel density of weighted values, scaled so the curve's area equals the total weight.
public enum Density {
    public static func curve(weights: [Double: Double], at grid: [Double], bandwidth: Double) -> [Double] {
        let scale = 1 / (bandwidth * (2 * Double.pi).squareRoot())
        return grid.map { x in
            weights.reduce(0) { sum, entry in
                let z = (x - entry.key) / bandwidth
                return sum + entry.value * scale * exp(-z * z / 2)
            }
        }
    }
}
