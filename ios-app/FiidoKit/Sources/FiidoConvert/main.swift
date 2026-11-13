import FiidoKit
import Foundation
import SQLite3

/// Converts a copy of the app's SwiftData store into a plain SQLite file:
/// `fiido-convert <default.store> <fiido.sqlite>`. Prints row counts as JSON.

struct ConvertError: Error, CustomStringConvertible {
    let description: String
}

nonisolated(unsafe) private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Database {
    private var handle: OpaquePointer?

    init(path: String, readOnly: Bool) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            throw ConvertError(description: "open \(path): \(String(cString: sqlite3_errmsg(handle)))")
        }
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error(sql) }
    }

    func query(_ sql: String, row: (OpaquePointer) throws -> Void) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { try row(statement) }
    }

    func insert(into table: String, columns: [String], rows: [[ExportValue?]]) throws {
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ",")
        let statement = try prepare("INSERT INTO \(table) (\(columns.joined(separator: ","))) VALUES (\(placeholders))")
        defer { sqlite3_finalize(statement) }
        for values in rows {
            sqlite3_reset(statement)
            for (index, value) in values.enumerated() {
                let position = Int32(index + 1)
                switch value {
                case nil: sqlite3_bind_null(statement, position)
                case .int(let number): sqlite3_bind_int64(statement, position, Int64(number))
                case .double(let number): sqlite3_bind_double(statement, position, number)
                case .bool(let flag): sqlite3_bind_int64(statement, position, flag ? 1 : 0)
                case .text(let text): sqlite3_bind_text(statement, position, text, -1, transient)
                case .bytes(let bytes): sqlite3_bind_blob(statement, position, bytes, Int32(bytes.count), transient)
                }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw error("insert into \(table)") }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error(sql) }
        return statement
    }

    private func error(_ context: String) -> ConvertError {
        ConvertError(description: "\(context): \(String(cString: sqlite3_errmsg(handle)))")
    }
}

/// SwiftData (Core Data) stores dates as seconds since 2001 and UUIDs as 16-byte blobs.
enum Column {
    static func date(_ statement: OpaquePointer, _ index: Int32) -> Date {
        Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, index))
    }

    static func uuid(_ statement: OpaquePointer, _ index: Int32) throws -> String {
        let bytes = blob(statement, index)
        guard bytes.count == 16 else { throw ConvertError(description: "UUID column holds \(bytes.count) bytes") }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString
    }

    static func blob(_ statement: OpaquePointer, _ index: Int32) -> [UInt8] {
        guard let pointer = sqlite3_column_blob(statement, index) else { return [] }
        return [UInt8](UnsafeRawBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(statement, index))))
    }
}

func iso(_ date: Date) -> ExportValue {
    .text(date.exportTimestamp)
}

let rideColumns = ["id", "start", "end", "start_odometer_km", "end_odometer_km", "distance_km",
                   "start_battery_pct", "end_battery_pct", "max_speed_kmh", "is_open"]
let perRide = ["ride_id", "time"]

/// Column types come from the bound values; SQLite stores each as given.
let schema = """
    CREATE TABLE rides (\(rideColumns.joined(separator: ", ")), PRIMARY KEY (id));
    CREATE TABLE frames (\((perRide + StoredFrame.columns).joined(separator: ", ")));
    CREATE TABLE gps (\((perRide + GPSFix.columns).joined(separator: ", ")));
    CREATE TABLE telemetry (\((perRide + TelemetryRow.columns).joined(separator: ", ")));
    CREATE INDEX frames_ride_time ON frames (ride_id, time);
    CREATE INDEX gps_ride_time ON gps (ride_id, time);
    CREATE INDEX telemetry_ride_time ON telemetry (ride_id, time);
    """

