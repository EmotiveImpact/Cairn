import Foundation

/// Uses only a disposable 64 MiB fixture. Exercises production hashing with
/// no retained result list, no view, and no personal file reads.
enum HashMemoryCheck {
    static func run() async {
        let result = await Task.detached(priority: .utility) { () -> Bool in
            let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("cairn-hash-memory-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                try autoreleasepool {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    let writer = try FileHandle(forWritingTo: url)
                    defer { try? writer.close() }
                    let chunk = Data(repeating: 0x5a, count: 1_048_576)
                    for _ in 0..<64 { try writer.write(contentsOf: chunk) }
                }
                let baseline = MemoryWatch.footprintBytes()
                var peak = baseline
                var digest: String?
                var success = true
                for pass in 1...8 {
                    let fingerprint = DupHash.fingerprint(url, shouldCancel: {
                        peak = max(peak, MemoryWatch.footprintBytes())
                        return peak > baseline + 384 * 1_048_576
                    })
                    if let fingerprint {
                        if let digest { success = success && digest == fingerprint.digest }
                        digest = fingerprint.digest
                        success = success && fingerprint.digest == "103f23a15401a701b73587902f16e3b5b3bf38a039d5c94b675a9a8e84dbd5b5"
                    } else { success = false }
                    print("Hash pass \(pass): footprint \(MemoryWatch.footprintBytes()/1_048_576) MiB; RSS \(MemoryWatch.residentBytes()/1_048_576) MiB; completed \(fingerprint != nil)")
                    if !success { break }
                }
                let growth = peak - baseline
                print("HASH MEMORY: baseline \(baseline/1_048_576) MiB; peak \(peak/1_048_576) MiB; growth \(growth/1_048_576) MiB; retained results: one digest")
                success = success && growth < 64 * 1_048_576
                print(success ? "HASH MEMORY PASSED" : "HASH MEMORY FAILED")
                guard success else { return false }
                for pass in 1...2 {
                    let directory = url.appendingPathExtension("copy-\(pass)")
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let copied = try ArchiveCopy.copy(source: url, directory: directory,
                        cancel: CancelBox(), destinationValid: { true }, progress: { _ in })
                    success = success && copied.1 == 64 * 1_048_576 && copied.2 == digest
                    success = success && MemoryWatch.footprintBytes() < baseline + 64 * 1_048_576
                    print("Copy pass \(pass): footprint \(MemoryWatch.footprintBytes()/1_048_576) MiB; verified \(copied.2 == digest)")
                }
                success = success && DupHash.fingerprint(url, shouldCancel: { true }) == nil
                var changed = false
                let changing = DupHash.fingerprint(url, shouldCancel: {
                    if !changed {
                        changed = true
                        if let writer = try? FileHandle(forWritingTo: url) {
                            try? writer.seek(toOffset: 32 * 1_048_576)
                            try? writer.write(contentsOf: Data([0x01]))
                            try? writer.close()
                        }
                    }
                    return false
                })
                success = success && changing == nil
                print(success ? "COPY MEMORY / HASH CORRECTNESS / CANCELLATION / MID-READ CHANGE PASSED" : "COPY OR HASH SAFETY FAILED")
                return success
            } catch { print("Hash fixture failed: \(error)"); return false }
        }.value
        exit(result ? 0 : 1)
    }
}
