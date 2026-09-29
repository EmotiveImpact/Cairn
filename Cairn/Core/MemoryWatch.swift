import Foundation

/// A local, always-on memory recorder.
///
/// The runaway-memory bug only shows up under real use — long sessions, real
/// scans, real navigation — and never reproduced reliably in a short scripted
/// run. Rather than guess, the app records its own resident size alongside what
/// it was doing at the time, so a spike can be traced to the exact page and scan
/// that caused it.
///
/// Local only. Writes to `~/Library/Logs/Cairn-memory.log`, never leaves the Mac,
/// and is capped so it can't grow without bound. Nothing is sent anywhere — the
/// no-telemetry promise still holds.
enum MemoryWatch {
    /// Includes compressed memory charged to the process; RSS alone can fall
    /// while the process is exhausting memory and forcing compression/swap.
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
    private static let logURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Cairn-memory.log")

    // AppShell can be reconstructed when its window is reopened. Keep exactly
    // one recorder, and refresh the provider to reflect the current shell.
    @MainActor private static var recorder: Task<Void, Never>?
    @MainActor private static var stateProvider: (@MainActor () -> String)?

    /// Resident size of this process, in bytes.
    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    /// Samples every 3s. Writes a line when memory moves meaningfully (±100 MB),
    /// every 60s regardless, and always once past 2 GB — so the run-up to a
    /// blow-up is recorded at full detail rather than averaged away.
    /// `state` describes what the app is doing, evaluated on the main actor.
    @MainActor
    static func start(state: @escaping @MainActor () -> String) {
        stateProvider = state
        guard recorder == nil else { return }
        recorder = Task {
            var lastLoggedMB = 0
            var tick = 0
            append("──── session start \(stamp()) ────")
            while !Task.isCancelled {
                let mb = Int(footprintBytes() / 1_048_576)
                let moved = abs(mb - lastLoggedMB) >= 100
                let heartbeat = tick % 20 == 0          // 20 × 3s = 60s
                if moved || heartbeat || mb > 2048 {
                    append("\(stamp())  footprint \(mb) MB  RSS \(residentBytes() / 1_048_576) MB  \(stateProvider?() ?? "window=closed")")
                    lastLoggedMB = mb
                }
                tick += 1
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    @MainActor
    static func stop() {
        recorder?.cancel()
        recorder = nil
        stateProvider = nil
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private static func append(_ line: String) {
        let text = line + "\n"
        guard let data = text.data(using: .utf8) else { return }
        let fm = FileManager.default
        // Roll the file rather than let it grow forever.
        if let size = try? fm.attributesOfItem(atPath: logURL.path)[.size] as? Int, size > 2_000_000 {
            try? fm.removeItem(at: logURL)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
}
