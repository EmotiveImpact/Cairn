import Foundation
import AppKit
import CryptoKit
import ObjectiveC

/// Apple Intelligence's on-device models. macOS 27 downloads 12 to 30 GB of
/// them and has no single off switch. Cairn never deletes files under /System.
/// Instead a configuration profile, which the person approves in System
/// Settings, turns the features off and points the models' downloads at a
/// closed local port; then macOS's own asset service is asked to remove them.
/// Removing the profile undoes all of it, and macOS downloads the models again
/// the first time a feature needs them.
///
/// The restriction keys, model sets and the asset service's reset operation
/// were first mapped by pared (github.com/4evy/pared, MIT) and RemoveMacAI
/// (github.com/omlahore/RemoveMacAI, MIT).
enum AppleIntelligence {
    /// A downloadable set of models in Apple's asset service.
    struct ModelSet: Identifiable, Equatable, Sendable {
        /// The set's name in the asset service.
        let id: String
        let assetType: String
        let title: String
        let line: String
    }

    /// A preference the profile forces while a feature is off.
    struct Forced: Equatable, Sendable {
        let domain: String
        let key: String
        let value: Bool
    }

    /// One thing that stops working, the switches that turn it off and the
    /// model sets it needs.
    struct Feature: Identifiable, Sendable {
        let id: String
        let title: String
        var restrictions: [String] = []
        var forced: [Forced] = []
        let sets: [String]
        /// The first macOS (major, minor) with the feature. Older ones ignore its
        /// keys, so it is left out there rather than switched off for nothing.
        var since: (Int, Int) = (15, 1)

        var supported: Bool {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return (os.majorVersion, os.minorVersion) >= since
        }
    }

    static let foundation = "com.apple.modelcatalog"
    static let visual = "com.apple.MobileAsset.UAF.FM.Visual"
    static let code = "com.apple.MobileAsset.UAF.FM.CodeLM"
    static let cleanUp = "com.apple.MobileAsset.UAF.Photos.MagicCleanup"
    static let spatial = "com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive"

    static let sets: [ModelSet] = [
        ModelSet(id: foundation, assetType: "com.apple.MobileAsset.UAF.FM.GenerativeModels",
                 title: "Main models", line: "Siri, Writing Tools, summaries and smart replies"),
        ModelSet(id: visual, assetType: visual, title: "Image models", line: "Genmoji and Image Playground"),
        ModelSet(id: code, assetType: code, title: "Xcode code completion", line: "Predictive code completion in Xcode"),
        ModelSet(id: cleanUp, assetType: cleanUp, title: "Photos Clean Up", line: "Removing things from photos"),
        ModelSet(id: spatial, assetType: spatial, title: "Spatial Photos", line: "Turning photos into spatial scenes"),
    ]

    static let features: [Feature] = [
        Feature(id: "siri", title: "Siri", restrictions: ["allowAssistant"], forced: [
            Forced(domain: "com.apple.assistant.support", key: "Assistant Enabled", value: false),
            Forced(domain: "com.apple.Siri", key: "StatusMenuVisible", value: false),
            Forced(domain: "com.apple.Siri", key: "VoiceTriggerUserEnabled", value: false),
        ], sets: [foundation]),
        Feature(id: "writing-tools", title: "Writing Tools", restrictions: ["allowWritingTools"], sets: [foundation]),
        Feature(id: "genmoji", title: "Genmoji", restrictions: ["allowGenmoji"], sets: [foundation, visual]),
        Feature(id: "image-playground", title: "Image Playground", restrictions: ["allowImagePlayground"], sets: [foundation, visual]),
        Feature(id: "mail", title: "Mail summaries and smart replies",
                restrictions: ["allowMailSummary", "allowMailSmartReplies"], forced: [
                    Forced(domain: "group.com.apple.mail", key: "DisableAutomaticMessageSummarization", value: true),
                    Forced(domain: "group.com.apple.mail", key: "PersonalizedSmartReplies", value: false),
                ], sets: [foundation]),
        Feature(id: "notification-summaries", title: "Notification summaries",
                forced: [Forced(domain: "group.com.apple.usernoted", key: "summarize_previews", value: false)], sets: [foundation]),
        Feature(id: "messages-summaries", title: "Messages summaries",
                forced: [Forced(domain: "com.apple.MobileSMS", key: "messageSummarizationEnabled", value: false)], sets: [foundation]),
        Feature(id: "safari-summaries", title: "Safari summaries", restrictions: ["allowSafariSummary"], sets: [foundation], since: (15, 4)),
        Feature(id: "notes-summaries", title: "Notes summaries", restrictions: ["allowNotesTranscriptionSummary"], sets: [foundation], since: (15, 3)),
        Feature(id: "spatial-photos", title: "Spatial Photos",
                forced: [Forced(domain: "com.apple.spatialphotosrelive", key: "LocallyDisabled", value: true)], sets: [spatial], since: (26, 0)),
        Feature(id: "photos-clean-up", title: "Photos Clean Up", sets: [cleanUp]),
        Feature(id: "xcode-completion", title: "Xcode code completion", sets: [code]),
    ]

