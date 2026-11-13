import Foundation

public enum Frame {
    static let header: [UInt8] = [0x46, 0x64]
    static let pollType: UInt8 = 0x55
    static let notifyType: UInt8 = 0xAA
    static let writeType: UInt8 = 0xAA

    public static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(0, ^)
    }

    public static func poll(_ poll: Poll) -> Data {
        self.poll(register: poll.rawValue, length: poll.length)
    }

    public static func poll(register: UInt8, length: UInt8) -> Data {
        sealed(header + [pollType, length, register])
    }

    public static func write(_ register: UInt8, payload: [UInt8]) -> Data {
        sealed(header + [writeType, UInt8(payload.count), register] + payload)
    }

    private static func sealed(_ bytes: [UInt8]) -> Data {
        Data(bytes + [checksum(bytes)])
    }
}

public enum Poll: UInt8, CaseIterable, Sendable {
    /// The poll a reply answers. Discovery blocks share some registers but are 16 bytes long.
    public init?(register: UInt8, payloadLength: Int) {
        guard let poll = Poll(rawValue: register), Int(poll.length) == payloadLength else { return nil }
        self = poll
    }

    case handshake = 0x0D
    case stats = 0x05
    case battery = 0x7B
    case motor = 0x96
    case energy = 0xC8
    case controller = 0xAF
    case meter = 0x60
    case speedLimit = 0x3C

    public var name: String {
        switch self {
        case .handshake: "handshake"
        case .stats: "stats"
        case .battery: "battery"
        case .motor: "motor"
        case .energy: "energy"
        case .controller: "controller"
        case .meter: "meter"
        case .speedLimit: "speed_limit"
        }
    }

    public var length: UInt8 {
        switch self {
        case .handshake: 13
        case .stats: 53
        case .battery, .meter: 13
        case .motor, .energy, .controller: 12
        case .speedLimit: 1
        }
    }
}

public struct Notify: Equatable, Sendable {
    public let register: UInt8
    public let payload: [UInt8]
}

/// Turns the notify byte stream into checksummed frames. Junk before a header and
/// frames with a bad checksum are dropped.
public struct FrameAssembler: Sendable {
    private var buffer: [UInt8] = []
    private static let headerLength = 5
    private static let maxBuffer = 512

    public init() {}

    public mutating func feed(_ data: Data) -> [Notify] {
        buffer.append(contentsOf: data)
        if buffer.count > Self.maxBuffer { buffer.removeFirst(buffer.count - Self.maxBuffer) }

        var frames: [Notify] = []
        while true {
            guard let start = headerIndex() else {
                buffer.removeFirst(max(0, buffer.count - 2))
                break
            }
            buffer.removeFirst(start)
            guard buffer.count >= Self.headerLength else { break }
            let length = Int(buffer[3])
            let total = Self.headerLength + length + 1
            guard buffer.count >= total else { break }

            let frame = Array(buffer[0..<total])
            if Frame.checksum(frame.dropLast()) == frame.last {
                frames.append(Notify(register: frame[4], payload: Array(frame[Self.headerLength..<total - 1])))
                buffer.removeFirst(total)
            } else {
                buffer.removeFirst(1)
            }
        }
        return frames
    }

    private func headerIndex() -> Int? {
        guard buffer.count >= 3 else { return nil }
        for i in 0...(buffer.count - 3)
        where buffer[i] == Frame.header[0] && buffer[i + 1] == Frame.header[1] && buffer[i + 2] == Frame.notifyType {
            return i
        }
        return nil
    }
}
