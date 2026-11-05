//
//  CRXVerifier.swift
//  Alp Browser
//
//  Offline verification of packed Chrome extensions (.crx, format versions 2 and 3).
//  Written from the public CRX format description; no network access is used.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import Security
import CryptoKit

enum CRXVerificationError: LocalizedError {
    case malformed(String)
    case unsupportedVersion(Int)
    case noSignature
    case badSignature
    case keyDoesNotMatchID
    case idMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .malformed(let why):
            return "The extension package is damaged (\(why)) and was not installed."
        case .unsupportedVersion(let v):
            return "The extension package uses an unsupported format (version \(v)) and was not installed."
        case .noSignature:
            return "The extension package carries no usable signature and was not installed."
        case .badSignature:
            return "The extension package signature does not verify, so its contents may have been altered. It was not installed."
        case .keyDoesNotMatchID:
            return "The extension package is not signed by the key its ID is derived from, and was not installed."
        case .idMismatch(let expected, let actual):
            return "The downloaded package is for a different extension (\(actual), expected \(expected)) and was not installed."
        }
    }
}

struct CRXPackage {
    /// 1 for the legacy format (CRX2), otherwise 3.
    let formatVersion: Int
    /// The zip archive that follows the header.
    let zipPayload: Data
    /// Extension ID derived from the signing key (32 letters a–p).
    let extensionID: String
}

enum CRXVerifier {
    private static let magic: [UInt8] = Array("Cr24".utf8)
    /// Header size cap; larger headers are rejected as malformed.
    private static let maxHeaderLength = 1 << 20
    private static let crx3SignedDataPrefix: [UInt8] = Array("CRX3 SignedData".utf8) + [0]
    private static let rsaEncryptionOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    // MARK: - Entry point

    /// Parses the header, verifies every signature over the payload and returns the payload.
    /// Throws `CRXVerificationError` for anything that does not verify.
    /// - Parameter expectedExtensionID: when given, the ID derived from the signing key must equal it.
    static func verify(_ file: Data, expectedExtensionID: String? = nil) throws -> CRXPackage {
        let bytes = [UInt8](file)
        guard bytes.count > 16, Array(bytes[0..<4]) == magic else {
            throw CRXVerificationError.malformed("missing Cr24 header")
        }
        let version = Int(le32(bytes, 4))

        let package: CRXPackage
        switch version {
        case 2: package = try verifyV2(bytes)
        case 3: package = try verifyV3(bytes)
        default: throw CRXVerificationError.unsupportedVersion(version)
        }

        if let expected = expectedExtensionID, expected != package.extensionID {
            throw CRXVerificationError.idMismatch(expected: expected, actual: package.extensionID)
        }
        return package
    }

    /// Extension ID for a DER SubjectPublicKeyInfo: first 16 bytes of its SHA-256, each nibble as a–p.
    static func extensionID(forPublicKey spki: [UInt8]) -> String {
        extensionID(forCRXID: Array(SHA256.hash(data: spki).prefix(16)))
    }

    static func extensionID(forCRXID crxID: [UInt8]) -> String {
        var out = ""
        for byte in crxID {
            out.append(Character(UnicodeScalar(UInt8(ascii: "a") + (byte >> 4))))
            out.append(Character(UnicodeScalar(UInt8(ascii: "a") + (byte & 0x0F))))
        }
        return out
    }

    // MARK: - CRX2

    /// Layout: "Cr24", version=2, keyLength, signatureLength, key (SPKI), signature, zip.
    /// The signature is RSA PKCS#1 v1.5 with SHA-1 over the zip (what the format specifies).
    private static func verifyV2(_ bytes: [UInt8]) throws -> CRXPackage {
        guard bytes.count >= 16 else { throw CRXVerificationError.malformed("short header") }
        let keyLen = Int(le32(bytes, 8))
        let sigLen = Int(le32(bytes, 12))
        guard keyLen > 0, sigLen > 0, keyLen <= maxHeaderLength, sigLen <= maxHeaderLength else {
            throw CRXVerificationError.malformed("bad key or signature length")
        }
        let zipStart = 16 + keyLen + sigLen
        guard zipStart < bytes.count else { throw CRXVerificationError.malformed("no payload") }

        let key = Array(bytes[16..<(16 + keyLen)])
        let signature = Array(bytes[(16 + keyLen)..<zipStart])
        let zip = Data(bytes[zipStart...])

        guard try verifyRSA(key: key, signature: signature, message: zip, algorithm: .rsaSignatureMessagePKCS1v15SHA1) else {
            throw CRXVerificationError.badSignature
        }
        return CRXPackage(formatVersion: 2, zipPayload: zip, extensionID: extensionID(forPublicKey: key))
    }

