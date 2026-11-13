import Testing
@testable import FiidoKit

@Test func jitterOnFlatGroundIsNotClimb() {
    let flat = (0..<300).map { 40 + ($0.isMultiple(of: 2) ? 2.0 : -2.0) }

    let elevation = Elevation(altitudes: flat)

    #expect(elevation.climbMeters == 0)
    #expect(elevation.descentMeters == 0)
}

@Test func steadyHillCountsItsFullHeight() {
    let up = (0..<200).map { 30 + Double($0) * 0.1 }
    let down = (0..<200).map { 50 - Double($0) * 0.1 }

    let elevation = Elevation(altitudes: up + down)

    #expect(abs(elevation.climbMeters - 20) < 2)
    #expect(abs(elevation.descentMeters - 20) < 2)
}
