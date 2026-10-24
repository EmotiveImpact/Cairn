import Foundation
import CryptoKit

/// New cache folders to look in, published between versions of Cairn as a
/// signed list. Updates stay off until Cairn ships with the publisher's public
/// key. A rule can only point Cairn at a cache folder: it cannot delete, cannot
/// name anything that isn't a cache, and SafePaths still checks every item
/// before anything moves. Items always go to the Bin after review.
enum RuleUpdates {
    struct Spot: Codable, Equatable, Sendable {
        /// Stable id, e.g. "example.app.cache".
        let id: String
        let title: String
        /// Inside the home folder, e.g. "Library/Application Support/Example/Cache".
        let path: String
        let note: String
    }

    struct Book: Codable, Equatable, Sendable {
        let version: Int
        let spots: [Spot]
    }

    enum Outcome: Equatable, Sendable {
        case off
        case upToDate(Int)
        case updated(Int, spots: Int)
        case failed(String)
    }

    /// The publisher's Ed25519 public key, base64. Nil keeps updates off.
    static let publicKey: String? = nil
    /// The list and its detached signature (the same address plus ".sig").
    static let feed = URL(string: "https://getcairn.app/rules/v1/rules.json")!
    static var enabled: Bool { publicKey != nil }
    /// Built-in rules are version 0; anything installed must be newer.
    static let builtInVersion = 0
    static let maxSpots = 500

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cairn", isDirectory: true)
    }
    private static var bookURL: URL { folder.appendingPathComponent("rules.json") }
    private static var signatureURL: URL { folder.appendingPathComponent("rules.json.sig") }

    // MARK: Checking a list

    /// True when `signature` is the publisher's signature of exactly `data`.
    static func verify(_ data: Data, signature: Data, key: String? = publicKey) -> Bool {
        guard let key, let raw = Data(base64Encoded: key),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return publicKey.isValidSignature(signature, for: data)
    }

    /// A rule may name a cache folder inside the home folder and nothing else:
    /// no absolute paths, no "..", and the folder itself must be called a cache
    /// unless it sits inside ~/Library/Caches or ~/.cache.
    static func allowed(_ spot: Spot) -> Bool {
        let path = spot.path
        guard !path.isEmpty, path.count < 300, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains("//"), !path.contains("\n"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return false }
        // Never a whole cache root or a whole app's folder: one app's cache only.
        if parts[0] == "Library" {
            let perApp: Set<String> = ["Application Support", "Containers", "Group Containers"]
            guard parts.count >= (perApp.contains(parts[1]) ? 4 : 3) else { return false }
        }
        let insideCacheRoot = (parts[0] == "Library" && parts[1] == "Caches" && parts.count >= 3) || (parts[0] == ".cache")
        guard insideCacheRoot || parts.last!.lowercased().contains("cache") else { return false }
        let url = FileScan.home.appendingPathComponent(path)
        return SafePaths.evaluate(url, allowedRoots: [FileScan.home], rebuildable: true).isAllowed
    }

    /// The list, if it is signed by the publisher, with any rule that breaks
    /// the limits above dropped.
    static func book(_ data: Data, signature: Data, key: String? = publicKey) -> Book? {
        guard verify(data, signature: signature, key: key),
              let book = try? JSONDecoder().decode(Book.self, from: data) else { return nil }
        return Book(version: book.version, spots: Array(book.spots.filter(allowed).prefix(maxSpots)))
    }

    // MARK: Installed list

    /// The installed list, checked again on every read so an edited file is ignored.
    static func installed() -> Book? {
        guard enabled, let data = try? Data(contentsOf: bookURL),
              let signature = try? Data(contentsOf: signatureURL) else { return nil }
        return book(data, signature: signature)
    }

    static var installedVersion: Int { installed()?.version ?? builtInVersion }

    /// Fetch the published list and install it when it is signed and newer.
    static func check() async -> Outcome {
        guard enabled else { return .off }
        do {
            let (data, response) = try await URLSession.shared.data(from: feed)
            let (signature, signed) = try await URLSession.shared.data(from: feed.appendingPathExtension("sig"))
            guard (response as? HTTPURLResponse)?.statusCode == 200, (signed as? HTTPURLResponse)?.statusCode == 200 else {
                return .failed("The rules list could not be reached.")
            }
            guard let book = book(data, signature: signature) else {
                return .failed("The rules list was not signed by Cairn, so it was ignored.")
            }
            let current = installedVersion
            guard book.version > current else { return .upToDate(current) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: bookURL, options: .atomic)
            try signature.write(to: signatureURL, options: .atomic)
            return .updated(book.version, spots: book.spots.count)
        } catch {
            return .failed("The rules list could not be reached.")
        }
    }
}
