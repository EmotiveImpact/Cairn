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
        let root = workspaceRootWithLockfile(startingAt: projectDir)

        // A package linked in by hand (npm link, yarn link, pnpm link --global)
        // points outside the project, and an install won't bring it back. The
        // package managers' own links stay inside the folder that holds the
        // lockfile (pnpm's .pnpm folder, workspace packages) or in pnpm's own
        // store, and an install makes them again, so those are fine.
        if let linked = linkPointingOutside(nm, allowed: [root ?? projectDir] + pnpmStores(nm)) {
            return Result(isRegenerable: false, severity: .review,
                          note: "\(linked) is linked from outside this project, so reinstalling won't bring it back")
        }

        // patch-package patches → patched state may not reproduce identically.
        if fm.fileExists(atPath: projectDir.appendingPathComponent("patches").path) {
            return Result(isRegenerable: false, severity: .review,
                          note: "patch-package patches present — verify before removing")
        }

        // A resolvable lockfile (here or at a workspace root) → regenerable.
        if let root {
            let where_ = (root == projectDir) ? "this project" : "workspace root \(root.lastPathComponent)"
            // file:/link:/portal: protocol deps → downgrade.
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

    /// The first package in `node_modules` (or inside an @scope folder) that is
    /// a link to somewhere outside every allowed folder, or nil. Bounded probe.
    private static func linkPointingOutside(_ nodeModules: URL, allowed: [URL]) -> String? {
        let fm = FileManager.default
        let bases = allowed.map { $0.resolvingSymlinksInPath().path }
        func inside(_ path: String) -> Bool {
            bases.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }
        func isLink(_ url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        }
        func entries(_ dir: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])) ?? []
        }
        var budget = 2_000
        var queue = [(nodeModules, "")]
        while !queue.isEmpty {
            let (dir, scope) = queue.removeFirst()
            for e in entries(dir) {
                budget -= 1
                if budget < 0 { return nil }
                let name = e.lastPathComponent
                guard isLink(e) else {
                    if scope.isEmpty && name.hasPrefix("@") { queue.append((e, name + "/")) }
                    continue
                }
                guard let dest = try? fm.destinationOfSymbolicLink(atPath: e.path) else { return scope + name }
                let target = dest.hasPrefix("/") ? URL(fileURLWithPath: dest)
                                                 : e.deletingLastPathComponent().appendingPathComponent(dest)
                if !inside(target.standardizedFileURL.resolvingSymlinksInPath().path) { return scope + name }
            }
        }
        return nil
    }

    /// Where pnpm keeps the real package folders when they live outside the
    /// project (a custom virtual store, or the shared global one), as recorded
    /// in node_modules/.modules.yaml. Links into these an install makes again.
    private static func pnpmStores(_ nodeModules: URL) -> [URL] {
        guard let text = try? String(contentsOf: nodeModules.appendingPathComponent(".modules.yaml"), encoding: .utf8)
        else { return [] }
        var stores: [URL] = []
        for line in text.split(separator: "\n") {
            for key in ["virtualStoreDir:", "storeDir:"] where line.hasPrefix(key) {
                let raw = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                guard !raw.isEmpty else { continue }
                let url = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : nodeModules.appendingPathComponent(raw)
                // A store is never the disk, the home folder or any folder around
                // the project, which would let every link count as pnpm's own.
                let path = url.resolvingSymlinksInPath().path
                let here = nodeModules.resolvingSymlinksInPath().path
                if path != "/" && !here.hasPrefix(path.hasSuffix("/") ? path : path + "/") { stores.append(url) }
            }
        }
        return stores
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
                    if let s = v as? String, s.hasPrefix("file:") || s.hasPrefix("link:") || s.hasPrefix("portal:") { return true }
                }
            }
        }
        return false
    }
}
