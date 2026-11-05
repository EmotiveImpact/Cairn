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

        // A package linked in by hand (npm link, yarn link, pnpm link --global,
        // or a link to a folder nobody declared) won't come back with an install.
        if let root, let linked = handMadeLink(nm, projectDir: projectDir, root: root) {
            return Result(isRegenerable: false, severity: .review,
                          note: "\(linked) was linked in by hand, so reinstalling won't bring it back")
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

    /// The first package in `node_modules` (or inside an @scope folder) that was
    /// linked in by hand, or nil. A link an install makes again points into a
    /// package manager's own folder (a `node_modules` inside the lockfile's
    /// folder, such as pnpm's `.pnpm`, or pnpm's store), or to a workspace
    /// package or declared dependency inside the lockfile's folder. Anything
    /// else is by hand: `npm link` goes through npm's global folder, and a link
    /// to a sibling folder nobody declared is gone after a fresh install. The
    /// link itself is judged, so a package linked through the global folder
    /// can't pass for a local one, and the end of its chain must also stay in
    /// the project or pnpm's store. Bounded probe.
    private static func handMadeLink(_ nodeModules: URL, projectDir: URL, root: URL) -> String? {
        let fm = FileManager.default
        let rootPath = root.resolvingSymlinksInPath().path
        let stores = pnpmStores(nodeModules).map { $0.resolvingSymlinksInPath().path }
        let declared = declaredDependencies(projectDir)
        let members = workspacePatterns(root)
        func within(_ path: String, _ base: String) -> Bool {
            path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
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
                let linkName = scope + name
                guard let dest = try? fm.destinationOfSymbolicLink(atPath: e.path) else { return linkName }
                let target = (dest.hasPrefix("/") ? URL(fileURLWithPath: dest)
                                                  : e.deletingLastPathComponent().appendingPathComponent(dest)).standardizedFileURL
                // Spell the folder the link names the same way as the roots,
                // without following the link's own target any further.
                let path = target.deletingLastPathComponent().resolvingSymlinksInPath()
                    .appendingPathComponent(target.lastPathComponent).path
                // The whole chain must also end inside the project or pnpm's store,
                // so a local alias to a folder elsewhere can't pass either.
                let end = target.resolvingSymlinksInPath().path
                guard within(end, rootPath) || stores.contains(where: { within(end, $0) }) else { return linkName }
                if stores.contains(where: { within(path, $0) }) { continue }
                guard within(path, rootPath) else { return linkName }
                let relative = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if relative.split(separator: "/").contains("node_modules") { continue }
                if declared.contains(linkName) || members(relative) { continue }
                return linkName
            }
        }
        return nil
    }

    /// Every package the project's package.json asks for, by name.
    private static func declaredDependencies(_ projectDir: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: projectDir.appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var names = Set<String>()
        for key in ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"] {
            if let deps = json[key] as? [String: Any] { names.formUnion(deps.keys) }
        }
        return names
    }

    /// Whether a folder (relative to the workspace root) is one of its
    /// workspace packages, from package.json "workspaces" or
    /// pnpm-workspace.yaml "packages". `*` matches within one folder, `**`
    /// across any number of folders (including none before a `/`), and a
    /// pattern starting with `!` leaves folders out.
    private static func workspacePatterns(_ root: URL) -> (String) -> Bool {
        var globs: [String] = []
        if let data = try? Data(contentsOf: root.appendingPathComponent("package.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let list = json["workspaces"] as? [String] { globs += list }
            if let object = json["workspaces"] as? [String: Any], let list = object["packages"] as? [String] { globs += list }
        }
        if let text = try? String(contentsOf: root.appendingPathComponent("pnpm-workspace.yaml"), encoding: .utf8) {
            var inPackages = false
            for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if raw.hasPrefix("packages:") { inPackages = true; continue }
                guard inPackages else { continue }
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard line.hasPrefix("-") else { if !raw.hasPrefix(" ") && !raw.hasPrefix("\t") { inPackages = false }; continue }
                globs.append(line.dropFirst().trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\"")))
            }
        }
        func regex(_ glob: String) -> NSRegularExpression? {
            var g = glob
            while g.hasPrefix("./") { g.removeFirst(2) }
            while g.hasSuffix("/") { g.removeLast() }
            guard !g.isEmpty else { return nil }
            var pattern = "^"
            var chars = Array(g)[...]
            while let c = chars.first {
                chars = chars.dropFirst()
                if c == "*" {
                    if chars.first == "*" {
                        chars = chars.dropFirst()
                        // `**/` also matches no folder at all, so packages/**/ui matches packages/ui.
                        if chars.first == "/" { chars = chars.dropFirst(); pattern += "(?:.*/)?" } else { pattern += ".*" }
                    } else {
                        pattern += "[^/]*"
                    }
                } else if c == "?" {
                    pattern += "[^/]"
                } else {
                    pattern += NSRegularExpression.escapedPattern(for: String(c))
                }
            }
            return try? NSRegularExpression(pattern: pattern + "$")
        }
        let include = globs.filter { !$0.hasPrefix("!") }.compactMap(regex)
        let exclude = globs.filter { $0.hasPrefix("!") }.compactMap { regex(String($0.dropFirst())) }
        func matches(_ list: [NSRegularExpression], _ path: String) -> Bool {
            list.contains { $0.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil }
        }
        return { path in matches(include, path) && !matches(exclude, path) }
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
