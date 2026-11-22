import XCTest
import CryptoKit
import IDEStudioShared

final class AddonSignatureTests: XCTestCase {
    var folder: URL!
    let key = Curve25519.Signing.PrivateKey()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("sigtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("{\"id\":\"com.example.test\"}".utf8).write(to: folder.appendingPathComponent("addon.json"))
        try Data("program".utf8).write(to: folder.appendingPathComponent("bin/tool"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    func signed() throws -> AddonSignature {
        let signature = try AddonSignature.sign(folder: folder, addon: "com.example.test", version: "1.0.0", with: key)
        try signature.write(into: folder)
        return signature
    }

    func testUnsignedFolder() throws {
        XCTAssertEqual(try AddonSignature.check(folder: folder), .unsigned)
    }

    func testValidSignatureNamesItsKey() throws {
        let signature = try signed()
        XCTAssertEqual(signature.files.keys.sorted(), ["addon.json", "bin/tool"])
        guard case .valid(let found) = try AddonSignature.check(folder: folder) else { return XCTFail("not valid") }
        XCTAssertEqual(found.key, key.publicKey.rawRepresentation.base64EncodedString())
        XCTAssertEqual(found.version, "1.0.0")
    }

    func testFinderFilesAreIgnored() throws {
        _ = try signed()
        try Data().write(to: folder.appendingPathComponent(".DS_Store"))
        try Data().write(to: folder.appendingPathComponent("bin/.DS_Store"))
        XCTAssertNoThrow(try AddonSignature.check(folder: folder))
    }

    func testChangedFileIsCaught() throws {
        _ = try signed()
        try Data("other program".utf8).write(to: folder.appendingPathComponent("bin/tool"))
        XCTAssertThrowsError(try AddonSignature.check(folder: folder)) { error in
            XCTAssertTrue((error as? AddonSignature.Failure)?.reason.contains("changed") == true, "\(error)")
        }
    }

    func testAddedAndMissingFilesAreCaught() throws {
        _ = try signed()
        try Data("x".utf8).write(to: folder.appendingPathComponent("bin/extra"))
        XCTAssertThrowsError(try AddonSignature.check(folder: folder))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("bin/extra"))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("bin/tool"))
        XCTAssertThrowsError(try AddonSignature.check(folder: folder))
    }

    func testEditedSignatureIsCaught() throws {
        var signature = try signed()
        signature.version = "9.9.9"
        try signature.write(into: folder)
        XCTAssertThrowsError(try AddonSignature.check(folder: folder))
        // A signature from another key over the same files, passed off under the first key, fails too.
        var forged = try AddonSignature.sign(folder: folder, addon: "com.example.test", version: "1.0.0", with: Curve25519.Signing.PrivateKey())
        forged.key = key.publicKey.rawRepresentation.base64EncodedString()
        try forged.write(into: folder)
        XCTAssertThrowsError(try AddonSignature.check(folder: folder))
    }

    func testFingerprintIsShortAndStable() {
        let k = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(AddonSignature.fingerprint(ofKey: k), AddonSignature.fingerprint(ofKey: k))
        XCTAssertEqual(AddonSignature.fingerprint(ofKey: k).count, 19)
    }
}
