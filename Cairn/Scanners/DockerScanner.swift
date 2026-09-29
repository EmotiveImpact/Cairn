import Foundation

/// Docker disk reclaim (SPEC §3.x — the developer wedge, tool-mediated). Docker
/// hides its real space inside a Linux VM image (`Docker.raw`), so deletion from
/// the host is meaningless: the only honest reclaim is `docker … prune`, run
/// while the daemon is up. We size with the read-only `docker system df` and then
/// surface graduated, individually-checked prune actions ordered safest →
/// destructive. Container layers and volumes are advice only because they may
/// hold the only copy of application or database state. The host `Docker.raw` is advice-only — pruning frees space INSIDE
/// the VM but the sparse host image only shrinks on a manual disk resize.
struct DockerScanner: CairnScanner {
    let info = CategoryInfo(
        id: "docker",
        title: "Docker",
        subtitle: "Build cache, unused images, stopped containers, volumes",
        systemImage: "shippingbox.fill",
        group: .developer,
        requiresFDA: false
    )

    func scan(_ ctx: ScanContext) async {
        if ctx.isCancelled() { return }

        // Daemon down → we cannot size or prune. One advice card, then stop.
        guard RunningApps.isDockerRunning() else {
            ctx.progress("Docker (not running)")
            ctx.emit(ScanItem(
                url: FileScan.home,
                allocatedSize: 0,
                categoryID: info.id,
                severity: .review,
                isRegenerable: false,
                requiresRunning: true,
                cleanMethod: .adviceOnly,
                note: "Docker isn't running — start Docker Desktop to size and prune reclaimable space",
                volumeURL: FileScan.volumeURL(of: FileScan.home)
            ))
            return
        }

        // Read-only sizing pass. Best-effort — if docker isn't on PATH or the
        // call fails, reclaimable stays unknown (0) and we still offer prunes.
        ctx.progress("docker system df")
        var reclaim = Reclaimable()
        if let result = try? ToolRunner.run("docker", ["system", "df"], timeout: 12), result.ok {
            reclaim = parseSystemDF(result.stdout)
        }

        if ctx.isCancelled() { return }

        // Graduated prune actions, safest first. Each is individually checked;
        // none is pre-selected (all REVIEW or RISKY). Sizes come from the parsed
        // reclaimable column where available, else 0.
        let dockerHome = FileScan.home

        ctx.progress("Build cache")
        ctx.emit(toolItem(
            label: "Docker build cache",
            url: dockerHome.appendingPathComponent(".docker/buildx"),
            severity: .review,
            command: ToolCommand(tool: "docker", arguments: ["builder", "prune", "-f"],
                                 display: "docker builder prune"),
            allocated: reclaim.buildCache,
            note: "Docker build cache — safest to prune; rebuilds on next `docker build`"
        ))

        if ctx.isCancelled() { return }
        ctx.progress("Unused images")
        ctx.emit(toolItem(
            label: "Unused Docker images",
            url: dockerHome.appendingPathComponent(".docker"),
            severity: .review,
            command: ToolCommand(tool: "docker", arguments: ["image", "prune", "-a", "-f"],
                                 display: "docker image prune -a"),
            allocated: reclaim.images,
            note: "Dangling + unreferenced images — re-pulled/rebuilt when needed"
        ))

        if ctx.isCancelled() { return }
        ctx.progress("Stopped containers")
        ctx.emit(toolItem(
            label: "Stopped Docker containers",
            url: dockerHome.appendingPathComponent(".docker"),
            severity: .review,
            command: ToolCommand(tool: "docker", arguments: ["container", "prune", "-f"],
                                 display: "docker container prune", destroysData: true),
            allocated: reclaim.containers,
            note: "Stopped containers may contain unrecoverable writable-layer data. Inspect them in Docker before any manual removal.",
            actionable: false
        ))

        if ctx.isCancelled() { return }
        ctx.progress("System prune (destructive)")
        ctx.emit(toolItem(
            label: "Docker volumes + everything (DESTRUCTIVE)",
            url: dockerHome.appendingPathComponent(".docker"),
            severity: .risky,
            command: ToolCommand(tool: "docker",
                                 arguments: ["system", "prune", "-a", "--volumes", "-f"],
                                 display: "docker system prune -a --volumes",
                                 destroysData: true),
            allocated: reclaim.total,
            note: "Deletes unused images, build cache, networks and named volumes; volume data may be unrecoverable. Cairn will not run this command.",
            actionable: false
        ))

        if ctx.isCancelled() { return }

        // The host VM disk image. Advice-only: pruning frees space INSIDE the VM,
        // but Docker.raw only shrinks on a manual disk resize (which wipes the VM).
        let rawURL = dockerHome.appendingPathComponent(
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        if FileScan.exists(rawURL) {
            ctx.progress("Docker.raw")
            let stats = FileScan.measure(rawURL)
            ctx.emit(ScanItem(
                url: rawURL,
                allocatedSize: stats.allocatedSize,
                itemCount: stats.fileCount,
                latestModified: stats.latestModified,
                categoryID: info.id,
                severity: .risky,
                isRegenerable: false,
                requiresRunning: false,
                cleanMethod: .adviceOnly,
                note: "Pruning frees space INSIDE the VM; the host Docker.raw only shrinks if you resize the disk image in Docker settings (which erases all images/volumes).",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: rawURL)
            ))
        }
    }

