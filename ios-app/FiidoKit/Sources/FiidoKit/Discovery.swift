import Foundation

/// Reads the whole register map in fixed blocks, including addresses no known poll covers.
public enum Discovery {
    public static let blockLength: UInt8 = 16
    public static let blocks: [UInt8] = stride(from: 0, to: 256, by: Int(blockLength)).map { UInt8($0) }

    public static func frame(_ block: UInt8) -> Data {
        Frame.poll(register: block, length: blockLength)
    }
}
