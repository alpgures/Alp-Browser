import Foundation

/// Why an archive was refused before extraction.
enum ZipScanError: LocalizedError, Equatable {
    case malformed(String)
    case unsupported(String)
    case unsafeEntry(name: String, reason: String)
    case limitExceeded(String)

    var errorDescription: String? {
        switch self {
        case .malformed(let why): return "The extension archive is damaged (\(why))."
        case .unsupported(let why): return "The extension archive uses an unsupported feature (\(why))."
        case .unsafeEntry(let name, let reason): return "The extension archive was refused: \"\(name)\" \(reason)."
        case .limitExceeded(let why): return "The extension archive was refused (\(why))."
        }
    }
}

/// Reads a zip's central directory in memory, without extracting anything, and refuses archives
/// that could write outside the destination folder ("zip slip").
///
/// Refused: absolute paths, any `..` component (either slash style), NUL bytes, drive-letter
/// paths, symlinks and other special files, encrypted entries, and archives whose local headers
/// disagree with the central directory (a tool could otherwise extract names the scan never saw).
/// Zip64 archives are refused (fail closed); extensions are far below the 4 GiB / 65,535-entry limits.
enum ZipArchiveScanner {
    static let maxEntries = 20_000
    static let maxTotalUncompressedBytes: UInt64 = 512 * 1024 * 1024

    struct Entry: Equatable {
        let name: String
        let isDirectory: Bool
    }

    /// Returns the validated entries, or throws `ZipScanError`.
    @discardableResult
    static func scan(_ zip: Data) throws -> [Entry] {
        let bytes = [UInt8](zip)
        guard bytes.count >= 22 else { throw ZipScanError.malformed("too short") }

        // End of central directory: signature 0x06054b50, searched backwards over the max comment length.
        let searchStart = max(0, bytes.count - 22 - 65_535)
        var eocd = -1
        var i = bytes.count - 22
        while i >= searchStart {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4b, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                let commentLen = Int(u16(bytes, i + 20))
                if i + 22 + commentLen == bytes.count { eocd = i; break }
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipScanError.malformed("no end-of-directory record") }

        let diskNumber = u16(bytes, eocd + 4)
        let cdDisk = u16(bytes, eocd + 6)
        let entriesOnDisk = u16(bytes, eocd + 8)
        let totalEntries = u16(bytes, eocd + 10)
        let cdSize = u32(bytes, eocd + 12)
        let cdOffset = u32(bytes, eocd + 16)

        guard diskNumber == 0, cdDisk == 0, entriesOnDisk == totalEntries else {
            throw ZipScanError.unsupported("multi-part archive")
        }
        if totalEntries == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            throw ZipScanError.unsupported("Zip64")
        }
        guard Int(totalEntries) <= maxEntries else { throw ZipScanError.limitExceeded("too many files") }
        guard Int(cdOffset) + Int(cdSize) <= eocd else { throw ZipScanError.malformed("directory out of range") }

        var entries: [Entry] = []
        var pos = Int(cdOffset)
        var totalUncompressed: UInt64 = 0

