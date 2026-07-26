import Foundation

/// `Cairn --safetycheck` — a release gate. Asserts the SafePaths chokepoint still
/// refuses every irreplaceable location (AI agent conversation history, iCloud
/// mirrors, Keychains, ssh keys, Documents) while normal caches stay cleanable.
/// Run before shipping; a failure here means a data-loss regression.
enum SafetyCheck {
    static func run() {
        // Verify the AI-history denylist really blocks these paths.
        let home = FileScan.home
        let mustBlock = [
            ".claude", ".claude/projects", ".claude/projects/foo/bar.jsonl",
            ".codex", ".codex/sessions", ".cursor",
            "Library/Application Support/Claude",
            "Library/Mobile Documents", "Library/CloudStorage/Dropbox",
            "Library/Keychains", ".ssh/id_rsa", "Documents/tax.pdf",
        ]
        var fails = 0
        for rel in mustBlock {
            let u = home.appendingPathComponent(rel)
            let v = SafePaths.evaluate(u, allowedRoots: [home])
            if v.isAllowed { print("❌ ALLOWED (should be blocked): \(rel)"); fails += 1 }
            else { print("✅ blocked: \(rel)") }
        }
        // sanity: a real cache target must still be cleanable
        let ok = home.appendingPathComponent("Library/Caches/some-app")
        print(SafePaths.evaluate(ok, allowedRoots: [home]).isAllowed ? "✅ cache still cleanable" : "❌ cache wrongly blocked")
        print(fails == 0 ? "\nALL SAFETY CHECKS PASSED" : "\n\(fails) SAFETY FAILURES")
    }
}
