import Foundation

/// Moving Docker Desktop's disk. Docker warns against moving the file in
/// Finder, because it loses track of it, so Cairn moves the folder and then
/// points Docker's own "Disk image location" setting (DataFolder) at it.
/// The original is only removed once Docker has started from the drive.
enum DockerMove {
    static let groupFolder = FileScan.home.appendingPathComponent("Library/Group Containers/group.com.docker")
    static let defaultDataFolder = FileScan.home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data")
    static let cli = "/Applications/Docker.app/Contents/Resources/bin/docker"
    private static let key = "DataFolder"

    /// Newer Docker Desktop keeps settings in settings-store.json; older
    /// versions used settings.json with a lower-case key.
    static func settingsFile() -> (URL, String)? {
        let store = groupFolder.appendingPathComponent("settings-store.json")
        if FileManager.default.fileExists(atPath: store.path) { return (store, key) }
        let legacy = groupFolder.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: legacy.path) { return (legacy, "dataFolder") }
        return nil
    }

    static var installed: Bool { FileManager.default.fileExists(atPath: "/Applications/Docker.app") }

    /// Where Docker keeps its disk now.
    static func currentDataFolder() -> URL {
        guard let (file, name) = settingsFile(), let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json[name] as? String, !path.isEmpty else { return defaultDataFolder }
        return URL(fileURLWithPath: path)
    }

    /// Changes only the DataFolder entry; every other setting is kept as it
    /// was. Nil puts Docker back on its default location.
    static func setDataFolder(_ path: String?) throws {
        guard let (file, name) = settingsFile() else {
            throw Relocation.Failure(message: "Docker's settings file was not found. Open Docker once, quit it, then try again.")
        }
        guard let data = try? Data(contentsOf: file),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Relocation.Failure(message: "Docker's settings could not be read, so Cairn left them alone.")
        }
        if let path { json[name] = path } else { json.removeValue(forKey: name) }
        let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: file, options: .atomic)
    }

    static func running() -> Bool {
        ["com.docker.backend", "com.docker.virtualization", "Docker Desktop"].contains { name in
            (try? ToolRunner.runExecutable("/usr/bin/pgrep", ["-x", name], timeout: 3))?.ok == true
        }
    }

    /// Asks Docker to quit and waits up to a minute for it to stop.
    static func quit() -> Bool {
        _ = try? ToolRunner.runExecutable("/usr/bin/osascript", ["-e", "quit app \"Docker\""], timeout: 20)
        for _ in 0..<30 {
            if !running() { return true }
            Thread.sleep(forTimeInterval: 2)
        }
        return !running()
    }

    /// Opens Docker and waits for its engine to answer, up to three minutes.
    static func startAndCheck() -> Bool {
        _ = try? ToolRunner.runExecutable("/usr/bin/open", ["-a", "Docker"], timeout: 15)
        for _ in 0..<60 {
            Thread.sleep(forTimeInterval: 3)
            if (try? ToolRunner.runExecutable(cli, ["info", "--format", "{{.ServerVersion}}"], timeout: 10))?.ok == true { return true }
        }
        return false
    }

    /// Copy and check, point Docker at the copy, start Docker and wait for it
    /// to answer, then remove the original. If Docker does not start, its
    /// setting is put back and the drive copy removed; the original was
    /// never touched.
    static func move(from source: URL, to destination: URL, cancel: CancelBox,
                     destinationValid: () -> Bool, progress: (Int64) -> Void) throws -> Relocation.Inventory {
        guard settingsFile() != nil else { throw Relocation.Failure(message: "Docker's settings file was not found. Open Docker once, quit it, then try again.") }
        guard !running() || quit() else { throw Relocation.Failure(message: "Docker did not quit. Quit it from its menu, then try again.") }
        let previous = currentDataFolder()
        guard previous.standardizedFileURL == source.standardizedFileURL else {
            throw Relocation.Failure(message: "Docker's disk has moved since Cairn looked. Rescan and try again.")
        }
        let copied: Relocation.Inventory
        do {
            copied = try Relocation.copyTree(from: source, to: destination, cancel: cancel, destinationValid: destinationValid, progress: progress)
        } catch {
            Relocation.discardPartial(for: destination)
            throw error
        }
        func undo(_ reason: String) -> Relocation.Failure {
            _ = quit()
            try? setDataFolder(previous == defaultDataFolder ? nil : previous.path)
            try? FileManager.default.removeItem(at: destination)
            return Relocation.Failure(message: reason + " Docker was put back as it was.")
        }
        do { try setDataFolder(destination.path) } catch { throw undo("Docker's setting could not be changed.") }
        guard startAndCheck() else { throw undo("Docker did not start from the drive.") }
        try FileManager.default.removeItem(at: source)
        return copied
    }

    /// The reverse: copy back, point Docker home, check it starts, then
    /// remove the drive copy.
    static func bringBack(to source: URL, from destination: URL, cancel: CancelBox,
                          destinationValid: () -> Bool, progress: (Int64) -> Void) throws -> Relocation.Inventory {
        guard !running() || quit() else { throw Relocation.Failure(message: "Docker did not quit. Quit it from its menu, then try again.") }
        guard !Relocation.exists(source) else { throw Relocation.Failure(message: "Something is already at \(source.path). Nothing was replaced.") }
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        let copied = try Relocation.copyTree(from: destination, to: source, cancel: cancel, destinationValid: destinationValid, progress: progress)
        do { try setDataFolder(source == defaultDataFolder ? nil : source.path) } catch {
            try? FileManager.default.removeItem(at: source)
            throw Relocation.Failure(message: "Docker's setting could not be changed. It is still on the drive.")
        }
        guard startAndCheck() else {
            _ = quit()
            try? setDataFolder(destination.path)
            try? FileManager.default.removeItem(at: source)
            throw Relocation.Failure(message: "Docker did not start on this Mac, so it was left on the drive.")
        }
        if destinationValid() { try? FileManager.default.removeItem(at: destination) }
        return copied
    }
}