    // MARK: - Item construction

    /// Build a tool-mediated prune item. Size is the parsed reclaimable bytes (or
    /// 0 when unknown); never trash-based, so we construct ScanItem directly to
    /// bypass makeItem's min-size skip and filesystem measurement.
    private func toolItem(
        label: String,
        url: URL,
        severity: Severity,
        command: ToolCommand,
        allocated: Int64,
        note: String,
        actionable: Bool = true
    ) -> ScanItem {
        ScanItem(
            url: url,
            allocatedSize: max(0, allocated),
            categoryID: info.id,
            severity: severity,
            isRegenerable: actionable,
            requiresRunning: true,
            cleanMethod: actionable ? .tool(command) : .adviceOnly,
            note: "\(label) — \(note)",
            volumeURL: FileScan.volumeURL(of: FileScan.home)
        )
    }

    // MARK: - `docker system df` parsing

    /// Reclaimable bytes broken out by `docker system df` section.
    private struct Reclaimable {
        var images: Int64 = 0
        var containers: Int64 = 0
        var volumes: Int64 = 0
        var buildCache: Int64 = 0
        /// Conservative total for the destructive `system prune`.
        var total: Int64 { images + containers + volumes + buildCache }
    }

    /// Best-effort parse of the default (non-verbose) `docker system df` table:
    ///
    ///     TYPE            TOTAL  ACTIVE  SIZE      RECLAIMABLE
    ///     Images          12     3       4.21GB    3.1GB (73%)
    ///     Containers      5      1       12.3MB    8MB (65%)
    ///     Local Volumes   4      2       1.2GB     900MB (75%)
    ///     Build Cache     30     0       2.5GB     2.5GB
    ///
    /// The RECLAIMABLE column is the trailing size token (optionally followed by a
    /// "(NN%)"). We key rows off the leading TYPE text, which is locale-stable.
    private func parseSystemDF(_ output: String) -> Reclaimable {
        var r = Reclaimable()
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            let lower = line.lowercased()
            guard let bytes = reclaimableBytes(in: line) else { continue }
            if lower.hasPrefix("images") {
                r.images = bytes
            } else if lower.hasPrefix("containers") {
                r.containers = bytes
            } else if lower.hasPrefix("local volumes") || lower.hasPrefix("volumes") {
                r.volumes = bytes
            } else if lower.hasPrefix("build cache") {
                r.buildCache = bytes
            }
        }
        return r
    }

    /// Extract the RECLAIMABLE size from a `docker system df` row: the last
    /// size-shaped token (e.g. "3.1GB"), ignoring a trailing "(NN%)".
    private func reclaimableBytes(in line: String) -> Int64? {
        // Drop any trailing percentage group like "(73%)".
        var fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        fields.removeAll { $0.hasPrefix("(") || $0.hasSuffix("%)") || $0.hasSuffix("%") }
        // Walk from the end for the last token that parses as a size.
        for token in fields.reversed() {
            if let bytes = parseSize(token) { return bytes }
        }
        return nil
    }

    /// Parse a Docker-style human size ("0B", "12.3MB", "4.21GB", "900kB", "1.5TiB")
    /// into bytes. Docker uses decimal (SI) units in `system df`; we accept binary
    /// suffixes too for robustness.
    private func parseSize(_ token: String) -> Int64? {
        let s = token.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // Split numeric prefix from unit suffix.
        var numEnd = s.startIndex
        var seenDigit = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isNumber { seenDigit = true; numEnd = s.index(after: i) }
            else if c == "." || c == "," { numEnd = s.index(after: i) }
            else { break }
            i = s.index(after: i)
        }
        guard seenDigit else { return nil }

        let numPart = s[s.startIndex..<numEnd].replacingOccurrences(of: ",", with: "")
        guard let value = Double(numPart) else { return nil }
        let unit = s[numEnd...].trimmingCharacters(in: .whitespaces).uppercased()

        let multiplier: Double
        switch unit {
        case "", "B":               multiplier = 1
        case "KB", "K", "KIB":      multiplier = 1_000
        case "MB", "M", "MIB":      multiplier = 1_000_000
        case "GB", "G", "GIB":      multiplier = 1_000_000_000
        case "TB", "T", "TIB":      multiplier = 1_000_000_000_000
        case "PB", "P", "PIB":      multiplier = 1_000_000_000_000_000
        default: return nil
        }
        return Int64((value * multiplier).rounded())
    }
}
