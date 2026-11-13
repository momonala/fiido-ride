import Testing
@testable import FiidoKit

@Test func densityAreaEqualsTotalWeightAndPeaksAtTheValue() {
    let step = 0.1
    let grid = stride(from: 0.0, through: 40, by: step).map { $0 }

    let curve = Density.curve(weights: [15: 120, 25: 60], at: grid, bandwidth: 1)

    let area = curve.reduce(0, +) * step
    #expect(abs(area - 180) < 0.5)
    let peak = grid[curve.firstIndex(of: curve.max()!)!]
    #expect(abs(peak - 15) < 0.05)
}
