import Foundation
import SwiftData

@Model
final class Ride {
    #Index<Ride>([\.start])

    @Attribute(.unique) var id: UUID
    var start: Date
    var end: Date
    var startOdometerKm: Double
    var endOdometerKm: Double
    var startBattery: Int
    var endBattery: Int
    var maxSpeedKmh: Double
    var isOpen: Bool

    init(start: Date, odometerKm: Double, battery: Int) {
        id = UUID()
        self.start = start
        end = start
        startOdometerKm = odometerKm
        endOdometerKm = odometerKm
        startBattery = battery
        endBattery = battery
        maxSpeedKmh = 0
        isOpen = true
    }

    var distanceKm: Double { endOdometerKm - startOdometerKm }
    private static let odometerStepKm = 0.1
    var wentAnywhere: Bool { distanceKm >= Self.odometerStepKm / 2 }
    var duration: TimeInterval { end.timeIntervalSince(start) }
    /// A ride that ends higher than it started, after a start reading taken under load, counts as 0.
    var batteryUsed: Int { max(0, startBattery - endBattery) }

    var batteryPerKm: Double? { Self.batteryPerKm(used: batteryUsed, distanceKm: distanceKm) }

    static func batteryPerKm(used: Int, distanceKm: Double) -> Double? {
        distanceKm >= 1 && used > 0 ? Double(used) / distanceKm : nil
    }
}

/// Rides of one day, or of one charge: from a ride that started well above where the previous one ended up to the next such ride.
struct RideGroup: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case days = "Days", charges = "Charges", rides = "Rides"
        var id: Self { self }
    }

    let kind: Kind
    /// Oldest first, never empty.
    let rides: [Ride]
    var startsAfterCharge = false

    var id: Date { start }
    var start: Date { rides[0].start }
    var isOpen: Bool { rides.contains(where: \.isOpen) }
    var distanceKm: Double { rides.map(\.distanceKm).reduce(0, +) }
    var duration: TimeInterval { rides.map(\.duration).reduce(0, +) }
    var maxSpeedKmh: Double { rides.map(\.maxSpeedKmh).max() ?? 0 }
    var startBattery: Int { rides[0].startBattery }
    var endBattery: Int { rides[rides.count - 1].endBattery }
    var batteryUsed: Int { rides.map(\.batteryUsed).reduce(0, +) }
    var batteryPerKm: Double? { Ride.batteryPerKm(used: batteryUsed, distanceKm: distanceKm) }

    /// `charges` newest first.
    static func chargeRange(_ charges: [RideGroup], battery: Int) -> (leftKm: Double, chargeKm: Double)? {
        guard let latest = charges.first else { return nil }
        let current = isCharge(from: latest.endBattery, to: battery) ? nil : latest
        guard let perKm = current?.batteryPerKm ?? charges.lazy.compactMap(\.batteryPerKm).first else { return nil }
        let left = Double(battery) / perKm
        return (left, (current?.distanceKm ?? 0) + left)
    }

    /// Newest group first. `rides` must be oldest first.
    static func grouping(_ rides: [Ride], by kind: Kind) -> [RideGroup] {
        let startsGroup: (Ride, Ride) -> Bool = switch kind {
        case .rides: { _, _ in true }
        case .days: { !Calendar.current.isDate($0.start, inSameDayAs: $1.start) }
        case .charges: { isCharge(from: $0.endBattery, to: $1.startBattery) }
        }
        var groups: [[Ride]] = []
        for ride in rides {
            if let last = groups.last?.last, !startsGroup(last, ride) {
                groups[groups.count - 1].append(ride)
            } else {
                groups.append([ride])
            }
        }
        return groups.indices.reversed().map { index in
            let previous = index > 0 ? groups[index - 1].last : nil
            return RideGroup(kind: kind, rides: groups[index],
                             startsAfterCharge: previous.map { isCharge(from: $0.endBattery, to: groups[index][0].startBattery) } ?? false)
        }
    }

    static func isCharge(from previousBattery: Int, to battery: Int) -> Bool {
        battery >= previousBattery + minimumChargePoints
    }

    private static let minimumChargePoints = 10
}

/// One notify frame from the bike, stored exactly as received.
@Model
final class RawFrame {
    #Index<RawFrame>([\.rideID, \.time])

    var rideID: UUID
    var time: Date
    var register: Int
    var payload: Data

    init(rideID: UUID, time: Date, register: UInt8, payload: [UInt8]) {
        self.rideID = rideID
        self.time = time
        self.register = Int(register)
        self.payload = Data(payload)
    }
}

@Model
final class LocationPoint {
    #Index<LocationPoint>([\.rideID, \.time])

    var rideID: UUID
    var time: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speedKmh: Double
    var course: Double
    var horizontalAccuracy: Double

    init(rideID: UUID, time: Date, latitude: Double, longitude: Double, altitude: Double,
         speedKmh: Double, course: Double, horizontalAccuracy: Double) {
        self.rideID = rideID
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speedKmh = speedKmh
        self.course = course
        self.horizontalAccuracy = horizontalAccuracy
    }
}

extension ModelContext {
    func deleteRide(_ ride: Ride) throws {
        let id = ride.id
        try delete(model: RawFrame.self, where: #Predicate { $0.rideID == id })
        try delete(model: LocationPoint.self, where: #Predicate { $0.rideID == id })
        delete(ride)
        try save()
    }
}