    static var availableFeatures: [Feature] { features.filter(\.supported) }

    /// The sets this macOS has: those a feature it has still names.
    static func available(among features: [Feature] = availableFeatures) -> [ModelSet] {
        sets.filter { set in features.contains { $0.sets.contains(set.id) } }
    }

    /// Apple Intelligence needs Apple silicon and macOS 15.1 or later.
    static var supportedMac: Bool {
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let silicon = sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0 && arm == 1
        return silicon && ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0))
    }

    /// Everything but Xcode's code completion when Xcode is here: Cairn's people write code.
    static func defaultChoice(among features: [Feature] = availableFeatures) -> Set<String> {
        var all = Set(available(among: features).map(\.id))
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") != nil { all.remove(code) }
        return all
    }

    /// Every feature that needs one of the chosen sets turns off.
    static func featuresOff(removing chosen: Set<String>, among features: [Feature] = availableFeatures) -> [Feature] {
        features.filter { !Set($0.sets).isDisjoint(with: chosen) }
    }

    /// The sets that go: each one whose features are all turning off. That is
    /// the chosen sets, plus the image models when the main models go, since
    /// Genmoji and Image Playground need both.
    static func setsToRemove(chosen: Set<String>, among features: [Feature] = availableFeatures) -> [String] {
        let off = Set(featuresOff(removing: chosen, among: features).map(\.id))
        return sets.map(\.id).filter { set in
            let users = features.filter { $0.sets.contains(set) }
            return !users.isEmpty && users.allSatisfy { off.contains($0.id) }
        }
    }

    // MARK: - The profile

    /// The configuration profile that holds every switch. macOS only installs
    /// or removes it when the person says so in System Settings.
    enum Profile {
        static let identifier = "com.emotiveimpact.cairn.apple-intelligence"
        static let downloadDomain = "com.apple.MobileAsset"
        static let downloadKeyPrefix = "DownloadServerBaseURLOverride-"
        /// Port 9 on this Mac never answers, so a download fails instead of refilling the disk.
        static let blockedURL = "https://127.0.0.1:9/cairn-blocked/"

        static var file: URL {
            (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileScan.home.appendingPathComponent("Library/Application Support"))
                .appendingPathComponent("Cairn/Apple Intelligence off.mobileconfig")
        }

        /// The profile for these sets, or nil when there is nothing to turn off.
        static func data(removing chosen: Set<String>, among features: [Feature] = availableFeatures) throws -> Data? {
            let removing = setsToRemove(chosen: chosen, among: features)
            guard !removing.isEmpty else { return nil }
            var restrictions = payload(type: "com.apple.applicationaccess", suffix: "restrictions", name: "Restrictions")
            var forced: [String: [String: Any]] = [:]
            for feature in featuresOff(removing: Set(removing), among: features) {
                for key in feature.restrictions { restrictions[key] = false }
                for pref in feature.forced { forced[pref.domain, default: [:]][pref.key] = pref.value }
            }
            for set in sets where removing.contains(set.id) {
                forced[downloadDomain, default: [:]][downloadKeyPrefix + set.assetType] = blockedURL
            }
            // Cairn's own marker, so the page can tell the profile is in force and what it holds.
            forced[identifier] = ["installed": true, "sets": removing.joined(separator: ",")]
            let preferences = forced.keys.sorted().map { domain -> [String: Any] in
                var p = payload(type: "com.apple.ManagedClient.preferences", suffix: "preferences." + domain,
                                name: "Forced settings: \(domain)")
                p["PayloadContent"] = [domain: ["Forced": [["mcx_preference_settings": forced[domain] ?? [:]]]]]
                return p
            }
            let hasRestrictions = restrictions.keys.contains { $0.hasPrefix("allow") }
            let profile: [String: Any] = [
                "PayloadType": "Configuration",
                "PayloadVersion": 1,
                "PayloadIdentifier": identifier,
                "PayloadUUID": uuid(identifier),
                "PayloadDisplayName": "Cairn: Apple Intelligence off",
                "PayloadDescription": "Turns off the Apple Intelligence features you chose in Cairn and stops their models downloading again. Remove this profile to turn them back on; macOS then downloads the models again the first time a feature needs them.",
                "PayloadOrganization": "Cairn",
                "PayloadScope": "System",
                "PayloadRemovalDisallowed": false,
                "PayloadContent": (hasRestrictions ? [restrictions] : []) + preferences,
            ]
            return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        }

        private static func payload(type: String, suffix: String, name: String) -> [String: Any] {
            let id = identifier + "." + suffix
            return ["PayloadType": type, "PayloadVersion": 1, "PayloadIdentifier": id,
                    "PayloadUUID": uuid(id), "PayloadDisplayName": name]
        }

        /// The same UUID for the same payload every time, so a new profile
        /// replaces the old one instead of sitting beside it.
        static func uuid(_ name: String) -> String {
            var b = Array(Insecure.SHA1.hash(data: Data(name.utf8)).prefix(16))
            b[6] = (b[6] & 0x0F) | 0x50
            b[8] = (b[8] & 0x3F) | 0x80
            return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                               b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])).uuidString
        }

        struct Installed: Equatable {
            var on = false
            var sets: Set<String> = []
        }

        /// Whether Cairn's profile is in force, and which sets it turned off.
        static func installed() -> Installed {
            let domain = identifier as CFString
            CFPreferencesAppSynchronize(domain)
            guard CFPreferencesAppValueIsForced("installed" as CFString, domain) else { return Installed() }
            let list = CFPreferencesCopyAppValue("sets" as CFString, domain) as? String ?? ""
            return Installed(on: true, sets: Set(list.split(separator: ",").map(String.init)))
        }

        /// Writes the profile and opens it, so System Settings shows it for approval.
        static func present(removing chosen: Set<String>) throws {
            guard let data = try data(removing: chosen) else { return }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            NSWorkspace.shared.open(file)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { openSettings() }
        }

        /// System Settings at the profiles pane.
        static func openSettings() {
            for link in ["x-apple.systempreferences:com.apple.Profiles-Settings.extension",
                         "x-apple.systempreferences:com.apple.preferences.configurationprofiles"] {
                if let url = URL(string: link), NSWorkspace.shared.open(url) { return }
            }
        }
    }

    // MARK: - macOS's asset service

    /// The asset service that downloads and removes the models. It is private,
    /// so every class and selector is looked up at run time and anything
    /// missing fails closed: Cairn then says it couldn't ask, and removes nothing.
    enum AssetService {
        private static let framework = "/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework"
        private static let service = "com.apple.siri.uaf.subscription.service"
        private static let loaded: Bool = dlopen(framework, RTLD_NOW) != nil

        static var available: Bool { assetType(of: foundation) != nil }

        private static func runtime(_ name: String) -> UAFRuntime? {
            guard loaded, let cls = NSClassFromString(name) else { return nil }
            return unsafeBitCast(cls as AnyObject, to: UAFRuntime.self)
        }

        /// The asset type the service gives a set on this macOS, or nil.
        static func assetType(of set: String) -> String? {
            guard let manager = runtime("UAFConfigurationManager")?.defaultManager?() ?? nil,
                  let found = unsafeBitCast(manager, to: UAFRuntime.self).getAssetSet?(set) ?? nil,
                  let type = unsafeBitCast(found, to: UAFRuntime.self).autoAssetType?() ?? nil else { return nil }
            return type as? String
        }

        /// Bytes on disk by asset type. macOS won't list some of these folders
        /// even to an admin, so the service is the only measure. Its inventory
        /// comes first, since a set's own status can say 0 for a set that is
        /// there; the status is asked only when the inventory can't be read.
        /// Nil when neither answers.
        static func measure() -> [String: Int64]? {
            if let found = inventory() { return found }
            var bytes: [String: Int64] = [:]
            for set in sets {
                if let n = downloadedBytes(set.id), n >= 0 { bytes[set.assetType] = n }
            }
            return bytes.isEmpty ? nil : bytes
        }

        private static func downloadedBytes(_ set: String) -> Int64? {
            guard let status = runtime("UAFAutoAssetManager")?.latestStatus?(forClients: set, error: nil) ?? nil else { return nil }
            return unsafeBitCast(status, to: UAFRuntime.self).downloadedFilesystemBytes?()
        }

        /// The service's own inventory of what is on this Mac, or nil when it
        /// doesn't answer or answers in a shape Cairn can't read.
        static func inventory() -> [String: Int64]? {
            guard let manager = runtime("UAFAssetSetManager") else { return nil }
            var error: NSError?
            guard let raw = manager.generateInformation?(&error) ?? nil else { return nil }
            var info: Any = raw
            if let text = info as? String, let data = text.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                info = parsed
            }
            guard let dictionary = info as? [String: Any] else { return nil }
            return parseInventory(dictionary)
        }

        static func parseInventory(_ info: [String: Any]) -> [String: Int64] {
            var bytes: [String: Int64] = [:]
            for asset in info["SystemAssets"] as? [[String: Any]] ?? [] {
                guard asset["isPresentOnDevice"] as? Bool == true,
                      let meta = asset["metadata"] as? [String: Any],
                      let type = meta["AssetType"] as? String else { continue }
                let size = meta["com.apple.UnifiedAssetFramework.UnarchivedSize"] ?? meta["_UnarchivedSize"]
                bytes[type, default: 0] += Int64("\(size ?? 0)") ?? 0
            }
            return bytes
        }

        /// The sets Cairn may ask about: known ones only, never an empty list,
        /// since the service reads an empty list as every set.
        static func requestable(_ names: [String]) -> [String] {
            names.filter { name in sets.contains { $0.id == name } }
        }

        enum Outcome: Equatable {
            case done, locked, noAnswer
            case failed(String)
        }

        /// Asks the service to remove each set, one at a time, so one it refuses
        /// doesn't stop the rest. A set whose asset type isn't the one Cairn
        /// knows on this macOS is left alone. Returns what stayed, with why.
        static func remove(_ names: [String]) async -> [(set: String, reason: String)] {
            var stayed: [(set: String, reason: String)] = []
            for name in requestable(names) {
                guard let known = sets.first(where: { $0.id == name }) else { continue }
                guard assetType(of: name) == known.assetType else {
                    stayed.append((name, "not found on this version of macOS, so it was left alone"))
                    continue
                }
                var outcome = await reset(name)
                for delay in [5.0, 15.0] where outcome == .locked {
                    try? await Task.sleep(for: .seconds(delay))
                    outcome = await reset(name)
                }
                switch outcome {
                case .done: break
                case .locked: stayed.append((name, "macOS is still using it. Restart your Mac, then try again."))
                case .noAnswer: stayed.append((name, "macOS didn't answer"))
                case .failed(let reason): stayed.append((name, reason))
                }
            }
            return stayed
        }

        static func reset(_ name: String, timeout: TimeInterval = 120) async -> Outcome {
            guard requestable([name]) == [name] else { return .failed("not one of Apple Intelligence's model sets") }
            guard let interface = runtime("UAFXPCProxyServiceInterface")?.defaultInterface?() ?? nil else {
                return .failed("macOS's asset service isn't available")
            }
            // A proxy answers every selector, so ask the interface itself.
            let operation = NSSelectorFromString("operationWithConfig:completion:")
            let proto = interface.`protocol`
            guard protocol_getMethodDescription(proto, operation, true, true).name != nil
                    || protocol_getMethodDescription(proto, operation, false, true).name != nil else {
                return .failed("macOS's asset service doesn't take this request")
            }
            let connection = NSXPCConnection(machServiceName: service, options: [])
            connection.remoteObjectInterface = interface
            connection.resume()
            return await withCheckedContinuation { continuation in
                let once = Once(connection)
                let finish: @Sendable (Outcome) -> Void = { outcome in
                    guard once.claim() else { return }
                    once.connection.invalidate()
                    continuation.resume(returning: outcome)
                }
                let proxy = connection.remoteObjectProxyWithErrorHandler { finish(AssetService.outcome(of: $0 as NSError)) }
                let request: NSDictionary = ["Operation": "ResetAssetSets", "AssetSets": [name]]
                unsafeBitCast(proxy as AnyObject, to: UAFOperations.self).operation(config: request) { error in
                    finish(error.map { AssetService.outcome(of: $0) } ?? .done)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.noAnswer) }
            }
        }

        private static func outcome(of error: NSError) -> Outcome {
            if error.userInfo["currentLockUsage"] != nil || error.localizedDescription.contains("current locks") { return .locked }
            return .failed(error.localizedDescription)
        }

        /// The first answer wins; it also carries the connection to close, which
        /// is only touched by whichever answer wins.
        private final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            let connection: NSXPCConnection
            init(_ connection: NSXPCConnection) { self.connection = connection }
            func claim() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if done { return false }
                done = true
                return true
            }
        }
    }

    // MARK: - Cairn going in the Bin

    /// Cairn going in the Bin while its profile still keeps Apple Intelligence
    /// off: offer the Undo first, so nobody is left with it blocked and no app
    /// to bring it back. The profile can always be removed in System Settings too.
    @MainActor final class RemovalWatch {
        static let shared = RemovalWatch()
        private var source: DispatchSourceFileSystemObject?
        private var asked = false

        func start() {
            let bundle = Bundle.main.bundleURL
            guard source == nil, bundle.pathExtension == "app", !CommandLine.arguments.contains("--preview-ui") else { return }
            let descriptor = open(bundle.path, O_EVTONLY)
            guard descriptor >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.moved(descriptor) } }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            self.source = source
        }

        private func moved(_ descriptor: Int32) {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let now = fcntl(descriptor, F_GETPATH, &path) == 0 ? String(cString: path) : ""
            guard !asked, now.contains("/.Trash/") || now.contains("/.Trashes/"), Profile.installed().on else { return }
            asked = true
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Turn Apple Intelligence back on first?"
            alert.informativeText = "Cairn turned it off with a profile, and removing Cairn leaves that profile in place. To turn it back on, select \"Cairn: Apple Intelligence off\" in System Settings and click Remove. macOS then downloads the models again when a feature needs them."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Leave it off")
            if alert.runModal() == .alertFirstButtonReturn { Profile.openSettings() }
        }
    }
}

/// The asset service's classes and the objects they hand back. Every member is
/// optional, so a missing one is a nil answer rather than a crash.
@objc private protocol UAFRuntime {
    @objc(defaultManager) optional func defaultManager() -> AnyObject?
    @objc(getAssetSet:) optional func getAssetSet(_ name: String) -> AnyObject?
    @objc(autoAssetType) optional func autoAssetType() -> AnyObject?
    @objc(generateInformationWithError:) optional func generateInformation(_ error: NSErrorPointer) -> AnyObject?
    @objc(latestStatusForClients:error:) optional func latestStatus(forClients name: String, error: NSErrorPointer) -> AnyObject?
    @objc(downloadedFilesystemBytes) optional func downloadedFilesystemBytes() -> Int64
    @objc(defaultInterface) optional func defaultInterface() -> NSXPCInterface?
}

/// The one request Cairn sends; checked against the interface before it goes.
@objc private protocol UAFOperations {
    @objc(operationWithConfig:completion:) func operation(config: NSDictionary, completion: @escaping (NSError?) -> Void)
}
