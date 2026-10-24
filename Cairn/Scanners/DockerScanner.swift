import Foundation

/// Docker disk reclaim (SPEC §3.x — the developer wedge, tool-mediated). Docker
/// hides its real space inside a Linux VM image (`Docker.raw`), so deletion from
/// the host is meaningless: the reclaim is `docker … prune`, run while the
/// daemon is up. We size with the read-only `docker system df` and offer
/// graduated prune actions, safest first. The host `Docker.raw` is advice-only — pruning frees space INSIDE
/// the VM, which current Docker Desktop then returns to the Mac. OrbStack and
/// Colima disks are sized as advice with their own way to give space back.
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

        // OrbStack and Colima keep their own VM disks. Sized whether or not
        // they are running, so their space is never invisible.
        emitOtherVMDisks(ctx)
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
                note: "Docker isn't running — start Docker Desktop, OrbStack or Colima to size and prune reclaimable space",
                volumeURL: FileScan.volumeURL(of: FileScan.home)
            ))
            return
        }

        // Read-only sizing pass. Best-effort — if docker isn't on PATH or the
        // call fails, reclaimable stays unknown (0) and the advice remains visible.
        // When Docker did answer, a row with nothing to reclaim is left out.
        ctx.progress("docker system df")
        var reclaim = Reclaimable()
        var sized = false
        if let result = try? ToolRunner.run("docker", ["system", "df"], timeout: 12), result.ok {
            reclaim = parseSystemDF(result.stdout)
            sized = true
        }
        let emitPrune: (ScanItem) -> Void = { item in
            if !sized || item.allocatedSize > 0 { ctx.emit(item) }
        }

        if ctx.isCancelled() { return }

        // Graduated prune actions, safest first. Only the build cache is pre-selected. Sizes
        // come from the parsed reclaimable column where available, else 0.
        let dockerHome = FileScan.home

        ctx.progress("Build cache")
        emitPrune(pruneItem(
            label: "Docker build cache",
            url: dockerHome.appendingPathComponent(".docker/buildx"),
            severity: .safe,
            command: ToolCommand(tool: "docker", arguments: ["builder", "prune", "-f"], display: "docker builder prune -f"),
            allocated: reclaim.buildCache,
            note: "Build cache — rebuilt on the next docker build"
        ))

        if ctx.isCancelled() { return }
        ctx.progress("Unused images")
        emitPrune(pruneItem(
            label: "Unused Docker images",
            url: dockerHome.appendingPathComponent(".docker"),
            severity: .review,
            command: ToolCommand(tool: "docker", arguments: ["image", "prune", "-a", "-f"], display: "docker image prune -a -f"),
            allocated: reclaim.images,
            note: "Images not used by any container — pulled or rebuilt again when needed"
        ))

        if ctx.isCancelled() { return }
        ctx.progress("Stopped containers")
        emitPrune(pruneItem(
            label: "Stopped Docker containers",
            url: dockerHome.appendingPathComponent(".docker"),
            severity: .review,
            command: ToolCommand(tool: "docker", arguments: ["container", "prune", "-f"], display: "docker container prune -f"),
            allocated: reclaim.containers,
            note: "Removes exited containers and their writable layers; running containers are untouched"
        ))

        if ctx.isCancelled() { return }
        ctx.progress("Volume and system risks")
        emitPrune(pruneItem(
            label: "Docker volumes + everything (DESTRUCTIVE)",
            url: dockerHome.appendingPathComponent(".docker"),
            severity: .risky,
            command: nil,
            allocated: reclaim.total,
            note: "A broad system prune can delete images, networks, and named volumes containing the only copy of data. Cairn will not run this command."
        ))

        if ctx.isCancelled() { return }

        // The host VM disk image. Advice-only: never delete it, it IS every
        // image, container and volume. Pruning frees space inside the VM, and
        // current Docker Desktop hands those blocks back to the Mac shortly
        // after; older qcow2 images can take minutes.
        let rawURL = dockerHome.appendingPathComponent(
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        if FileScan.exists(rawURL) {
            ctx.progress("Docker.raw")
            let stats = FileScan.measure(rawURL)
            // The file is sparse: Finder shows its maximum, the disk holds far less.
            let maximum = (try? rawURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let real = maximum > stats.allocatedSize + 1_000_000_000
                ? "Uses \(Fmt.size(stats.allocatedSize)) on disk, out of the \(Fmt.size(maximum)) Docker may grow to. Finder shows the \(Fmt.size(maximum)), which is only the limit. "
                : ""
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
                note: real + "Docker's disk holds every image, container and volume, so Cairn never deletes it. After a prune, current Docker Desktop gives the space back to the Mac within a minute or so; scan again to see the new size.",
                permissionDenied: stats.permissionDenied,
                volumeURL: FileScan.volumeURL(of: rawURL)
            ))
        }
    }

    // MARK: - OrbStack and Colima

    private func emitOtherVMDisks(_ ctx: ScanContext) {
        let home = FileScan.home
        let orbstack = [
            home.appendingPathComponent("Library/Group Containers/HUAQ24HBR6.dev.orbstack/data"),
            home.appendingPathComponent(".orbstack/data"),
        ].first(where: FileScan.exists)
        if let orbstack {
            emitVMDisk(orbstack, ctx: ctx,
                       note: "OrbStack's disk holds its containers, images and Linux machines, so Cairn never deletes it. Prune unused images in OrbStack, and it returns freed space to the Mac by itself")
        }
        // Colima keeps one lima VM per profile; sized together.
        let colima = [home.appendingPathComponent(".colima/_lima"), home.appendingPathComponent(".lima")]
            .first(where: FileScan.exists)
        if let colima {
            emitVMDisk(colima, ctx: ctx,
                       note: "Colima's disks hold its containers and images, so Cairn never deletes them. After a prune, restarting Colima (0.5 or newer) gives the freed space back to the Mac; `colima ssh -- sudo fstrim -a` does the same without a restart")
        }
    }

    private func emitVMDisk(_ url: URL, ctx: ScanContext, note: String) {
        ctx.progress(url.lastPathComponent)
        let stats = FileScan.measure(url)
        guard stats.allocatedSize >= ctx.minSizeBytes else { return }
        ctx.emit(ScanItem(
            url: url,
            allocatedSize: stats.allocatedSize,
            itemCount: stats.fileCount,
            latestModified: stats.latestModified,
            categoryID: info.id,
            severity: .risky,
            isRegenerable: false,
            requiresRunning: false,
            cleanMethod: .adviceOnly,
            note: note,
            permissionDenied: stats.permissionDenied,
            volumeURL: FileScan.volumeURL(of: url)
        ))
    }

    // MARK: - Item construction

    /// Build a prune item. Size is Docker's parsed reclaimable estimate (or 0
    /// when unknown). A nil command keeps the finding advice-only.
    private func pruneItem(
        label: String,
        url: URL,
        severity: Severity,
        command: ToolCommand?,
        allocated: Int64,
        note: String
    ) -> ScanItem {
        ScanItem(
            url: url,
            allocatedSize: max(0, allocated),
            categoryID: info.id,
            severity: severity,
            isRegenerable: command != nil && severity == .safe,
            requiresRunning: true,
            cleanMethod: command.map { CleanMethod.tool($0) } ?? CleanMethod.adviceOnly,
            note: "\(label) — \(note)",
            volumeURL: FileScan.volumeURL(of: FileScan.home),
            selected: severity == .safe && allocated > 0
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
