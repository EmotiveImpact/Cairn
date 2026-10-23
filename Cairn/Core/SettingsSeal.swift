import CryptoKit
import Foundation
import Security

/// Settings that let Cairn do more on its own can only be switched on in Cairn.
///
/// Each one is saved with a seal made from a secret that only Cairn can read
/// from the login Keychain. Another program, or an AI tool told to run
/// `defaults write`, can change the saved value but cannot make a matching
/// seal, so Cairn treats the change as if the setting were off.
enum SettingsSeal {
    private static let lock = NSLock()
    private static var cached: SymmetricKey?
    private static let account = "settings-seal"

    /// Read once, or made on first use. Never shows a Keychain prompt; when the
    /// Keychain is locked or unavailable there is no key and nothing is sealed.
    static func key() -> SymmetricKey? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        do {
            if let stored = try LicenseKeychain.read(account, as: Data.self) {
                cached = SymmetricKey(data: stored)
                return cached
            }
            let fresh = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            do { try LicenseKeychain.write(account, value: fresh, onlyIfAbsent: true) }
            catch LicenseStorageError.keychain(let status) where status == errSecDuplicateItem {
                guard let stored = try LicenseKeychain.read(account, as: Data.self) else { return nil }
                cached = SymmetricKey(data: stored)
                return cached
            }
            cached = SymmetricKey(data: fresh)
            return cached
        } catch {
            return nil
        }
    }

    static func seal(_ value: String, for name: String) -> String? {
        guard let key = key() else { return nil }
        return Data(HMAC<SHA256>.authenticationCode(for: Data("\(name)=\(value)".utf8), using: key)).base64EncodedString()
    }

    static func isSealed(_ value: String, for name: String, seal: String?) -> Bool {
        guard let seal, let mac = Data(base64Encoded: seal), let key = key() else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data("\(name)=\(value)".utf8), using: key)
    }
}
