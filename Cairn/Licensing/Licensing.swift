import CryptoKit
import Foundation
import IOKit
import Security
import LocalAuthentication
import SwiftUI

// MARK: - Config

/// Cairn uses FREEMIUM + one-time Pro (no subscription). The free tier always
/// works (scan + basic clean); Pro unlocks tool-mediated cleans (docker prune,
/// simctl, git gc…), app uninstall, and batch power features. There is no
/// trial: Pro needs a key. Validation is by the customer's Polar license key +
/// the public org ID — no secret/product ID ships in the client.
enum LicenseConfig {
    /// Polar organization "Emotive Impact" — public (appears in checkout URLs).
    static let organizationID = "033c682c-186b-46fd-8f3a-03a686e96cba"
    /// How long Pro keeps working fully offline before a required online re-check.
    /// Generous on purpose: a lifetime licence should not lapse because a Mac
    /// spent a few weeks away from the internet.
    static let offlineGrace: TimeInterval = 60 * 60 * 24 * 30
    /// Set once a licence has been saved on this Mac. Opening Cairn reads the
    /// Keychain only when this is set, so people without a licence never have
    /// their Keychain touched at login. Not a secret: changing it from outside
    /// only makes Cairn look for a saved licence, which it then checks properly.
    static let savedHintKey = "cairn.licence.saved"
    /// Where buyers without a key purchase Cairn Pro.
    static let purchaseURL = URL(string: "https://cairnmac.com/#pricing")!
    static let price = "£35.99"

    /// DEV ONLY, and only in debug builds — unlocks Pro locally so Pro-gated
    /// screens can be built and reviewed without a real key:
    ///
    ///     defaults write com.emotiveimpact.cairn cairn.devPro -bool true
    ///     defaults delete com.emotiveimpact.cairn cairn.devPro     # turn back off
    ///
    /// Release builds (the app that is sold) never read the setting, so no
    /// command can turn Pro on without a key. `--safetycheck` still FAILS while
    /// it is on, and the UI shows a DEV PRO badge.
    #if DEBUG
    static var devProUnlock: Bool { UserDefaults.standard.bool(forKey: "cairn.devPro") }
    #else
    static let devProUnlock = false
    #endif
}

// MARK: - App integrity

/// Pro runs only in the Cairn that Emotive Impact signed. A copy whose code was
/// changed, the usual way to crack an app, no longer passes Apple's signature
/// check, so it keeps the free tier. Debug builds skip this.
enum AppIntegrity {
    static let teamID = "FC88M2P4F9"
    static let message = "This copy of Cairn has been changed or was not signed by Emotive Impact, so Pro can't run in it. Download Cairn again from cairnmac.com."
    /// Worked out once, off the main thread, when the saved licence is first read.
    static let allowsPro: Bool = {
        #if DEBUG
        return true
        #else
        return signedByUs()
        #endif
    }()

    /// Cairn itself, signed with Emotive Impact's Developer ID certificate.
    static let requirement = "identifier \"com.emotiveimpact.cairn\" and anchor apple generic"
        + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
        + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        + " and certificate leaf[subject.OU] = \"\(teamID)\""

    static func signedByUs() -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(Self.requirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        // The code that is running now.
        var me: SecCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCheckValidity(me, [], requirement) == errSecSuccess else { return false }
        // The whole app on disk too: every architecture, Info.plist and every
        // resource, so an edited file inside the app is caught as well.
        var bundle: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &bundle) == errSecSuccess, let bundle else { return false }
        let strict = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(bundle, strict, requirement) == errSecSuccess else { return false }
        // Our builds always run with the hardened runtime, which is what stops
        // other code being loaded into Cairn. A copy without it is not ours.
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(bundle, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let flags = ((info as? [String: Any])?[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value
        else { return false }
        return flags & SecCodeSignatureFlags.runtime.rawValue != 0
    }
}

// MARK: - Device identity

enum DeviceIdentity {
    static let hardwareUUID: String = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { if service != 0 { IOObjectRelease(service) } }
        guard service != 0,
              let prop = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0),
              let uuid = prop.takeRetainedValue() as? String
        else { return "unknown-mac" }
        return uuid
    }()
    static var label: String { Host.current().localizedName ?? "Mac" }
}

// MARK: - Keychain-backed store

struct StoredLicense: Codable {
    var key: String
    var activationID: String
    var lastValidated: Date
    var granted: Bool
    /// Written by Cairn on this Mac. A record typed in by hand, edited, or
    /// copied from another Mac has no matching seal, so it needs an online check.
    var seal: String? = nil

