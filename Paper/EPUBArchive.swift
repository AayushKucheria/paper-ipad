import Foundation
import zlib

enum EPUBError: LocalizedError {
    case invalidArchive, invalidPublication, unsupportedArchive, sizeLimit

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "This file is not a readable EPUB archive."
        case .invalidPublication: return "This EPUB does not contain readable HTML chapters."
        case .unsupportedArchive: return "This EPUB uses encryption or an unsupported archive format. Choose an unlocked EPUB."
        case .sizeLimit: return "This EPUB is too large to open on this iPad."
        }
    }
}

struct EPUBArchive {
    // Bound allocations before inflating a file selected in Files or downloaded from Reader.
    static let maxArchiveBytes = 100 * 1024 * 1024
    private static let maxEntryBytes = 40 * 1024 * 1024
    private static let maxExpandedBytes = 250 * 1024 * 1024

    private struct Entry {
        let path: String
        let method: UInt16
        let crc: UInt32
        let compressed: Int
        let expanded: Int
        let offset: Int
    }

    static func extract(_ archive: Data, to directory: URL) throws {
        guard archive.count <= maxArchiveBytes else { throw EPUBError.sizeLimit }
        guard archive.count >= 22 else { throw EPUBError.invalidArchive }
        var footer: Int?
        for index in stride(from: archive.count - 22, through: max(0, archive.count - 65_557), by: -1) {
            if archive.u32(index) == 0x06054b50, index + 22 + Int(archive.u16(index + 20)) == archive.count {
                footer = index
                break
            }
        }
        guard let footer else { throw EPUBError.invalidArchive }
        guard archive.u16(footer + 4) == 0, archive.u16(footer + 6) == 0,
              archive.u16(footer + 8) == archive.u16(footer + 10) else { throw EPUBError.unsupportedArchive }
        let count = Int(archive.u16(footer + 10))
        let centralStart = Int(archive.u32(footer + 16))
        let centralSize = Int(archive.u32(footer + 12))
        guard (1...10_000).contains(count), centralStart + centralSize <= footer else { throw EPUBError.unsupportedArchive }
        var cursor = centralStart
        var entries: [Entry] = []
        var expandedTotal = 0
        var paths: Set<String> = []
        for _ in 0..<count {
            guard cursor + 46 <= centralStart + centralSize,
                  archive.u32(cursor) == 0x02014b50 else { throw EPUBError.invalidArchive }
            let nameBytes = Int(archive.u16(cursor + 28))
            let nameEnd = cursor + 46 + nameBytes
            let next = nameEnd + Int(archive.u16(cursor + 30)) + Int(archive.u16(cursor + 32))
            guard next <= centralStart + centralSize,
                  let name = String(data: archive[(cursor + 46)..<nameEnd], encoding: .utf8),
                  !name.isEmpty else { throw EPUBError.invalidArchive }
            let directoryEntry = name.hasSuffix("/")
            let path = directoryEntry ? String(name.dropLast()) : name
            guard Self.safeComponents(path) != nil else { throw EPUBError.invalidArchive }
            let unixMode = (archive.u32(cursor + 38) >> 16) & 0xf000
            guard unixMode != 0xa000, archive.u16(cursor + 8) & 0x0041 == 0,
                  archive.u16(cursor + 34) == 0 else { throw EPUBError.unsupportedArchive }
            if !directoryEntry {
                let expanded = Int(archive.u32(cursor + 24))
                expandedTotal += expanded
                guard expanded <= maxEntryBytes, expandedTotal <= maxExpandedBytes else { throw EPUBError.sizeLimit }
                guard paths.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw EPUBError.invalidArchive }
                entries.append(Entry(path: path, method: archive.u16(cursor + 10), crc: archive.u32(cursor + 16),
                                     compressed: Int(archive.u32(cursor + 20)), expanded: expanded,
                                     offset: Int(archive.u32(cursor + 42))))
            }
            cursor = next
        }
        let manager = FileManager.default
        for entry in entries {
            let start = entry.offset
            guard start + 30 <= centralStart, archive.u32(start) == 0x04034b50 else { throw EPUBError.invalidArchive }
            let dataStart = start + 30 + Int(archive.u16(start + 26)) + Int(archive.u16(start + 28))
            guard dataStart + entry.compressed <= centralStart else { throw EPUBError.invalidArchive }
            let compressed = archive[dataStart..<(dataStart + entry.compressed)]
            let bytes: Data
            switch entry.method {
            case 0:
                guard entry.compressed == entry.expanded else { throw EPUBError.invalidArchive }
                bytes = compressed
            case 8:
                bytes = try inflateRaw(compressed, expandedSize: entry.expanded)
            default:
                throw EPUBError.unsupportedArchive
            }
            let checksum = bytes.withUnsafeBytes { buffer in
                crc32(0, buffer.bindMemory(to: UInt8.self).baseAddress, UInt32(buffer.count))
            }
            guard checksum == entry.crc else { throw EPUBError.invalidArchive }
            let target = directory.appendingPathComponent(entry.path)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: target, options: .atomic)
        }
        let type = try? String(contentsOf: directory.appendingPathComponent("mimetype"), encoding: .utf8)
        guard type?.trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip" else { throw EPUBError.invalidPublication }
    }

    static func safeComponents(_ path: String) -> [String]? {
        guard !path.contains("\\"), !path.contains(":"), !path.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return components
    }

    private static func inflateRaw(_ compressed: Data, expandedSize: Int) throws -> Data {
        let capacity = max(1, expandedSize)
        var output = Data(count: capacity)
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw EPUBError.invalidArchive
        }
        defer { inflateEnd(&stream) }
        let status = compressed.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
                stream.next_in = input.bindMemory(to: UInt8.self).baseAddress.map { UnsafeMutablePointer(mutating: $0) }
                stream.avail_in = UInt32(input.count)
                stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress
                stream.avail_out = UInt32(destination.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.total_out == expandedSize, stream.total_in == compressed.count else {
            throw EPUBError.invalidArchive
        }
        return output.prefix(expandedSize)
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
    }
}
