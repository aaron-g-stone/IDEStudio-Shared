import Foundation
import CryptoKit

/// The signature of an IDE Studio add-on: `signature.json` at the add-on's top, holding the SHA-256 of
/// every other file and an Ed25519 signature over them, the add-on's id and its version.
///
/// The signer (the add-on's release tool) and IDE Studio both build the signed message here, so they
/// cannot drift apart. Signing itself needs the private key and happens only in the release tool.
public struct AddonSignature: Codable, Equatable {
    public static let fileName = "signature.json"

    public var format: Int
    public var addon: String
    public var version: String
    /// The Ed25519 public key that signed, base64 of its 32 raw bytes.
    public var key: String
    /// Every file of the add-on but this one, by path inside it ("bin/splunk-studio"), as SHA-256 in hex.
    public var files: [String: String]
    /// The Ed25519 signature over `message`, base64.
    public var signature: String

    public init(format: Int = 1, addon: String, version: String, key: String, files: [String: String], signature: String) {
        self.format = format; self.addon = addon; self.version = version; self.key = key; self.files = files; self.signature = signature
    }

    /// Why a signature does not hold.
    public struct Failure: Error, LocalizedError, Equatable {
        public var reason: String
        public init(_ reason: String) { self.reason = reason }
        public var errorDescription: String? { reason }
    }

    /// What a folder's signature says.
    public enum Check: Equatable {
        /// There is no signature.json.
        case unsigned
        /// The signature holds: these are the files that were signed, by this key.
        case valid(AddonSignature)
    }

    // MARK: The signed message

    /// Paths in byte order, so every Mac sorts them alike.
    static func sortedPaths(_ files: [String: String]) -> [String] {
        files.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    /// The exact bytes that are signed.
    public static func message(addon: String, version: String, files: [String: String]) -> Data {
        var text = "IDE Studio add-on signature 1\naddon \(addon)\nversion \(version)\n"
        for path in sortedPaths(files) { text += "\(files[path]!)  \(path)\n" }
        return Data(text.utf8)
    }

    /// Files that are never part of an add-on: the Finder's and Python's own side files.
    static func isIgnored(_ name: String) -> Bool { name == ".DS_Store" || name == "__pycache__" }

    /// The SHA-256 of every file in a folder but signature.json, by path inside it. A symbolic link
    /// counts as its destination's path, not the file it points to.
    public static func digests(of folder: URL) throws -> [String: String] {
        let base = folder.resolvingSymlinksInPath().standardizedFileURL
        // The path-based walker gives each file's path inside the folder directly ("bin/tool").
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw Failure("The add-on's folder could not be read.")
        }
        var out: [String: String] = [:]
        while let path = walker.nextObject() as? String {
            let type = walker.fileAttributes?[.type] as? FileAttributeType
            if isIgnored((path as NSString).lastPathComponent) {
                if type == .typeDirectory { walker.skipDescendants() }
                continue
            }
            guard !path.contains("\n") else { throw Failure("A file name in the add-on has a line break in it.") }
            if path == fileName { continue }
            let url = base.appendingPathComponent(path)
            if type == .typeSymbolicLink {
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                out[path] = hex(SHA256.hash(data: Data("symlink\0\(destination)".utf8)))
            } else if type == .typeRegular {
                out[path] = hex(SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)))
            }
        }
        return out
    }

    static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Signing and checking

    /// Signs a folder as it is now. The caller writes the result as `signature.json` in it.
    public static func sign(folder: URL, addon: String, version: String, with key: Curve25519.Signing.PrivateKey) throws -> AddonSignature {
        let files = try digests(of: folder)
        let signed = try key.signature(for: message(addon: addon, version: version, files: files))
        return AddonSignature(addon: addon, version: version, key: key.publicKey.rawRepresentation.base64EncodedString(),
                              files: files, signature: signed.base64EncodedString())
    }

    /// Writes the signature into the folder.
    public func write(into folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }

    /// Checks a folder's signature: that it is well formed, made by the key it names, and that the
    /// folder holds exactly the files that were signed, unchanged. Throws when any of that fails.
    public static func check(folder: URL) throws -> Check {
        let file = folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return .unsigned }
        guard let signature = try? JSONDecoder().decode(AddonSignature.self, from: Data(contentsOf: file)) else {
            throw Failure("Its signature.json could not be read.")
        }
        guard signature.format == 1 else { throw Failure("Its signature is of a kind this IDE Studio does not know (format \(signature.format)).") }
        guard let keyData = Data(base64Encoded: signature.key), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signed = Data(base64Encoded: signature.signature) else {
            throw Failure("Its signature is damaged.")
        }
        guard key.isValidSignature(signed, for: message(addon: signature.addon, version: signature.version, files: signature.files)) else {
            throw Failure("Its signature does not match what it says was signed.")
        }
        let actual = try digests(of: folder)
        let changed = sortedPaths(signature.files).filter { actual[$0] != nil && actual[$0] != signature.files[$0] }
        let missing = sortedPaths(signature.files).filter { actual[$0] == nil }
        let added = sortedPaths(actual).filter { signature.files[$0] == nil }
        if !changed.isEmpty { throw Failure("Files were changed after it was signed: \(changed.joined(separator: ", ")).") }
        if !missing.isEmpty { throw Failure("Signed files are missing: \(missing.joined(separator: ", ")).") }
        if !added.isEmpty { throw Failure("Files were added after it was signed: \(added.joined(separator: ", ")).") }
        return .valid(signature)
    }

    /// A short, readable name for a key: the first 8 bytes of its SHA-256, in hex groups ("3fa1 09bc 77d2 e104").
    public static func fingerprint(ofKey base64: String) -> String {
        let digest = hex(SHA256.hash(data: Data(base64Encoded: base64) ?? Data(base64.utf8)))
        return stride(from: 0, to: 16, by: 4).map { i in
            String(digest[digest.index(digest.startIndex, offsetBy: i)..<digest.index(digest.startIndex, offsetBy: i + 4)])
        }.joined(separator: " ")
    }
}
