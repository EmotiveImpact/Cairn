import Foundation

/// Computed regenerability for JS/env trees (SPEC §5.4). SAFE is granted ONLY on
/// a positive result; anything inconclusive or non-regenerable is downgraded to
/// REVIEW (never silently SAFE — fixes the prototype's sibling-lockfile-=-SAFE
/// heuristic, BUG-012-class).
enum Regenerability {
    struct Result {
        var isRegenerable: Bool
        var severity: Severity
        var note: String
    }

    private static let lockfiles = ["pnpm-lock.yaml", "yarn.lock", "package-lock.json", "bun.lockb", "npm-shrinkwrap.json"]

    /// Evaluate a `node_modules` directory given its containing project dir.
    static func evaluateNodeModules(projectDir: URL) -> Result {
        let fm = FileManager.default
        let nm = projectDir.appendingPathComponent("node_modules")

        // npm-link symlinks inside node_modules → not reproduced by install.
        if hasLinkSymlinks(nm) {
            return Result(isRegenerable: false, severity: .review,
                          note: "Contains npm-link symlinks — reinstall won't reproduce them")
        }

        // patch-package patches → patched state may not reproduce identically.
        if fm.fileExists(atPath: projectDir.appendingPathComponent("patches").path) {
            return Result(isRegenerable: false, severity: .review,
                          note: "patch-package patches present — verify before removing")
        }

        // A resolvable lockfile (here or at a workspace root) → regenerable.
        if let root = workspaceRootWithLockfile(startingAt: projectDir) {
            let where_ = (root == projectDir) ? "this project" : "workspace root \(root.lastPathComponent)"
            // file:/link: protocol deps → downgrade.
            if manifestHasLocalDeps(projectDir) {
                return Result(isRegenerable: false, severity: .review,
                              note: "Has file:/link: dependencies — reinstall may not reproduce")
            }
            return Result(isRegenerable: true, severity: .safe,
                          note: "Reinstalls from lockfile (\(where_))")
        }

        // No resolvable lockfile and not a workspace member → could be vendored.
        return Result(isRegenerable: false, severity: .review,
                      note: "No lockfile found — may not be reproducible; review before removing")
    }

    // MARK: - helpers

    private static func hasLinkSymlinks(_ nodeModules: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: nodeModules, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { return false }
        for e in entries.prefix(400) {   // bounded probe
            if (try? e.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return true }
        }
        return false
    }

    /// Walk up to ~6 levels looking for a lockfile (here or at a workspace root).
    private static func workspaceRootWithLockfile(startingAt dir: URL) -> URL? {
        let fm = FileManager.default
        var current = dir
        for _ in 0..<6 {
            for lf in lockfiles where fm.fileExists(atPath: current.appendingPathComponent(lf).path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent == current || parent == SafePaths.home { break }
            current = parent
        }
        return nil
    }

    private static func manifestHasLocalDeps(_ projectDir: URL) -> Bool {
        let pkg = projectDir.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: pkg),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        for key in ["dependencies", "devDependencies", "optionalDependencies"] {
            if let deps = json[key] as? [String: Any] {
                for (_, v) in deps {
                    if let s = v as? String, s.hasPrefix("file:") || s.hasPrefix("link:") { return true }
                }
            }
        }
        return false
    }
}
