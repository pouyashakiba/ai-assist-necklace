import Foundation

enum AudioPacket {
    static func wav(pcm: Data, sampleRate: UInt32) -> Data {
        var result = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { result.append(contentsOf: $0) } }
        append(UInt32(pcm.count + 36)); result.append(Data("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16)); result.append(Data("data".utf8)); append(UInt32(pcm.count)); result.append(pcm)
        return result
    }
}

struct PCMAssembler {
    private(set) var data = Data()
    private(set) var nextSequence: UInt16 = 0
    private(set) var expectedBytes = 0
    mutating func begin(bytes: Int) throws {
        guard bytes > 0, bytes <= 128000, bytes % 2 == 0 else { throw CompanionError.unavailable("Invalid pendant recording size.") }
        data = Data(); nextSequence = 0; expectedBytes = bytes
    }
    mutating func append(_ packet: Data) throws {
        guard packet.count >= 3, expectedBytes > 0 else { throw CompanionError.unavailable("Unexpected pendant audio packet.") }
        let bytes = [UInt8](packet)
        let sequence = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        guard sequence == nextSequence, data.count + packet.count - 2 <= expectedBytes else { throw CompanionError.unavailable("A Bluetooth audio packet was lost. Please record again.") }
        data.append(packet.dropFirst(2)); nextSequence &+= 1
    }
    func finish() throws -> Data {
        guard data.count == expectedBytes, expectedBytes > 0 else { throw CompanionError.unavailable("Pendant recording was incomplete. Please try again.") }
        return data
    }
}