    // MARK: - CRX3

    /// Layout: "Cr24", version=3, headerLength, CrxFileHeader (protobuf), zip.
    /// CrxFileHeader: repeated rsa proofs (field 2), repeated ecdsa proofs (field 3), and the signed
    /// header data (field 10000) holding the 16-byte crx_id. Each proof is { public_key = 1, signature = 2 }.
    /// Every signature covers: "CRX3 SignedData\0" + LE32(len(signedHeaderData)) + signedHeaderData + zip.
    private static func verifyV3(_ bytes: [UInt8]) throws -> CRXPackage {
        guard bytes.count >= 12 else { throw CRXVerificationError.malformed("short header") }
        let headerLen = Int(le32(bytes, 8))
        guard headerLen > 0, headerLen <= maxHeaderLength, 12 + headerLen < bytes.count else {
            throw CRXVerificationError.malformed("bad header length")
        }
        let header = Array(bytes[12..<(12 + headerLen)])
        let zip = Data(bytes[(12 + headerLen)...])

        let fields = try protoFields(header)
        let signedHeaderBlobs = fields.filter { $0.number == 10000 }
        guard signedHeaderBlobs.count == 1 else { throw CRXVerificationError.malformed("signed header data") }
        let signedHeaderData = signedHeaderBlobs[0].bytes

        let signedFields = try protoFields(signedHeaderData)
        guard let crxID = signedFields.first(where: { $0.number == 1 })?.bytes, crxID.count == 16 else {
            throw CRXVerificationError.malformed("crx_id")
        }

        var signedData = Data(crx3SignedDataPrefix)
        var length = UInt32(signedHeaderData.count).littleEndian
        withUnsafeBytes(of: &length) { signedData.append(contentsOf: $0) }
        signedData.append(contentsOf: signedHeaderData)
        signedData.append(zip)

        var proofCount = 0
        var idKeyVerified = false

        for field in fields where field.number == 2 || field.number == 3 {
            let proof = try protoFields(field.bytes)
            guard let key = proof.first(where: { $0.number == 1 })?.bytes,
                  let signature = proof.first(where: { $0.number == 2 })?.bytes,
                  !key.isEmpty, !signature.isEmpty else {
                throw CRXVerificationError.malformed("incomplete signature proof")
            }
            let valid: Bool
            if field.number == 2 {
                valid = try verifyRSA(key: key, signature: signature, message: signedData, algorithm: .rsaSignatureMessagePKCS1v15SHA256)
            } else {
                valid = verifyECDSA(key: key, signature: signature, message: signedData)
            }
            // One bad proof invalidates the file, even if another proof is good.
            guard valid else { throw CRXVerificationError.badSignature }
            proofCount += 1
            if Array(SHA256.hash(data: key).prefix(16)) == crxID { idKeyVerified = true }
        }

        guard proofCount > 0 else { throw CRXVerificationError.noSignature }
        // The key the extension ID is derived from must be among the verified signers.
        guard idKeyVerified else { throw CRXVerificationError.keyDoesNotMatchID }
        return CRXPackage(formatVersion: 3, zipPayload: zip, extensionID: extensionID(forCRXID: crxID))
    }

    // MARK: - Signature checks

    private static func verifyRSA(key spki: [UInt8], signature: [UInt8], message: Data,
                                  algorithm: SecKeyAlgorithm) throws -> Bool {
        guard let parsed = parseSPKI(spki), parsed.oid == rsaEncryptionOID else {
            throw CRXVerificationError.malformed("unsupported RSA key encoding")
        }
        // SecKey wants the bare PKCS#1 RSAPublicKey, which is the SPKI BIT STRING content.
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(Data(parsed.keyBits) as CFData, attributes as CFDictionary, &error) else {
            throw CRXVerificationError.malformed("unreadable RSA key")
        }
        // Refuse keys too small to mean anything.
        guard SecKeyGetBlockSize(secKey) * 8 >= 1024 else {
            throw CRXVerificationError.malformed("RSA key too small")
        }
        guard SecKeyIsAlgorithmSupported(secKey, .verify, algorithm) else { return false }
        let ok = SecKeyVerifySignature(secKey, algorithm, message as CFData, Data(signature) as CFData, &error)
        error?.release()
        return ok
    }

