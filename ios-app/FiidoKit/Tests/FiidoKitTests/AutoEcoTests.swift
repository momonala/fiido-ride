import Foundation
import Testing
@testable import FiidoKit

/// Feeds one sample per second and records every action the rule returns.
private struct Ride {
    var rule = AutoEco()
    var clock = Date(timeIntervalSince1970: 0)
    var actions: [AutoEco.Action] = []

    mutating func boost() {
        if let action = rule.boost(at: clock) { actions.append(action) }
    }

    mutating func ride(_ samples: [(Double, AssistLevel)]) {
        for (speed, level) in samples {
            if let action = rule.update(c21Stats(speedKmh: speed, level: level), at: clock) { actions.append(action) }
            clock += 1
        }
    }
}

@Test func switchesToEcoAboveThresholdAndBackBelowHysteresis() {
    var ride = Ride()
    ride.ride([(15, .normal), (21, .normal), (22, .normal), (23, .normal)])
    #expect(ride.actions == [.write(.eco)])

    ride.ride([(23, .eco), (19, .eco), (19, .eco), (19, .eco), (19, .eco)])
    #expect(ride.actions == [.write(.eco)], "19 km/h is inside the 18-20 band")

    ride.ride([(17, .eco), (17, .eco), (17, .eco), (17, .normal), (17, .normal)])
    #expect(ride.actions == [.write(.eco), .write(.normal)])
}

@Test func ignoresShortSpikeAboveThreshold() {
    var ride = Ride()
    ride.ride([(19, .normal), (21, .normal), (19, .normal), (21, .normal), (19, .normal)])

    #expect(ride.actions.isEmpty)
}

@Test func takesOverFromSportImmediatelyAtTheRightLevel() {
    var slow = Ride()
    slow.ride([(10, .sport)])
    var fast = Ride()
    fast.ride([(25, .turbo)])

    #expect(slow.actions == [.write(.normal)])
    #expect(fast.actions == [.write(.eco)])
}

@Test func handsBackWhenRiderChangesLevelOnTheDisplay() {
    var ride = Ride()
    ride.ride([(10, .normal), (10, .normal), (10, .sport)])

    #expect(ride.actions == [.handBack])
}

@Test func handsBackWhenBikeIgnoresTheWriteTwice() {
    var ride = Ride()
    ride.ride(Array(repeating: (25, .normal), count: 12))

    #expect(ride.actions == [.write(.eco), .write(.eco), .handBack])
}

@Test func controllerRestartReadoptsCurrentLevel() {
    var ride = Ride()
    ride.ride([(0, .normal)])
    _ = ride.rule.update(c21Stats(speedKmh: 0, controllerOn: false), at: ride.clock)
    ride.ride([(0, .eco), (0, .eco)])

    #expect(ride.actions.isEmpty)
}

@Test func boostHoldsNormalAtSpeedForTenSecondsThenReturnsToEco() {
    var ride = Ride()
    ride.ride([(22, .eco)])
    ride.boost()
    #expect(ride.actions == [.write(.normal)])

    ride.ride(Array(repeating: (24, .normal), count: 10))
    #expect(ride.actions == [.write(.normal)], "held through the boost despite being above the threshold")

    ride.ride(Array(repeating: (24, .normal), count: 3))
    #expect(ride.actions == [.write(.normal), .write(.eco)])
}

@Test func boostWhileAlreadyInNormalWritesNothing() {
    var ride = Ride()
    ride.ride([(15, .normal)])
    ride.boost()
    ride.ride(Array(repeating: (22, .normal), count: 5))

    #expect(ride.actions.isEmpty)
}

@Test func riderChangingLevelDuringBoostHandsBack() {
    var ride = Ride()
    ride.ride([(22, .eco)])
    ride.boost()
    ride.ride([(22, .normal), (22, .sport)])

    #expect(ride.actions == [.write(.normal), .handBack])
}

@Test func boostWithBikeOffDoesNothing() {
    var ride = Ride()
    ride.boost()

    #expect(ride.actions.isEmpty)
}

@Test func boostWhileSwitchingToEcoKeepsAutoWhicheverWriteLandsFirst() {
    var ecoLanded = Ride()
    ecoLanded.ride([(15, .normal), (22, .normal), (22, .normal), (22, .normal)])
    ecoLanded.boost()
    ecoLanded.ride([(22, .eco), (22, .eco), (22, .normal), (22, .normal)])
    #expect(ecoLanded.actions == [.write(.eco), .write(.normal)], "Eco landing before the boost isn't a rider change")
    #expect(ecoLanded.rule.isBoosting)

    var boostLanded = Ride()
    boostLanded.ride([(15, .normal), (22, .normal), (22, .normal), (22, .normal)])
    boostLanded.boost()
    boostLanded.ride([(22, .normal), (22, .normal)])
    #expect(boostLanded.actions == [.write(.eco), .write(.normal)])
    #expect(boostLanded.rule.isBoosting)
}
