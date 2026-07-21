import Foundation

enum ZipWriter {
    static func writeArchive(
        entries: [String: Data],
        to destinationURL: URL
    ) throws {
        var localData = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for (path, contents) in entries.sorted(by: { $0.key < $1.key }) {
            let pathData = Data(path.utf8)
            let crc = crc32(contents)

            var localHeader = Data()
            localHeader.appendUInt32(0x04034b50)
            localHeader.appendUInt16(20)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt32(crc)
            localHeader.appendUInt32(UInt32(contents.count))
            localHeader.appendUInt32(UInt32(contents.count))
            localHeader.appendUInt16(UInt16(pathData.count))
            localHeader.appendUInt16(0)
            localHeader.append(pathData)

            localData.append(localHeader)
            localData.append(contents)

            var centralHeader = Data()
            centralHeader.appendUInt32(0x02014b50)
            centralHeader.appendUInt16(20)
            centralHeader.appendUInt16(20)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt32(crc)
            centralHeader.appendUInt32(UInt32(contents.count))
            centralHeader.appendUInt32(UInt32(contents.count))
            centralHeader.appendUInt16(UInt16(pathData.count))
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt32(0)
            centralHeader.appendUInt32(offset)
            centralHeader.append(pathData)

            centralDirectory.append(centralHeader)
            offset += UInt32(localHeader.count + contents.count)
        }

        var archive = localData
        archive.append(centralDirectory)

        var endRecord = Data()
        endRecord.appendUInt32(0x06054b50)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(UInt16(entries.count))
        endRecord.appendUInt16(UInt16(entries.count))
        endRecord.appendUInt32(UInt32(centralDirectory.count))
        endRecord.appendUInt32(offset)
        endRecord.appendUInt16(0)
        archive.append(endRecord)

        try archive.write(to: destinationURL, options: .atomic)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