    /// Pro without reaching Polar: only a record this Mac sealed, checked
    /// within the offline grace period, and never dated in the future.
    var grantsOffline: Bool {
        let age = Date().timeIntervalSince(lastValidated)
        return granted && age > -300 && age < LicenseConfig.offlineGrace && seal == LicenseSeal.make(self)
    }
    mutating func reseal() { seal = LicenseSeal.make(self) }
}

/// Ties a saved licence to this Mac and to what Polar last said about it.
enum LicenseSeal {
    private static let pepper = "cairn.licence.seal.v1.4e9b7c21d6"
    static func make(_ license: StoredLicense) -> String {
        let key = SymmetricKey(data: SHA256.hash(data: Data((pepper + DeviceIdentity.hardwareUUID).utf8)))
        let message = "\(license.key)|\(license.activationID)|\(Int(license.lastValidated.timeIntervalSince1970))|\(license.granted)"
        return Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)).base64EncodedString()
    }
}

/// A locked/unavailable or malformed record is never treated as absent.
/// No read may show a system prompt while the window is being constructed.
enum LicenseStorageError: LocalizedError {
    case keychain(OSStatus), malformed
    var errorDescription: String? {
        switch self {
        case .keychain: return "Cairn could not access its saved license in Keychain. Your saved records were left intact. Unlock your login keychain, then retry."
        case .malformed: return "The saved license record could not be read. It was left intact; contact support before replacing it."
        }
    }
}

enum LicenseKeychain {
    private static func query(_ account: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.emotiveimpact.cairn.license",
                kSecAttrAccount as String: account,
                kSecUseAuthenticationContext as String: context]
    }
    static func read<T: Decodable>(_ account: String, as: T.Type,
                                  fetch: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemCopyMatching) throws -> T? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = fetch(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw LicenseStorageError.keychain(status) }
        guard let data = item as? Data, let value = try? JSONDecoder().decode(T.self, from: data) else { throw LicenseStorageError.malformed }
        return value
    }
    static func write<T: Encodable>(_ account: String, value: T, onlyIfAbsent: Bool = false,
                                   update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate,
                                   add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemAdd) throws {
        let data = try JSONEncoder().encode(value)
        let base = query(account)
        if !onlyIfAbsent {
            let status = update(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecSuccess { return }
            guard status == errSecItemNotFound else { throw LicenseStorageError.keychain(status) }
        }
        var addition = base
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = add(addition as CFDictionary, nil)
        guard status == errSecSuccess else { throw LicenseStorageError.keychain(status) }
    }
    static func clear(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LicenseStorageError.keychain(status) }
    }
}

enum LicenseStore {
    static func load() throws -> StoredLicense? { try LicenseKeychain.read("primary", as: StoredLicense.self) }
    static func save(_ license: StoredLicense) throws { try LicenseKeychain.write("primary", value: license) }
    static func clear() throws { try LicenseKeychain.clear("primary") }
}

struct LocalLicenseState {
    let license: StoredLicense?
}

/// Serial off-main queue bounds outstanding Keychain work even if macOS stalls.
/// The watchdog below reports a slow read; it never spawns replacement reads.
enum LicenseStorageWorker {
    private static let queue = DispatchQueue(label: "dev.cairn.license-storage", qos: .utility)
    static func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    static func load() throws -> LocalLicenseState {
        _ = AppIntegrity.allowsPro
        return LocalLicenseState(license: try LicenseStore.load())
    }
}

// MARK: - Polar customer-portal client

struct PolarClient {
    var organizationID: String
    var base = URL(string: "https://api.polar.sh")!
    var session: URLSession = .shared

    struct PolarError: LocalizedError {
        let message: String
        var status: Int? = nil
        var errorDescription: String? { message }
        var isDefinitiveRejection: Bool { status == 403 || status == 404 }
    }

    func activate(key: String) async throws -> String {
        let body: [String: Any] = [
            "key": key, "organization_id": organizationID,
            "label": DeviceIdentity.label, "meta": ["device": DeviceIdentity.hardwareUUID],
        ]
        let json = try await post("/v1/customer-portal/license-keys/activate", body)
        guard let id = json["id"] as? String else { throw PolarError(message: "Activation failed — please try again.") }
        return id
    }

