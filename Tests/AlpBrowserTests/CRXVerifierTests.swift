import XCTest
import CryptoKit
import Security
@testable import AlpBrowser

// Builds signed CRX files in memory with freshly generated keys. No network, no files.

final class CRXVerifierTests: XCTestCase {
    private let zip: [UInt8] = Array("PK-fake-zip-payload".utf8) + Array(repeating: 7, count: 64)

    // MARK: - Builders

    private func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }

    private func varint(_ value: Int) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    private func field(_ number: Int, _ bytes: [UInt8]) -> [UInt8] {
        varint(number << 3 | 2) + varint(bytes.count) + bytes
    }

    private func der(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        var length: [UInt8]
        if content.count < 0x80 {
            length = [UInt8(content.count)]
        } else {
            length = [0x82, UInt8(content.count >> 8), UInt8(content.count & 0xFF)]
        }
        return [tag] + length + content
    }

    private func signedData(signedHeaderData: [UInt8], zip: [UInt8]) -> Data {
        Data(Array("CRX3 SignedData".utf8) + [0] + le32(signedHeaderData.count) + signedHeaderData + zip)
    }

    private struct ECSigner {
        let key = P256.Signing.PrivateKey()
        var spki: [UInt8] { Array(key.publicKey.derRepresentation) }
        var crxID: [UInt8] { Array(SHA256.hash(data: spki).prefix(16)) }
    }

    /// Builds a CRX3. `crxID` and `proofs` default to a single valid proof by `signer`.
    private func makeCRX3(zip: [UInt8], signer: ECSigner, crxIDOverride: [UInt8]? = nil,
                          includeProof: Bool = true, signedPayload: [UInt8]? = nil) -> Data {
        let crxID = crxIDOverride ?? signer.crxID
        let signedHeaderData = field(1, crxID)
        let toSign = signedData(signedHeaderData: signedHeaderData, zip: signedPayload ?? zip)
        let signature = Array((try! signer.key.signature(for: toSign)).derRepresentation)
        var header: [UInt8] = []
        if includeProof {
            header += field(3, field(1, signer.spki) + field(2, signature))
        }
        header += field(10000, signedHeaderData)
        return Data(Array("Cr24".utf8) + le32(3) + le32(header.count) + header + zip)
    }

    private func makeRSA() -> (priv: SecKey, spki: [UInt8]) {
        let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        let priv = SecKeyCreateRandomKey(attrs as CFDictionary, nil)!
        let pub = SecKeyCopyPublicKey(priv)!
        let pkcs1 = [UInt8](SecKeyCopyExternalRepresentation(pub, nil)! as Data)
        let oid: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        let algorithm = der(0x30, oid + [0x05, 0x00])
        return (priv, der(0x30, algorithm + der(0x03, [0x00] + pkcs1)))
    }

    private func rsaSign(_ priv: SecKey, _ algorithm: SecKeyAlgorithm, _ message: Data) -> [UInt8] {
        [UInt8](SecKeyCreateSignature(priv, algorithm, message as CFData, nil)! as Data)
    }

    private func makeCRX2(zip: [UInt8], rsa: (priv: SecKey, spki: [UInt8]), signedPayload: [UInt8]? = nil) -> Data {
        let sig = rsaSign(rsa.priv, .rsaSignatureMessagePKCS1v15SHA1, Data(signedPayload ?? zip))
        return Data(Array("Cr24".utf8) + le32(2) + le32(rsa.spki.count) + le32(sig.count) + rsa.spki + sig + zip)
    }

    private func assertThrows(_ data: Data, expectedID: String? = nil, _ matches: (CRXVerificationError) -> Bool,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try CRXVerifier.verify(data, expectedExtensionID: expectedID), file: file, line: line) { error in
            guard let crxError = error as? CRXVerificationError else {
                return XCTFail("unexpected error \(error)", file: file, line: line)
            }
            XCTAssertTrue(matches(crxError), "wrong error: \(crxError)", file: file, line: line)
        }
    }

    // MARK: - CRX3

    func testValidCRX3Verifies() throws {
        let signer = ECSigner()
        let id = CRXVerifier.extensionID(forPublicKey: signer.spki)
        let package = try CRXVerifier.verify(makeCRX3(zip: zip, signer: signer), expectedExtensionID: id)
        XCTAssertEqual(package.formatVersion, 3)
        XCTAssertEqual(package.extensionID, id)
        XCTAssertEqual([UInt8](package.zipPayload), zip)
        XCTAssertEqual(id.count, 32)
        XCTAssertTrue(id.allSatisfy { ("a"..."p").contains($0) })
    }

    func testTamperedPayloadIsRejected() {
        let signer = ECSigner()
        var tampered = zip
        tampered[0] ^= 0xFF
        assertThrows(makeCRX3(zip: tampered, signer: signer, signedPayload: zip)) {
            if case .badSignature = $0 { return true } else { return false }
        }
    }

    func testWrongExpectedIDIsRejected() {
        let signer = ECSigner()
        let other = CRXVerifier.extensionID(forPublicKey: ECSigner().spki)
        assertThrows(makeCRX3(zip: zip, signer: signer), expectedID: other) {
            if case .idMismatch = $0 { return true } else { return false }
        }
    }

    func testSignerThatIsNotTheIDKeyIsRejected() {
        // Valid signature, but the crx_id names a different key than the one that signed.
        let signer = ECSigner()
        let foreignID = ECSigner().crxID
        assertThrows(makeCRX3(zip: zip, signer: signer, crxIDOverride: foreignID)) {
            if case .keyDoesNotMatchID = $0 { return true } else { return false }
        }
    }

    func testMissingProofsAreRejected() {
        assertThrows(makeCRX3(zip: zip, signer: ECSigner(), includeProof: false)) {
            if case .noSignature = $0 { return true } else { return false }
        }
    }

    func testBadMagicAndVersionAreRejected() {
        var data = [UInt8](makeCRX3(zip: zip, signer: ECSigner()))
        var badMagic = data
        badMagic[0] = 0x00
        assertThrows(Data(badMagic)) { if case .malformed = $0 { return true } else { return false } }

        data[4] = 9
        assertThrows(Data(data)) { if case .unsupportedVersion(9) = $0 { return true } else { return false } }
    }

    func testTruncatedAndOversizedHeadersAreRejected() {
        let full = [UInt8](makeCRX3(zip: zip, signer: ECSigner()))
        assertThrows(Data(full.prefix(20))) { if case .malformed = $0 { return true } else { return false } }

        var huge = full
        huge.replaceSubrange(8..<12, with: le32(0x7FFF_FFFF))
        assertThrows(Data(huge)) { if case .malformed = $0 { return true } else { return false } }
    }

    func testCorruptedSignatureByteIsRejected() {
        var data = [UInt8](makeCRX3(zip: zip, signer: ECSigner()))
        // Flip a byte inside the header (the signature is near its end, before the signed header data).
        let headerLen = Int(data[8]) | Int(data[9]) << 8
        data[12 + headerLen - 40] ^= 0x01
        XCTAssertThrowsError(try CRXVerifier.verify(Data(data)))
    }

    func testRSAProofInCRX3Verifies() throws {
        let rsa = makeRSA()
        let crxID = Array(SHA256.hash(data: rsa.spki).prefix(16))
        let signedHeaderData = field(1, crxID)
        let sig = rsaSign(rsa.priv, .rsaSignatureMessagePKCS1v15SHA256, signedData(signedHeaderData: signedHeaderData, zip: zip))
        let header = field(2, field(1, rsa.spki) + field(2, sig)) + field(10000, signedHeaderData)
        let file = Data(Array("Cr24".utf8) + le32(3) + le32(header.count) + header + zip)

        let package = try CRXVerifier.verify(file, expectedExtensionID: CRXVerifier.extensionID(forPublicKey: rsa.spki))
        XCTAssertEqual([UInt8](package.zipPayload), zip)
    }

    // MARK: - CRX2

    func testValidCRX2Verifies() throws {
        let rsa = makeRSA()
        let package = try CRXVerifier.verify(makeCRX2(zip: zip, rsa: rsa))
        XCTAssertEqual(package.formatVersion, 2)
        XCTAssertEqual(package.extensionID, CRXVerifier.extensionID(forPublicKey: rsa.spki))
        XCTAssertEqual([UInt8](package.zipPayload), zip)
    }

    func testTamperedCRX2IsRejected() {
        let rsa = makeRSA()
        var tampered = zip
        tampered[3] ^= 0x55
        assertThrows(makeCRX2(zip: tampered, rsa: rsa, signedPayload: zip)) {
            if case .badSignature = $0 { return true } else { return false }
        }
    }

    // MARK: - DER

    func testSPKIParsingRejectsTrailingGarbageAndWrongShape() {
        let rsa = makeRSA()
        XCTAssertNotNil(CRXVerifier.parseSPKI(rsa.spki))
        XCTAssertNil(CRXVerifier.parseSPKI(rsa.spki + [0x00]))
        XCTAssertNil(CRXVerifier.parseSPKI([0x30, 0x00]))
        XCTAssertNil(CRXVerifier.parseSPKI([]))
    }
}