func convert(store: String, output: String) throws -> [String: Int] {
    let source = try Database(path: store, readOnly: true)
    try source.query("PRAGMA quick_check") { row in
        let result = String(cString: sqlite3_column_text(row, 0))
        guard result == "ok" else { throw ConvertError(description: "copied store is inconsistent: \(result)") }
    }

    var rides: [[ExportValue?]] = []
    try source.query("""
        SELECT ZID, ZSTART, ZEND, ZSTARTODOMETERKM, ZENDODOMETERKM, ZSTARTBATTERY, ZENDBATTERY, ZMAXSPEEDKMH, ZISOPEN
        FROM ZRIDE ORDER BY ZSTART
        """) { row in
        let startKm = sqlite3_column_double(row, 3)
        let endKm = sqlite3_column_double(row, 4)
        rides.append([
            .text(try Column.uuid(row, 0)), iso(Column.date(row, 1)), iso(Column.date(row, 2)),
            .double(startKm), .double(endKm), .double(endKm - startKm),
            .int(Int(sqlite3_column_int64(row, 5))), .int(Int(sqlite3_column_int64(row, 6))),
            .double(sqlite3_column_double(row, 7)), .bool(sqlite3_column_int64(row, 8) != 0),
        ])
    }

    var fixesByRide: [String: [GPSFix]] = [:]
    try source.query("""
        SELECT ZRIDEID, ZTIME, ZLATITUDE, ZLONGITUDE, ZALTITUDE, ZSPEEDKMH, ZCOURSE, ZHORIZONTALACCURACY
        FROM ZLOCATIONPOINT ORDER BY ZRIDEID, ZTIME
        """) { row in
        fixesByRide[try Column.uuid(row, 0), default: []].append(GPSFix(
            time: Column.date(row, 1), latitude: sqlite3_column_double(row, 2), longitude: sqlite3_column_double(row, 3),
            altitude: sqlite3_column_double(row, 4), speedKmh: sqlite3_column_double(row, 5),
            course: sqlite3_column_double(row, 6), horizontalAccuracy: sqlite3_column_double(row, 7)))
    }

    var framesByRide: [String: [StoredFrame]] = [:]
    try source.query("SELECT ZRIDEID, ZTIME, ZREGISTER, ZPAYLOAD FROM ZRAWFRAME ORDER BY ZRIDEID, ZTIME") { row in
        framesByRide[try Column.uuid(row, 0), default: []].append(StoredFrame(
            time: Column.date(row, 1), register: UInt8(truncatingIfNeeded: sqlite3_column_int64(row, 2)),
            payload: Column.blob(row, 3)))
    }

    let partial = output + ".partial"
    try? FileManager.default.removeItem(atPath: partial)
    let target = try Database(path: partial, readOnly: false)
    try target.execute(schema)
    try target.execute("BEGIN")
    try target.insert(into: "rides", columns: rideColumns, rows: rides)
    var counts = ["rides": rides.count, "frames": 0, "gps": 0, "telemetry": 0]
    for (ride, fixes) in fixesByRide {
        try target.insert(into: "gps", columns: perRide + GPSFix.columns,
                          rows: fixes.map { [.text(ride), iso($0.time)] + $0.values })
        counts["gps", default: 0] += fixes.count
    }
    for (ride, frames) in framesByRide {
        try target.insert(into: "frames", columns: perRide + StoredFrame.columns,
                          rows: frames.map { [.text(ride), iso($0.time)] + $0.values })
        let telemetry = TelemetryRow.rows(frames: frames, fixes: fixesByRide[ride] ?? [])
        try target.insert(into: "telemetry", columns: perRide + TelemetryRow.columns,
                          rows: telemetry.map { [.text(ride), iso($0.time)] + $0.values })
        counts["frames", default: 0] += frames.count
        counts["telemetry", default: 0] += telemetry.count
    }
    try target.execute("COMMIT")

    if FileManager.default.fileExists(atPath: output) { try FileManager.default.removeItem(atPath: output) }
    try FileManager.default.moveItem(atPath: partial, toPath: output)
    return counts
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: fiido-convert <default.store> <fiido.sqlite>\n".utf8))
    exit(2)
}
do {
    let counts = try convert(store: arguments[1], output: arguments[2])
    let json = try JSONSerialization.data(withJSONObject: counts, options: .sortedKeys)
    print(String(decoding: json, as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("fiido-convert: \(error)\n".utf8))
    exit(1)
}