    func validate(key: String, activationID: String) async throws -> Bool {
        let body: [String: Any] = ["key": key, "organization_id": organizationID, "activation_id": activationID]
        let json = try await post("/v1/customer-portal/license-keys/validate", body)
        // A broken/changed response is not evidence of revocation. Throw a
        // transient error so refresh retains the existing offline grace state.
        switch json["status"] as? String {
        case "granted": return true
        case "revoked", "disabled": return false
        default: throw PolarError(message: "Cairn couldn't check your licence just now. It will try again later.")
        }
    }

    func deactivate(key: String, activationID: String) async throws {
        let body: [String: Any] = ["key": key, "organization_id": organizationID, "activation_id": activationID]
        _ = try await post("/v1/customer-portal/license-keys/deactivate", body)
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw PolarError(message: "No response from the licensing server.") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200...299).contains(http.statusCode) else {
            let detail = (json["detail"] as? String) ?? (json["error"] as? String)
            switch http.statusCode {
            case 403: throw PolarError(message: detail ?? "This license is not active.", status: 403)
            case 404: throw PolarError(message: "License key not found. Check for typos.", status: 404)
            case 429: throw PolarError(message: "Activation limit reached for this key.", status: 429)
            default: throw PolarError(message: detail ?? "Licensing error (\(http.statusCode)).", status: http.statusCode)
            }
        }
        return json
    }
}

// MARK: - License manager

