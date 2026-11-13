import Foundation
import Testing
@testable import FiidoKit

/// STATS reply captured from the C21 on 2026-11-13: parked, display in Normal,
/// odometer 1600.0 km, battery 70 %.
let c21StatsFrame: [UInt8] = hex("""
    4664 AA35 0500 0000 0000 0000 0000
    0015 1617 1819 2021 2223 2425 0000
    0000 3E80 0000 0000 4650 02A1 0000
    0000 2062 2B03 081E 4F04 0000 0000
    0000 90
    """)

/// The C21 capture with speed, level and controller power replaced.
func c21Stats(speedKmh: Double, level: AssistLevel = .normal, controllerOn: Bool = true) -> Stats {
    var payload = Array(c21StatsFrame[5..<58])
    let tenths = UInt16(speedKmh * 10)
    payload[29] = UInt8(tenths >> 8)
    payload[30] = UInt8(tenths & 0xFF)
    payload[33] = level.rawValue
    payload[34] = controllerOn ? payload[34] | 0x80 : payload[34] & 0x7F
    return Stats(payload: payload)!
}

func hex(_ string: String) -> [UInt8] {
    let digits = string.filter(\.isHexDigit)
    return stride(from: 0, to: digits.count, by: 2).map {
        let start = digits.index(digits.startIndex, offsetBy: $0)
        return UInt8(digits[start...digits.index(after: start)], radix: 16)!
    }
}

@Test func pollAndWriteFramesMatchWhatTheBikeAccepted() {
    #expect(Array(Frame.poll(.stats)) == hex("46 64 55 35 05 47"))
    #expect(Array(AssistLevel.eco.writeFrame) == hex("46 64 AA 01 26 01 AE"))
    #expect(Array(AssistLevel.normal.writeFrame) == hex("46 64 AA 01 26 02 AD"))
}

@Test func assemblerFindsFrameSplitAcrossNotifiesAfterJunk() {
    var assembler = FrameAssembler()
    let first = assembler.feed(Data([0x00, 0x13] + c21StatsFrame[0..<20]))
    let second = assembler.feed(Data(c21StatsFrame[20...]))

    #expect(first.isEmpty)
    #expect(second.count == 1)
    #expect(second.first?.register == Poll.stats.rawValue)
    #expect(second.first?.payload.count == 53)
}

@Test func assemblerDropsFrameWithBadChecksum() {
    var assembler = FrameAssembler()
    var corrupted = c21StatsFrame
    corrupted[40] ^= 0x01

    #expect(assembler.feed(Data(corrupted)).isEmpty)
    #expect(assembler.feed(Data(c21StatsFrame)).count == 1)
}

@Test func decodesC21Stats() throws {
    let stats = try #require(Stats(payload: Array(c21StatsFrame[5..<58])))

    #expect(stats.totalKm == 1600.0)
    #expect(stats.tripKm == 0)
    #expect(stats.speedKmh == 0)
    #expect(stats.batteryBars == 70)
    #expect(stats.levelCount == 5)
    #expect(stats.level == .normal)
    #expect(stats.controllerOn)
    #expect(stats.speedLimitOn)
    #expect(!stats.lightOn)
    #expect(stats.hasTorqueSensor)
    #expect(!stats.hasEnergyMeter)
    #expect(!stats.hasBatteryCurrentSensor)
    #expect(!stats.hasBatteryLink)
}

@Test func rejectsStatsWithImpossibleSpeed() {
    var payload = Array(c21StatsFrame[5..<58])
    payload[29] = 0x10  // 409.6 km/h

    #expect(Stats(payload: payload) == nil)
}

@Test func lightWriteFlipsOnlyTheLightBit() throws {
    let stats = try #require(Stats(payload: Array(c21StatsFrame[5..<58])))

    #expect(Array(stats.lightWriteFrame(on: true)) == hex("46 64 AA 01 27 A9 07"))
    #expect(Array(stats.lightWriteFrame(on: false)) == hex("46 64 AA 01 27 A1 0F"))
}

@Test func powerWriteFlipsOnlyThePowerBit() throws {
    let stats = try #require(Stats(payload: Array(c21StatsFrame[5..<58])))

    #expect(Array(stats.powerWriteFrame(on: false)) == hex("46 64 AA 01 27 21 8F"))
    #expect(Array(stats.powerWriteFrame(on: true)) == hex("46 64 AA 01 27 A1 0F"))
}

@Test func hornAndKeySoundWritesTouchOnlyTheirBits() throws {
    let stats = try #require(Stats(payload: Array(c21StatsFrame[5..<58])))

    #expect(stats.hornOn)
    #expect(stats.keySoundOn)
    #expect(Array(stats.hornWriteFrame(on: false)) == hex("46 64 AA 01 38 04 B5"))
    #expect(Array(stats.keySoundWriteFrame(on: false)) == hex("46 64 AA 01 2C 30 95"))
}

@Test func speedLimitWritesMatchTheTwoPhaseSequence() throws {
    let stats = try #require(Stats(payload: Array(c21StatsFrame[5..<58])))
    #expect(Array(Frame.poll(.speedLimit)) == hex("46 64 55 01 3C 4A"))

    let legal = stats.speedLimitWrite(.legal)
    #expect(legal.first.map(Array.init) == [hex("46 64 AA 01 2C A0 05")])
    #expect(legal.then.map(Array.init) == [hex("46 64 AA 01 3C 19 AC"), hex("46 64 AA 01 27 A1 0F")])
    #expect(!legal.delayThen)

    let none = stats.speedLimitWrite(.none)
    #expect(none.first.isEmpty)
    #expect(none.then.map(Array.init) == [hex("46 64 AA 01 3C 64 D1"), hex("46 64 AA 01 27 81 2F")])
    #expect(none.delayThen)
}

@Test func riderPowerIsTorqueTimesAngularVelocity() throws {
    let payload: [UInt8] = [0x01, 0x90, 0x00, 0x3C, 0, 0, 0, 0, 0, 0, 0x0E, 0x10]  // 40.0 Nm, 60 rpm, 3600 s
    let energy = try #require(Energy(payload: payload))

    #expect(abs(energy.riderPowerW - 251.327) < 0.01)
    #expect(energy.uptimeSeconds == 3600)
}

@Test func traceDropsPointsOlderThanTheWindow() {
    var trace = RollingTrace(window: 60)
    let start = Date(timeIntervalSince1970: 0)
    trace.append(speedKmh: 0, at: start)
    trace.append(speedKmh: 9, at: start + 0.5)
    trace.append(speedKmh: 18, at: start + 1)
    trace.append(speedKmh: 20, at: start + 61)

    #expect(trace.points.map(\.speedKmh) == [18, 20])
}

@Test func discoveryCoversTheWholeMapInSixteenBlocks() {
    #expect(Discovery.blocks.count == 16)
    #expect(Discovery.blocks.last == 0xF0)
    #expect(Array(Discovery.frame(0x40)) == hex("46 64 55 10 40 27"))
}

@Test func decodesC21BatteryLevelFromMotorPoll() throws {
    let full = try #require(Motor(payload: [0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x18, 0x00, 0x63, 0x01, 0x5E, 0x00]))
    let afterRide = try #require(Motor(payload: [0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x18, 0x00, 0x36, 0x01, 0x5E, 0x00]))

    #expect(full.batteryPercent == 99)
    #expect(afterRide.batteryPercent == 54)
    #expect(full.ratedPowerW == 350)
}
