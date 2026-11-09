import Foundation

/// `--licensecheck`: the licence key is asked for once and never again.
///
/// Every check uses an in-memory licence server and an in-memory Keychain, so
/// nothing reaches Polar, the real Keychain or the app's real preferences.
@MainActor enum LicenseCheck {
    static func run() async {
        var failures = 0
        func check(_ good: Bool, _ label: String) {
            print("\(good ? "PASS" : "FAIL") \(label)"); if !good { failures += 1 }
        }
        let suite = "cairn.licensecheck.fixture"
        UserDefaults().removePersistentDomain(forName: suite)
        guard let defaults = UserDefaults(suiteName: suite) else {
            print("FAIL fixture preferences"); exit(1)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LicenseServerFixture.self]
        let session = URLSession(configuration: config)
        let client = PolarClient(organizationID: "fixture", base: URL(string: "https://polar.invalid")!, session: session)

        func sealed(daysAgo: Double) -> StoredLicense {
            var license = StoredLicense(key: "FIXTURE-KEY", activationID: "fixture",
                                        lastValidated: Date().addingTimeInterval(-daysAgo * 86_400), granted: true)
            license.reseal()
            return license
        }
        func manager(_ license: StoredLicense?, saves: SaveLog, retry: [TimeInterval] = [60]) -> LicenseManager {
            LicenseManager(loadLocal: { LocalLicenseState(license: license) },
                           saveLocal: { saves.append($0) },
                           client: client, defaults: defaults, retryDelays: retry,
                           automatic: false, checkOnline: true, honorDevUnlock: false)
        }
        func waitUntil(_ condition: () -> Bool) async {
            let deadline = Date().addingTimeInterval(3)
            while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        }

        check(LicenseConfig.offlineGrace >= 30 * 86_400, "Pro keeps working offline for at least 30 days")

        // Nobody with no saved licence has their Keychain read at launch.
        let untouched = ReadLog()
        let fresh = LicenseManager(loadLocal: { untouched.mark(); return LocalLicenseState(license: nil) },
                                   client: client, defaults: defaults, honorDevUnlock: false)
        await fresh.loadAfterLaunch(delay: 0)
        check(!untouched.wasRead && !fresh.hasRequestedStorage, "Without a saved licence, opening Cairn leaves the Keychain alone")

        // Typing the key in once remembers that a licence is saved.
        LicenseServerFixture.mode = "granted"
        let activating = manager(nil, saves: SaveLog())
        await activating.loadIfNeeded()
        let activated = await activating.activate(key: "FIXTURE-KEY")
        check(activated && activating.isUnlocked && defaults.bool(forKey: LicenseConfig.savedHintKey),
              "Entering the key once unlocks Pro and is remembered")

        // Next launch: read by itself, no visit to Settings, no key asked for.
        let launchSaves = SaveLog()
        let launched = manager(sealed(daysAgo: 3), saves: launchSaves)
        await launched.loadAfterLaunch(delay: 0)
        check(launched.hasRequestedStorage && launched.isUnlocked && !launched.waitingToConfirm,
              "Opening Cairn turns Pro on by itself from the saved licence")
        check(launchSaves.count == 1, "The quiet online check refreshes the saved licence")

        // Straight after login, before Wi-Fi is up, within the grace period.
        LicenseServerFixture.mode = "offline"
        let earlySaves = SaveLog()
        let early = manager(sealed(daysAgo: 10), saves: earlySaves)
        await early.loadAfterLaunch(delay: 0)
        check(early.isUnlocked && early.waitingToConfirm && early.hasSavedLicense && earlySaves.count == 0,
              "No internet yet keeps Pro on and the saved licence untouched")

        // Away from the internet longer than the grace: paused, key kept, retried.
        let away = manager(sealed(daysAgo: 45), saves: SaveLog(), retry: [0.05])
        await away.loadAfterLaunch(delay: 0)
        check(!away.isUnlocked && away.waitingToConfirm && away.hasSavedLicense,
              "After a long time offline Pro pauses but the saved key is kept")
        LicenseServerFixture.mode = "granted"
        await waitUntil { away.isUnlocked }
        check(away.isUnlocked && !away.waitingToConfirm, "Pro comes back by itself once the licence server answers")

        // A garbled reply is treated like no internet, never as a cancelled licence.
        LicenseServerFixture.mode = "garbled"
        let garbled = manager(sealed(daysAgo: 5), saves: SaveLog())
        await garbled.loadAfterLaunch(delay: 0)
        check(garbled.isUnlocked && garbled.waitingToConfirm, "A garbled server reply keeps Pro and retries")

        // A refunded licence switches Pro off, keeps the record, and stops retrying.
        LicenseServerFixture.mode = "revoked"
        let refundSaves = SaveLog()
        let refunded = manager(sealed(daysAgo: 1), saves: refundSaves)
        await refunded.loadAfterLaunch(delay: 0)
        check(!refunded.isUnlocked && !refunded.waitingToConfirm && refunded.hasSavedLicense
              && refundSaves.last?.granted == false, "A cancelled licence switches Pro off without retrying")

        // exit() skips defer, so tidy up first.
        session.invalidateAndCancel()
        UserDefaults().removePersistentDomain(forName: suite)
        print("Licence checks: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}

private final class SaveLog: @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [StoredLicense] = []
    func append(_ license: StoredLicense) { lock.lock(); saved.append(license); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return saved.count }
    var last: StoredLicense? { lock.lock(); defer { lock.unlock() }; return saved.last }
}

private final class ReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var read = false
    func mark() { lock.lock(); read = true; lock.unlock() }
    var wasRead: Bool { lock.lock(); defer { lock.unlock() }; return read }
}

/// In-memory licence server. `mode` picks how it answers.
private final class LicenseServerFixture: URLProtocol {
    private static let lock = NSLock()
    private static var current = "granted"
    static var mode: String {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let body: String
        switch Self.mode {
        case "offline":
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        case "garbled": body = "unavailable"
        case "revoked": body = "{\"status\":\"revoked\"}"
        default:
            body = url.path.hasSuffix("/activate") ? "{\"id\":\"fixture-activation\"}" : "{\"status\":\"granted\"}"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