/// The licence key is typed in once. After that Cairn reads it from the
/// Keychain by itself shortly after opening, confirms it with Polar quietly,
/// and never asks for it again: not at login, not after a restart, not after
/// an update. When Polar can't be reached Cairn keeps the saved key, keeps Pro
/// on for the offline grace period, and tries again on its own.
@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isPro = false
    /// Pro features unlocked (a valid Pro licence; there is no trial). Free tier always works regardless.
    @Published private(set) var isUnlocked = false
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    @Published private(set) var hasRequestedStorage = false
    @Published private(set) var isLoading = false
    @Published private(set) var storageMessage: String?
    /// A licence is saved on this Mac but the last online check could not
    /// reach Polar. Cairn is retrying by itself; the key is never asked for.
    @Published private(set) var waitingToConfirm = false
    /// A licence key is saved on this Mac (whatever Polar last said about it).
    @Published private(set) var hasSavedLicense = false
    private let client: PolarClient
    private var stored: StoredLicense? { didSet { hasSavedLicense = stored != nil } }
    private let loadLocal: () throws -> LocalLicenseState
    private let saveLocal: (StoredLicense) throws -> Void
    private let defaults: UserDefaults
    private let checkOnline: Bool
    private let honorDevUnlock: Bool
    /// Waits between quiet retries when Polar can't be reached. The last one repeats.
    private let retryDelays: [TimeInterval]
    private var retryTask: Task<Void, Never>?
    private var retryCount = 0

    init(loadLocal: @escaping () throws -> LocalLicenseState = LicenseStorageWorker.load,
         saveLocal: @escaping (StoredLicense) throws -> Void = LicenseStore.save,
         client: PolarClient = PolarClient(organizationID: LicenseConfig.organizationID),
         defaults: UserDefaults = .standard,
         retryDelays: [TimeInterval] = [30, 120, 300, 900],
         automatic: Bool = false, checkOnline: Bool = true, honorDevUnlock: Bool = true) {
        self.loadLocal = loadLocal
        self.saveLocal = saveLocal
        self.client = client
        self.defaults = defaults
        self.retryDelays = retryDelays
        self.checkOnline = checkOnline
        self.honorDevUnlock = honorDevUnlock
        guard !CommandLine.arguments.contains("--preview-ui"), automatic else { return }
        // Return immediately. Neither Security nor network APIs run in init.
        Task { await reloadStorage() }
    }

    /// Called once when Cairn opens. Waits for the window to be up, then reads
    /// a saved licence in the background so Pro is on without visiting
    /// Settings. Does nothing when no licence was ever saved on this Mac.
    func loadAfterLaunch(delay: TimeInterval = 2) async {
        guard defaults.bool(forKey: LicenseConfig.savedHintKey) else { return }
        try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
        guard !Task.isCancelled else { return }
        await loadIfNeeded()
    }

    /// Settings › Licence and the launch read both come here. Whichever runs
    /// first does the read; returning to the view never queues another one.
    func loadIfNeeded() async {
        guard !hasRequestedStorage, !CommandLine.arguments.contains("--preview-ui") else { return }
        await reloadStorage()
    }

    func reloadStorage() async {
        guard !isLoading, !isBusy else { return }
        hasRequestedStorage = true
        isLoading = true
        storageMessage = nil
        let watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self, self.isLoading else { return }
            self.storageMessage = "The saved license is taking longer to read. You can leave Settings and keep using Cairn; this check will continue in the background."
        }
        defer { watchdog.cancel(); isLoading = false }
        do {
            let state = try await LicenseStorageWorker.run(loadLocal)
            stored = state.license
            // A licence saved before this hint existed is found the first time
            // Settings is opened; from then on it is read at every launch.
            if state.license != nil { defaults.set(true, forKey: LicenseConfig.savedHintKey) }
            isPro = state.license?.grantsOffline ?? false
            if honorDevUnlock && LicenseConfig.devProUnlock { isPro = true }
            storageMessage = nil
            recompute()
            if checkOnline { await refreshStoredLicense() }
        } catch {
            storageMessage = error.localizedDescription
            // Preserve any already loaded state. Do not replace a saved
            // license after a failed read.
        }
    }

    private func recompute() {
        if isPro && !AppIntegrity.allowsPro {
            isPro = false
            lastError = AppIntegrity.message
        }
        isUnlocked = isPro
    }

    @discardableResult
    func activate(key rawKey: String) async -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, hasRequestedStorage, !isBusy, !isLoading, storageMessage == nil else { return false }
        isBusy = true; lastError = nil
        defer { isBusy = false }
        do {
            let activationID = try await client.activate(key: key)
            let granted = try await client.validate(key: key, activationID: activationID)
            var license = StoredLicense(key: key, activationID: activationID, lastValidated: Date(), granted: granted)
            license.reseal()
            let saved = license, save = saveLocal
            try await LicenseStorageWorker.run { try save(saved) }; stored = saved
            defaults.set(true, forKey: LicenseConfig.savedHintKey)
            stopRetrying()
            isPro = granted; recompute()
            if !granted { lastError = "This license is not active." }
            return isPro
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Activation failed."
            return false
        }
    }

    func deactivate() async {
        guard let s = stored, !isBusy, !isLoading else { return }
        isBusy = true; lastError = nil; defer { isBusy = false }
        do {
            try await client.deactivate(key: s.key, activationID: s.activationID)
            isPro = false; recompute()
            stopRetrying()
            do {
                try await LicenseStorageWorker.run { try LicenseStore.clear() }
                stored = nil
                defaults.set(false, forKey: LicenseConfig.savedHintKey)
            } catch { storageMessage = error.localizedDescription; throw error }
        } catch { lastError = error.localizedDescription }
    }

    /// "Check now" in Settings, and the quiet retries.
    func refresh() async {
        guard !isBusy, !isLoading else { return }
        isBusy = true; defer { isBusy = false }
        await refreshStoredLicense()
    }

    private func refreshStoredLicense() async {
        defer { recompute() }
        // Never let a network round-trip revoke the local dev unlock.
        if honorDevUnlock && LicenseConfig.devProUnlock { isPro = true; return }
        guard let s = stored else { isPro = false; stopRetrying(); return }
        let save = saveLocal
        do {
            let granted = try await client.validate(key: s.key, activationID: s.activationID)
            var u = s; u.granted = granted; u.lastValidated = Date(); u.reseal()
            stored = u; isPro = granted
            stopRetrying()
            do { try await LicenseStorageWorker.run { try save(u) } }
            catch { storageMessage = error.localizedDescription }
        } catch let e as PolarClient.PolarError where e.isDefinitiveRejection {
            isPro = false; var u = s; u.granted = false; u.reseal(); stored = u
            stopRetrying()
            do { try await LicenseStorageWorker.run { try save(u) } }
            catch { storageMessage = error.localizedDescription }
        } catch {
            // No internet yet (common straight after login), or Polar is busy.
            // Keep the saved key, use the offline grace, and try again quietly.
            isPro = s.grantsOffline
            waitingToConfirm = true
            retryQuietly()
        }
    }

    private func retryQuietly() {
        retryTask?.cancel()
        guard !retryDelays.isEmpty else { return }
        let wait = retryDelays[min(retryCount, retryDelays.count - 1)]
        retryCount += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, wait) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Settings may be mid-check; try again after the next wait instead.
            if self.isBusy || self.isLoading { self.retryQuietly() } else { await self.refresh() }
        }
    }

    private func stopRetrying() {
        retryTask?.cancel(); retryTask = nil
        retryCount = 0
        waitingToConfirm = false
    }
}
