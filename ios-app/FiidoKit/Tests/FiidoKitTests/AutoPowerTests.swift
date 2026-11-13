import Foundation
import Testing
@testable import FiidoKit

/// One STATS sample per second, each preceded by an RSSI reading.
private struct Parking {
    var rule: AutoPower
    var clock = Date(timeIntervalSince1970: 1000)
    var actions: [AutoPower.Action] = []

    init() {
        rule = AutoPower()
    }

    mutating func sample(_ seconds: Int, on: Bool, rssi: Double, speed: Double = 0, atHome: Bool = false) {
        for _ in 0..<seconds {
            rule.record(rssi: rssi)
            let stats = c21Stats(speedKmh: speed, controllerOn: on)
            if let action = rule.update(stats, at: clock, mayPowerOn: !atHome) { actions.append(action) }
            clock += 1
        }
    }

    mutating func outOfRange(for seconds: TimeInterval) {
        rule.linkLost(at: clock)
        clock += seconds
    }
}

@Test func turnsOnOnlyOnceCloseAfterDroppingOutOfRange() {
    var parking = Parking()
    parking.outOfRange(for: 61)
    parking.sample(3, on: false, rssi: -80)
    #expect(parking.actions.isEmpty, "back in range but not yet near")
    parking.sample(1, on: false, rssi: -65)
    #expect(parking.actions.isEmpty, "one near reading could be a stray")
    parking.sample(1, on: false, rssi: -65)
    #expect(parking.actions == [.powerOn])
}

@Test func strayStrongReadingsBetweenWeakOnesDoNotTurnBikeOn() {
    var parking = Parking()
    parking.outOfRange(for: 61)
    for _ in 0..<5 {
        parking.sample(1, on: false, rssi: -60)
        parking.sample(1, on: false, rssi: -85)
    }
    #expect(parking.actions.isEmpty)
}

@Test func briefDropoutOrAppRelaunchDoesNotTurnBikeOn() {
    var parking = Parking()
    parking.sample(5, on: false, rssi: -50)
    parking.outOfRange(for: 10)
    parking.sample(5, on: false, rssi: -50)
    #expect(parking.actions.isEmpty)
}

@Test func turnsOffWhenWalkingAwayFromParkedBike() {
    var parking = Parking()
    parking.sample(3, on: true, rssi: -50)
    parking.sample(3, on: true, rssi: -90)
    #expect(parking.actions.isEmpty, "the first weak sample starts the 3 s window")
    parking.sample(1, on: true, rssi: -90)
    #expect(parking.actions == [.powerOff])
}

@Test func ridingArmsItEvenIfThePhoneNeverReadNear() {
    var parking = Parking()
    parking.sample(10, on: true, rssi: -60, speed: 15)
    parking.sample(5, on: true, rssi: -90)
    #expect(parking.actions == [.powerOff])
}

@Test func neverTurnsOffWhileMoving() {
    var parking = Parking()
    parking.sample(3, on: true, rssi: -50)
    parking.sample(20, on: true, rssi: -90, speed: 12)
    #expect(parking.actions.isEmpty)
}

@Test func doesNotTurnOffWhileApproachingAfterAutoOn() {
    var parking = Parking()
    parking.outOfRange(for: 61)
    parking.sample(2, on: false, rssi: -45)
    parking.sample(20, on: true, rssi: -75)
    #expect(parking.actions == [.powerOn])
}

@Test func retriesAMissedPowerOffOnceThenGivesUp() {
    var parking = Parking()
    parking.sample(3, on: true, rssi: -50)
    parking.sample(30, on: true, rssi: -90)
    #expect(parking.actions == [.powerOff, .powerOff, .gaveUp])
}

@Test func turnsBackOnWhenReturningAfterAwayPowerOff() {
    var parking = Parking()
    parking.sample(3, on: true, rssi: -50)
    parking.sample(4, on: true, rssi: -90)
    parking.sample(5, on: false, rssi: -90)
    parking.sample(3, on: false, rssi: -75)
    #expect(parking.actions == [.powerOff], "closer, but not near yet")
    parking.sample(2, on: false, rssi: -65)
    #expect(parking.actions == [.powerOff, .powerOn])
}

@Test func manualPowerOffNearTheBikeStaysOff() {
    var parking = Parking()
    parking.sample(3, on: true, rssi: -50)
    parking.sample(4, on: true, rssi: -90)
    parking.sample(2, on: false, rssi: -90)
    parking.sample(3, on: true, rssi: -50)
    parking.sample(10, on: false, rssi: -50)
    #expect(parking.actions == [.powerOff])
}

@Test func staysOffNearTheBikeAtHomeUntilLeavingHome() {
    var parking = Parking()
    parking.outOfRange(for: 61)
    parking.sample(5, on: false, rssi: -45, atHome: true)
    #expect(parking.actions.isEmpty)
    parking.sample(1, on: false, rssi: -45)
    #expect(parking.actions == [.powerOn])
}

@Test func noRetryOnceBackNearTheBike() {
    var parking = Parking()
    parking.sample(3, on: true, rssi: -50)
    parking.sample(4, on: true, rssi: -90)
    #expect(parking.actions == [.powerOff])
    parking.sample(10, on: true, rssi: -50)
    #expect(parking.actions == [.powerOff], "the bike ignored the first command, but I came back")
}
