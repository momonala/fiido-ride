import CoreLocation
import FiidoKit
import Foundation
import Observation
import os
import SwiftData

/// Opens a ride when the controller switches on and closes it after the controller
/// has been off, or the bike silent, for `idleTimeout`. Every frame received while a
/// ride is open is stored as-is.
@MainActor @Observable
final class RideRecorder {
    private(set) var currentRide: Ride?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let location: LocationTracker
    @ObservationIgnored private var lastActive = Date.distantPast
    @ObservationIgnored private var lastFrame = Date.distantPast
    @ObservationIgnored private var startBatteryPending = false
    @ObservationIgnored private var unsaved = 0
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    private let idleTimeout: TimeInterval = 120
    private static let log = Logger(subsystem: "org.mnalavadi.FiidoRide", category: "RideRecorder")

    init(context: ModelContext, location: LocationTracker) {
        self.context = context
        self.location = location
        location.onLocation = { [weak self] in self?.record($0) }
        closeLeftoverRides()
    }

    func record(_ notify: Notify, at time: Date) {
        if let ride = currentRide, time.timeIntervalSince(lastFrame) > idleTimeout {
            close(ride, at: lastFrame)
        }
        lastFrame = time

        if notify.register == Poll.stats.rawValue, let stats = Stats(payload: notify.payload) {
            track(stats, at: time)
        } else if notify.register == Poll.motor.rawValue, let motor = Motor(payload: notify.payload) {
            track(motor)
        }
        guard let ride = currentRide else { return }
        context.insert(RawFrame(rideID: ride.id, time: time, register: notify.register, payload: notify.payload))
        saveEvery(50)
    }

    func closeRideIfBikeStaysSilent() {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(idleTimeout))
            guard !Task.isCancelled, let ride = currentRide,
                  Date().timeIntervalSince(lastFrame) >= idleTimeout else { return }
            close(ride, at: lastFrame)
        }
    }

    private func track(_ stats: Stats, at time: Date) {
        if stats.controllerOn { lastActive = time }

        if let ride = currentRide {
            ride.end = time
            ride.endOdometerKm = stats.totalKm
            ride.maxSpeedKmh = max(ride.maxSpeedKmh, stats.speedKmh)
            if time.timeIntervalSince(lastActive) > idleTimeout { close(ride, at: lastActive) }
        } else if stats.controllerOn {
            let ride = Ride(start: time, odometerKm: stats.totalKm, battery: 0)
            startBatteryPending = true
            context.insert(ride)
            currentRide = ride
            location.start()
        }
    }

    private func track(_ motor: Motor) {
        guard let ride = currentRide else { return }
        if startBatteryPending {
            ride.startBattery = motor.batteryPercent
            startBatteryPending = false
        }
        ride.endBattery = motor.batteryPercent
    }

    private func record(_ fix: CLLocation) {
        guard let ride = currentRide, fix.horizontalAccuracy >= 0 else { return }
        context.insert(LocationPoint(
            rideID: ride.id,
            time: fix.timestamp,
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            altitude: fix.altitude,
            speedKmh: max(0, fix.speed) * 3.6,
            course: fix.course,
            horizontalAccuracy: fix.horizontalAccuracy
        ))
        saveEvery(50)
    }

    private func close(_ ride: Ride, at time: Date) {
        ride.end = max(ride.start, time)
        ride.isOpen = false
        currentRide = nil
        location.stop()
        keepOrDiscard(ride)
    }

    private func closeLeftoverRides() {
        let open = (try? context.fetch(FetchDescriptor<Ride>(predicate: #Predicate { $0.isOpen }))) ?? []
        open.forEach {
            $0.isOpen = false
            keepOrDiscard($0)
        }
        save()
    }

    private func keepOrDiscard(_ ride: Ride) {
        guard !ride.wentAnywhere else {
            save()
            return
        }
        do {
            try context.deleteRide(ride)
        } catch {
            Self.log.error("Deleting a zero-distance ride failed: \(error)")
        }
    }

    private func saveEvery(_ count: Int) {
        unsaved += 1
        if unsaved >= count { save() }
    }

    private func save() {
        unsaved = 0
        do {
            try context.save()
        } catch {
            Self.log.error("SwiftData save failed: \(error)")
        }
    }
}
