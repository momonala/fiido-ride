import FiidoKit
import Foundation
import SwiftData

/// Writes three CSVs: `telemetry.csv` (one decoded row per STATS frame, other readings
/// carried forward), `frames.csv` (every raw frame, lossless) and `gps.csv`.
@ModelActor
actor Exporter {
    func export() throws -> [URL] {
        let rides = try modelContext.fetch(FetchDescriptor<Ride>(sortBy: [SortDescriptor(\.start)]))

        let folder = FileManager.default.temporaryDirectory.appending(path: "FiidoRide-export")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var telemetry = [Self.header(TelemetryRow.columns)]
        var frames = [Self.header(StoredFrame.columns)]
        var gps = [Self.header(GPSFix.columns)]

        for ride in rides {
            let id = ride.id
            let rideFrames = try modelContext.fetch(FetchDescriptor<RawFrame>(
                predicate: #Predicate { $0.rideID == id }, sortBy: [SortDescriptor(\.time)]))
            let points = try modelContext.fetch(FetchDescriptor<LocationPoint>(
                predicate: #Predicate { $0.rideID == id }, sortBy: [SortDescriptor(\.time)]))

            let stored = rideFrames.map { StoredFrame(time: $0.time, register: UInt8($0.register), payload: [UInt8]($0.payload)) }
            let fixes = points.map {
                GPSFix(time: $0.time, latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude,
                       speedKmh: $0.speedKmh, course: $0.course, horizontalAccuracy: $0.horizontalAccuracy)
            }
            frames += stored.map { Self.line(id, $0.time, $0.values) }
            gps += fixes.map { Self.line(id, $0.time, $0.values) }
            telemetry += TelemetryRow.rows(frames: stored, fixes: fixes).map { Self.line(id, $0.time, $0.values) }
        }

        let files = [("telemetry.csv", telemetry), ("frames.csv", frames), ("gps.csv", gps)]
        return try files.map { name, lines in
            let url = folder.appending(path: name)
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    private static func header(_ columns: [String]) -> String {
        (["ride_id", "time"] + columns).joined(separator: ",")
    }

    private static func line(_ ride: UUID, _ time: Date, _ values: [ExportValue?]) -> String {
        ([ride.uuidString, time.exportTimestamp] + values.map { $0.map(csv) ?? "" }).joined(separator: ",")
    }

    private static func csv(_ value: ExportValue) -> String {
        switch value {
        case .int(let number): "\(number)"
        case .double(let number): "\(number)"
        case .bool(let flag): "\(flag)"
        case .text(let text): text
        case .bytes(let bytes): Data(bytes).hex
        }
    }
}

extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined() }
}
