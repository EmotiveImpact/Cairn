import Foundation

/// Installed language runtimes managed by per-user version managers — nvm, asdf,
/// mise, pyenv, rbenv — plus conda environments and the conda package cache
/// (SPEC §3.1, developer wedge). These live under plain user dirs (0700) → no
/// Full Disk Access needed.
///
/// Every installed version is the ONLY local copy of that runtime: removing it
/// forces a (often slow) re-download/recompile, and a version may be pinned by a
/// project's `.nvmrc` / `.tool-versions` / `.python-version` / `.ruby-version`.
/// So everything here is REVIEW and never pre-selected. We prefer the manager's
/// own `uninstall` (which also rewrites shims) but `.trash` is acceptable for v1.
/// conda environments are irreversible once removed; the conda package cache is
/// pruned via `conda clean --all`, never rm.
struct LanguageRuntimesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "runtimes",
        title: "Language Runtimes",
        subtitle: "nvm, asdf, mise, pyenv, rbenv versions; conda envs & package cache",
        systemImage: "cube.box.fill",
        group: .developer,
        requiresFDA: false
    )

    // MARK: - Version-manager layouts

    /// A version manager whose installed runtimes are laid out as either a flat
    /// list of version dirs (`root/<version>`) or a two-level `root/<tool>/<version>`.
    private struct Manager {
        let name: String                // "nvm", "asdf", "mise", "pyenv", "rbenv"
        let uninstall: String           // the command to prefer, e.g. "nvm uninstall"
        let root: URL                   // directory holding the versions
        let twoLevel: Bool              // true → root/<tool>/<version>; false → root/<version>
    }

    private var managers: [Manager] {
        let home = FileScan.home
        return [
            Manager(name: "nvm", uninstall: "nvm uninstall",
                    root: home.appendingPathComponent(".nvm/versions/node"), twoLevel: false),
            Manager(name: "asdf", uninstall: "asdf uninstall",
                    root: home.appendingPathComponent(".asdf/installs"), twoLevel: true),
            Manager(name: "mise", uninstall: "mise uninstall",
                    root: home.appendingPathComponent(".local/share/mise/installs"), twoLevel: true),
            Manager(name: "pyenv", uninstall: "pyenv uninstall",
                    root: home.appendingPathComponent(".pyenv/versions"), twoLevel: false),
            Manager(name: "rbenv", uninstall: "rbenv uninstall",
                    root: home.appendingPathComponent(".rbenv/versions"), twoLevel: false),
        ]
    }

    func scan(_ ctx: ScanContext) async {
        // 1) Version managers — one REVIEW, trashable item per installed version.
        for mgr in managers {
            if ctx.isCancelled() { return }
            guard FileScan.exists(mgr.root) else { continue }
            ctx.progress(mgr.name)

            for versionDir in versionDirs(in: mgr) {
                if ctx.isCancelled() { return }
                let version = versionLabel(for: versionDir, manager: mgr)
                if let item = makeItem(
                    at: versionDir,
                    severity: .review,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: true,
                    cleanMethod: .trash,
                    note: "\(mgr.name) \(version) — prefer '\(mgr.uninstall)'; don't remove a version pinned by a project",
                    selectedIfSafe: false
                ) {
                    ctx.emit(item)
                }
            }
        }

        // 2) conda environments — one REVIEW, trashable item per env. Irreversible.
        let condaRoots = [
            FileScan.home.appendingPathComponent("miniconda3"),
            FileScan.home.appendingPathComponent("anaconda3"),
        ]
        for condaRoot in condaRoots {
            if ctx.isCancelled() { return }
            let envsDir = condaRoot.appendingPathComponent("envs")
            guard FileScan.exists(envsDir), let envs = FileScan.children(of: envsDir) else { continue }
            ctx.progress("conda envs (\(condaRoot.lastPathComponent))")

            for env in envs {
                if ctx.isCancelled() { return }
                // Skip symlinks / non-directories defensively.
                let rv = try? env.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if rv?.isSymbolicLink == true { continue }
                if rv?.isDirectory != true { continue }
                if let item = makeItem(
                    at: env,
                    severity: .review,
                    minSize: ctx.minSizeBytes,
                    isRegenerable: false,
                    cleanMethod: .trash,
                    note: "conda env '\(env.lastPathComponent)' — irreversible, may be the only copy",
                    selectedIfSafe: false
                ) {
                    ctx.emit(item)
                }
            }
        }

        // 3) conda package cache — ONE review-only item per install. It may be
        //    hard-linked into environments. Surface the size for inspection but
        //    never infer that the scanned path is conda's configured active root.
        for condaRoot in condaRoots {
            if ctx.isCancelled() { return }
            let pkgs = condaRoot.appendingPathComponent("pkgs")
            guard FileScan.exists(pkgs) else { continue }
            ctx.progress("conda pkgs (\(condaRoot.lastPathComponent))")

            let stats = FileScan.measure(pkgs)
            guard stats.allocatedSize >= ctx.minSizeBytes else { continue }
            let clean = ToolCommand(tool: "conda", arguments: ["clean", "--all", "-y"], display: "conda clean --all -y")
            ctx.emit(ScanItem(
                url: pkgs,
                allocatedSize: stats.allocatedSize,
                itemCount: stats.fileCount,
                latestModified: stats.latestModified,
                categoryID: info.id,
                severity: .review,
                isRegenerable: true,
                requiresQuitBundleIDs: [],
                requiresRunning: false,
                cleanMethod: .tool(clean),
                note: "Conda package cache — pruned with conda clean, which keeps packages used by environments",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: pkgs),
                selected: false
            ))
        }
    }

    // MARK: - helpers

    /// The list of installed-version directories for a manager, handling both the
    /// flat (`root/<version>`) and two-level (`root/<tool>/<version>`) layouts.
    private func versionDirs(in mgr: Manager) -> [URL] {
        guard let top = FileScan.children(of: mgr.root) else { return [] }
        let topDirs = top.filter { isRealDirectory($0) }
        if !mgr.twoLevel { return topDirs }

        var result: [URL] = []
        for toolDir in topDirs {
            guard let versions = FileScan.children(of: toolDir) else { continue }
            result.append(contentsOf: versions.filter { isRealDirectory($0) })
        }
        return result
    }

    /// A human-readable version label. For two-level managers this is "<tool> <version>"
    /// (e.g. "nodejs 20.11.0"); for flat managers it is just the version dir name.
    private func versionLabel(for versionDir: URL, manager mgr: Manager) -> String {
        if mgr.twoLevel {
            let tool = versionDir.deletingLastPathComponent().lastPathComponent
            return "\(tool) \(versionDir.lastPathComponent)"
        }
        return versionDir.lastPathComponent
    }

    /// True only for a real directory (not a symlink, not iCloud stub). We never
    /// follow symlinks — a version dir that is a symlink (e.g. nvm aliases) points
    /// at another real version and would double-count.
    private func isRealDirectory(_ url: URL) -> Bool {
        guard let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else { return false }
        if rv.isSymbolicLink == true { return false }
        return rv.isDirectory == true
    }
}