        for _ in 0..<Int(totalEntries) {
            guard pos + 46 <= bytes.count,
                  bytes[pos] == 0x50, bytes[pos + 1] == 0x4b, bytes[pos + 2] == 0x01, bytes[pos + 3] == 0x02 else {
                throw ZipScanError.malformed("bad directory entry")
            }
            let madeBy = u16(bytes, pos + 4)
            let flags = u16(bytes, pos + 8)
            let uncompressed = u32(bytes, pos + 24)
            let nameLen = Int(u16(bytes, pos + 28))
            let extraLen = Int(u16(bytes, pos + 30))
            let commentLen = Int(u16(bytes, pos + 32))
            let externalAttrs = u32(bytes, pos + 38)
            let localOffset = u32(bytes, pos + 42)
            let nameStart = pos + 46
            guard nameStart + nameLen + extraLen + commentLen <= bytes.count else {
                throw ZipScanError.malformed("directory entry out of range")
            }
            let nameBytes = Array(bytes[nameStart..<nameStart + nameLen])
            guard let name = String(bytes: nameBytes, encoding: .utf8) else {
                throw ZipScanError.malformed("file name is not valid UTF-8")
            }

            if flags & 0x1 != 0 { throw ZipScanError.unsafeEntry(name: name, reason: "is encrypted") }
            if let reason = unsafeReason(for: name) { throw ZipScanError.unsafeEntry(name: name, reason: reason) }

            // Host system 3 = Unix: the high 16 bits of the external attributes are st_mode.
            if madeBy >> 8 == 3 {
                let fileType = (externalAttrs >> 16) & 0xF000
                if fileType != 0, fileType != 0x8000, fileType != 0x4000 {
                    throw ZipScanError.unsafeEntry(name: name, reason: "is a link or special file")
                }
            }

            // The local header must carry the same name, or the extractor could see different paths.
            let local = Int(localOffset)
            guard local + 30 <= Int(cdOffset),
                  bytes[local] == 0x50, bytes[local + 1] == 0x4b, bytes[local + 2] == 0x03, bytes[local + 3] == 0x04 else {
                throw ZipScanError.malformed("bad local header")
            }
            let localNameLen = Int(u16(bytes, local + 26))
            guard local + 30 + localNameLen <= bytes.count,
                  Array(bytes[local + 30..<local + 30 + localNameLen]) == nameBytes else {
                throw ZipScanError.malformed("local header name differs from directory")
            }

            totalUncompressed += UInt64(uncompressed)
            if totalUncompressed > maxTotalUncompressedBytes { throw ZipScanError.limitExceeded("unpacks to more than 512 MB") }

            entries.append(Entry(name: name, isDirectory: name.hasSuffix("/")))
            pos = nameStart + nameLen + extraLen + commentLen
        }
        guard pos <= eocd else { throw ZipScanError.malformed("directory overruns its record") }
        return entries
    }

    /// Reason an entry name could escape the destination, or nil if it is fine.
    static func unsafeReason(for name: String) -> String? {
        if name.isEmpty { return "has an empty name" }
        if name.contains("\0") { return "contains a NUL byte" }
        if name.hasPrefix("/") || name.hasPrefix("\\") { return "is an absolute path" }
        let scalars = Array(name.unicodeScalars)
        if scalars.count >= 2, scalars[1] == ":", scalars[0].properties.isAlphabetic, scalars[0].isASCII {
            return "is a drive-letter path"
        }
        // Either slash style counts as a separator, so "a\\..\\b" is caught too.
        let parts = name.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        if parts.contains("..") { return "contains a \"..\" path component" }
        return nil
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        let lo = UInt16(b[o])
        let hi = UInt16(b[o + 1]) << 8
        return lo | hi
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        let b0 = UInt32(b[o])
        let b1 = UInt32(b[o + 1]) << 8
        let b2 = UInt32(b[o + 2]) << 16
        let b3 = UInt32(b[o + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    /// After extraction: every item must be a regular file or folder that really lives under `root`.
    /// Catches anything the pre-scan could not predict (for example a link created by the extractor).
    static func verifyExtractedTree(at root: URL) throws {
        let fm = FileManager.default
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey], options: []) else {
            throw ZipScanError.malformed("could not read the unpacked folder")
        }
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            if values.isSymbolicLink == true {
                throw ZipScanError.unsafeEntry(name: url.lastPathComponent, reason: "was unpacked as a symbolic link")
            }
            guard values.isRegularFile == true || values.isDirectory == true else {
                throw ZipScanError.unsafeEntry(name: url.lastPathComponent, reason: "was unpacked as a special file")
            }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else {
                throw ZipScanError.unsafeEntry(name: url.lastPathComponent, reason: "was unpacked outside the destination")
            }
        }
    }
}
