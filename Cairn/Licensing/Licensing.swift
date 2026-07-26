import Foundation
import IOKit
import Security
import SwiftUI

// MARK: - Config

/// Cairn uses FREEMIUM + one-time Pro (no subscription). The free tier always
/// works (scan + basic clean); Pro unlocks tool-mediated cleans (docker prune,
/// simctl, git gc…), app uninstall, and batch power features. A 14-day trial
/// unlocks everything. Validation is by the customer's Polar license key + the
/// public org ID — no secret/product ID ships in the client.
enum LicenseConfig {
    /// Polar organization "Emotive Impact" — public (appears in checkout URLs).
    static let organizationID = "033c682c-186b-46fd-8f3a-03a686e96cba"
    /// Free, full-feature trial before Pro features require a key.
    static let trialDays = 14
    /// How long Pro keeps working fully offline before a required online re-check.
    static let offlineGrace: TimeInterval = 60 * 60 * 24 * 14
    /// Where buyers without a key purchase Cairn Pro (domain TBD pre-launch).
    static let purchaseURL = URL(string: "https://getcairn.app/#pricing")!
    static let price = "£95"

    /// DEV ONLY — unlocks Pro locally so Pro-gated screens can be built and
    /// reviewed without a real key. Off unless explicitly switched on for this
    /// user on this Mac:
    ///
    ///     defaults write com.emotiveimpact.cairn cairn.devPro -bool true
    ///     defaults delete com.emotiveimpact.cairn cairn.devPro     # turn back off
    ///
    /// No code path enables this by default, so a shipped build is never Pro
    /// without a key. `--safetycheck` FAILS while it is on, so a build with it
    /// left enabled can't pass the release gate. The UI also shows a DEV PRO
    /// badge, so it can never be mistaken for a real licence.
    static var devProUnlock: Bool { UserDefaults.standard.bool(forKey: "cairn.devPro") }
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
}

enum LicenseStore {
    private static let service = "com.emotiveimpact.cairn.license"
    private static let account = "primary"

    static func load() -> StoredLicense? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let license = try? JSONDecoder().decode(StoredLicense.self, from: data)
        else { return nil }
        return license
    }

    static func save(_ license: StoredLicense) {
        guard let data = try? JSONEncoder().encode(license) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func clear() {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
    }
}

/// Trial start, persisted in the Keychain so it survives reinstall.
enum TrialStore {
    private static let service = "com.emotiveimpact.cairn.license"
    private static let account = "trial"

    static func startDate() -> Date {
        if let existing = load() { return existing }
        let now = Date(); save(now); return now
    }
    private static func load() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let seconds = try? JSONDecoder().decode(Double.self, from: data)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
    private static func save(_ date: Date) {
        guard let data = try? JSONEncoder().encode(date.timeIntervalSince1970) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
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
        return ((json["status"] as? String) ?? "") == "granted"
    }

    func deactivate(key: String, activationID: String) async {
        let body: [String: Any] = ["key": key, "organization_id": organizationID, "activation_id": activationID]
        _ = try? await post("/v1/customer-portal/license-keys/deactivate", body)
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
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

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isPro = false
    @Published private(set) var isInTrial = false
    /// Pro features unlocked (Pro OR within trial). Free tier always works regardless.
    @Published private(set) var isUnlocked = false
    @Published private(set) var trialDaysRemaining = 0
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private let client = PolarClient(organizationID: LicenseConfig.organizationID)
    private let trialStart: Date
    private var stored: StoredLicense?

    init() {
        trialStart = TrialStore.startDate()
        stored = LicenseStore.load()
        if let s = stored, s.granted, Date().timeIntervalSince(s.lastValidated) < LicenseConfig.offlineGrace { isPro = true }
        if LicenseConfig.devProUnlock { isPro = true }
        recompute()
        Task { await refresh() }
    }

    var hasKey: Bool { stored != nil }

    private func recompute() {
        let trialEnd = trialStart.addingTimeInterval(Double(LicenseConfig.trialDays) * 86400)
        isInTrial = !isPro && Date() < trialEnd
        trialDaysRemaining = isInTrial ? max(1, Int(ceil(trialEnd.timeIntervalSinceNow / 86400))) : 0
        isUnlocked = isPro || isInTrial
    }

    @discardableResult
    func activate(key rawKey: String) async -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        isBusy = true; lastError = nil
        defer { isBusy = false }
        do {
            let activationID = try await client.activate(key: key)
            let granted = try await client.validate(key: key, activationID: activationID)
            let license = StoredLicense(key: key, activationID: activationID, lastValidated: Date(), granted: granted)
            LicenseStore.save(license); stored = license
            isPro = granted; recompute()
            if !granted { lastError = "This license is not active." }
            return granted
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Activation failed."
            return false
        }
    }

    func deactivate() async {
        guard let s = stored else { return }
        isBusy = true; defer { isBusy = false }
        await client.deactivate(key: s.key, activationID: s.activationID)
        LicenseStore.clear(); stored = nil; isPro = false; recompute()
    }

    func refresh() async {
        defer { recompute() }
        // Never let a network round-trip revoke the local dev unlock.
        if LicenseConfig.devProUnlock { isPro = true; return }
        guard let s = stored else { isPro = false; return }
        do {
            let granted = try await client.validate(key: s.key, activationID: s.activationID)
            var u = s; u.granted = granted; u.lastValidated = Date()
            LicenseStore.save(u); stored = u; isPro = granted
        } catch let e as PolarClient.PolarError where e.isDefinitiveRejection {
            isPro = false; var u = s; u.granted = false; LicenseStore.save(u); stored = u
        } catch {
            isPro = (s.granted && Date().timeIntervalSince(s.lastValidated) < LicenseConfig.offlineGrace)
        }
    }
}