    private static func verifyECDSA(key spki: [UInt8], signature: [UInt8], message: Data) -> Bool {
        guard let publicKey = try? P256.Signing.PublicKey(derRepresentation: Data(spki)),
              let ecdsa = try? P256.Signing.ECDSASignature(derRepresentation: Data(signature)) else {
            return false
        }
        return publicKey.isValidSignature(ecdsa, for: message)
    }

    // MARK: - Minimal DER (SubjectPublicKeyInfo only)

    /// SubjectPublicKeyInfo ::= SEQUENCE { SEQUENCE { OID, ... }, BIT STRING }
    /// Returns the algorithm OID bytes and the BIT STRING content (without the unused-bits byte).
    static func parseSPKI(_ der: [UInt8]) -> (oid: [UInt8], keyBits: [UInt8])? {
        var pos = 0
        guard let outer = derElement(der, &pos), outer.tag == 0x30, pos == der.count else { return nil }
        var inner = outer.content.lowerBound
        guard let algorithm = derElement(der, &inner), algorithm.tag == 0x30 else { return nil }
        var algPos = algorithm.content.lowerBound
        guard let oid = derElement(der, &algPos), oid.tag == 0x06 else { return nil }
        guard let bits = derElement(der, &inner), bits.tag == 0x03, inner == outer.content.upperBound,
              bits.content.count > 1, der[bits.content.lowerBound] == 0 else { return nil }
        return (Array(der[oid.content]), Array(der[(bits.content.lowerBound + 1)..<bits.content.upperBound]))
    }

    /// Reads one TLV at `pos` and advances `pos` past it. Definite lengths up to 4 bytes only.
    private static func derElement(_ b: [UInt8], _ pos: inout Int) -> (tag: UInt8, content: Range<Int>)? {
        guard pos + 2 <= b.count else { return nil }
        let tag = b[pos]
        var cursor = pos + 1
        var length = Int(b[cursor])
        cursor += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count >= 1, count <= 4, cursor + count <= b.count else { return nil }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(b[cursor])
                cursor += 1
            }
        }
        guard length >= 0, cursor + length <= b.count else { return nil }
        pos = cursor + length
        return (tag, cursor..<(cursor + length))
    }

    // MARK: - Minimal protobuf reader (length-delimited fields only)

    private struct ProtoField {
        let number: Int
        let bytes: [UInt8]
    }

    /// Returns the length-delimited fields in order; varint and fixed-width fields are skipped.
    private static func protoFields(_ b: [UInt8]) throws -> [ProtoField] {
        var fields: [ProtoField] = []
        var pos = 0

        func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while pos < b.count, shift < 64 {
                let byte = b[pos]
                pos += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            throw CRXVerificationError.malformed("bad varint")
        }

        while pos < b.count {
            let key = try readVarint()
            let number = Int(truncatingIfNeeded: key >> 3)
            switch key & 7 {
            case 0:
                _ = try readVarint()
            case 1:
                guard pos + 8 <= b.count else { throw CRXVerificationError.malformed("truncated field") }
                pos += 8
            case 2:
                let length = try readVarint()
                guard length <= UInt64(b.count - pos) else { throw CRXVerificationError.malformed("truncated field") }
                fields.append(ProtoField(number: number, bytes: Array(b[pos..<(pos + Int(length))])))
                pos += Int(length)
            case 5:
                guard pos + 4 <= b.count else { throw CRXVerificationError.malformed("truncated field") }
                pos += 4
            default:
                throw CRXVerificationError.malformed("unsupported field encoding")
            }
        }
        return fields
    }

    // MARK: - Helpers

    private static func le32(_ b: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(b[offset]) | UInt32(b[offset + 1]) << 8 | UInt32(b[offset + 2]) << 16 | UInt32(b[offset + 3]) << 24
    }
}
