import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StorageWorkspace: View {
    let store: StorageTransferStore
    var search: String
    @Binding var focused: String?
    @State private var selected = "Finished exports"
    @State private var selectedGuide = "Xcode build output"
    @State private var selectedRecord: UUID?
    @State private var source: URL?
    @State private var plannedDrive: StorageDrive?
    @State private var confirm = false
    @State private var showTransfers = false
    @State private var inspectedDrive: StorageDrive?
    @State private var localMessage = ""
    @State private var showCopyDetails = false
    @State private var npmCacheStatus = ""
    @State private var inspectingNpm = false
    private let preview = CommandLine.arguments.contains("--preview-ui")
    private var drives: [StorageDrive] { preview ? (CommandLine.arguments.contains("--preview-empty-storage") ? Array(Self.samples.prefix(1)) : Self.samples) : store.drives }
    private var externalDrives: [StorageDrive] { drives.filter(\.external) }
    private var drive: StorageDrive? {
        if let focused { return externalDrives.first { $0.id == focused } }
        return externalDrives.first
    }
    private var record: TransferRecord? { store.records.first { $0.id == selectedRecord } ?? store.records.first }
    private let guides = ["Xcode build output", "npm cache", "Docker disk image", "Cloud & remote machines", "Sessions, databases & swap"]
    private let areas = ["Models & archives", "Build output", "Finished exports", "Conversations & source"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Where your work lives").font(.system(size: 38, weight: .light))
                        Text("See your drives and choose the right next step for your files.").font(.system(size: 13)).foregroundStyle(Brand.textMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Text(Date(), format: .dateTime.day().month(.abbreviated).year()).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        HStack(spacing: 12) {
                            Button("Transfers") { showTransfers = true }.buttonStyle(.plain)
                            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(preview).help("Refresh drives").accessibilityLabel("Refresh drives")
                        }.font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                    }
                }
                driveStrip
                VStack(spacing: 0) {
                    HStack {
                        Text("Data").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Location").frame(width: 190, alignment: .leading)
                        Text("Next step").frame(width: 175, alignment: .leading)
                    }.font(.system(size: 12)).foregroundStyle(Brand.textMuted).padding(.horizontal, 19).frame(height: 35)
                    ForEach(areas.filter { search.isEmpty || ($0 + areaSubtitle($0)).localizedCaseInsensitiveContains(search) }, id: \.self) { area in areaRow(area) }
                    if !search.isEmpty && !areas.contains(where: { ($0 + areaSubtitle($0)).localizedCaseInsensitiveContains(search) }) {
                        Text("No storage categories match your search.").foregroundStyle(Brand.textMuted).padding(20)
                    }
                    Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.horizontal, 18).padding(.top, 14)
                    detail.padding(20)
                }
                if !localMessage.isEmpty || !store.message.isEmpty {
                    Text(localMessage.isEmpty ? store.message : localMessage).font(.system(size: 12)).foregroundStyle(Brand.textSecondary).textSelection(.enabled)
                }
            }.padding(30)
        }.background(Brand.background).foregroundStyle(Brand.textPrimary)
        .task { if !preview { await store.refresh() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in if !preview { Task { await store.refresh() } } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in if !preview { Task { await store.refresh() } } }
        .sheet(isPresented: $confirm) {
            if let source, let plannedDrive {
                WorkspaceConfirmation(title: "Copy and verify this export?", explanation: "Copy the file content to \(plannedDrive.name). The original stays in place. This does not free internal space or create a versioned backup. Close any application still writing this export. Extended attributes and resource forks are not copied; archive files that require them.", entries: [source.path, "Destination: \(plannedDrive.url.path)", "Drive identity: \(plannedDrive.uuid)"], actionTitle: "Copy & verify") {
                    guard !preview else { return }
                    store.start(source: source, drive: plannedDrive); showTransfers = true
                }
            }
        }
        .sheet(isPresented: $showTransfers) { transferSheet }
        .sheet(item: $inspectedDrive) { item in
            CairnDialog(title: item.name, subtitle: "Drive information") {
                ScrollView { VStack(alignment: .leading, spacing: 18) {
                WorkspaceDetail(title: "Drive identity", text: item.uuid.isEmpty ? "Unavailable" : item.uuid)
                WorkspaceDetail(title: "Format & protection", text: "\(item.format.uppercased()) · \(item.encrypted ? "encryption reported by macOS" : "encryption not confirmed") · \(item.writable ? "writable" : "read-only or unknown")")
                WorkspaceDetail(title: "Location", text: item.url.path)
                WorkspaceDetail(title: "Available capacity", text: "\(Fmt.size(item.available)) of \(Fmt.size(item.capacity)). Includes space macOS may reclaim.")
                WorkspaceDetail(title: "Export readiness", text: item.exportStatus)
                } }
            } actions: { Button("Done") { inspectedDrive = nil }.buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction) }
        }
    }
    private var driveStrip: some View {
        HStack(spacing: 20) {
            if let internalDrive = drives.first(where: { !$0.external }) {
                Button { inspectedDrive = internalDrive } label: {
                    driveSummary(internalDrive, icon: "laptopcomputer")
                }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
            } else { driveLabel("This Mac", subtitle: "Reading capacity…", icon: "laptopcomputer").frame(maxWidth: .infinity, alignment: .leading) }
            Rectangle().fill(Brand.separator).frame(width: 0.5, height: 80)
            HStack(spacing: 8) {
                if let drive {
                    Button { inspectedDrive = drive } label: {
                        driveSummary(drive, icon: "externaldrive")
                    }.buttonStyle(.plain)
                    Menu {
                        ForEach(externalDrives) { item in Button(item.name) { focused = item.id } }
                    } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.borderlessButton).frame(width: 18).accessibilityLabel("Choose destination drive")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        driveLabel(focused == nil ? "No external drive" : "Selected drive disconnected", subtitle: "Reconnect it or choose another drive", icon: "externaldrive")
                        if !externalDrives.isEmpty {
                            Menu("Choose connected drive") { ForEach(externalDrives) { item in Button(item.name) { focused = item.id } } }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 12)
    }
    private func driveSummary(_ item: StorageDrive, icon: String) -> some View {
        let available = min(max(item.available, 0), max(item.capacity, 0))
        let used = item.capacity > 0 ? 1 - Double(available) / Double(item.capacity) : 0
        return VStack(alignment: .leading, spacing: 12) {
            driveLabel(item.name, subtitle: "\(item.external ? "External" : "Internal") · \(item.encrypted ? "Encrypted" : "Encryption unconfirmed")", icon: icon)
            if item.capacity > 0 {
                GeometryReader { geometry in
                    Capsule().fill(Brand.track)
                    Capsule().fill(used > 0.95 ? Brand.amber : Brand.inUse).frame(width: geometry.size.width * used)
                }.frame(height: 5).accessibilityLabel("\(Int(used * 100)) percent used")
                HStack {
                    Text("\(Fmt.size(available)) available")
                    Spacer(minLength: 4)
                    Text(Fmt.size(item.capacity)).foregroundStyle(Brand.textMuted)
                }.font(.system(size: 11)).monospacedDigit()
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func driveLabel(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 29, weight: .light)).foregroundStyle(Brand.textSecondary).frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .regular)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private func areaRow(_ area: String) -> some View {
        Button { selected = area } label: {
            HStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: areaIcon(area)).font(.system(size: 23, weight: .light)).foregroundStyle(Brand.textSecondary).frame(width: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(area).font(.system(size: 13, weight: .regular))
                        Text(areaSubtitle(area)).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Label(area == "Models & archives" ? "Moved to your drive" : area == "Conversations & source" ? "Protected locations" : (area == "Finished exports" ? "Choose a local file" : "Tool-managed paths"), systemImage: area == "Conversations & source" ? "lock.shield" : area == "Models & archives" ? "externaldrive" : "laptopcomputer")
                        .font(.system(size: 12))
                    Text(area == "Models & archives" ? "Link left behind" : area == "Build output" ? "Check in the owning tool" : (area == "Finished exports" ? "Original kept in place" : "No relocation offered"))
                        .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
                }.frame(width: 190, alignment: .leading)
                HStack {
                    Text(area == "Models & archives" ? "Move and link" : area == "Build output" ? "Supported-path guidance" : (area == "Finished exports" ? "Copy and verify" : "Keep protected")).font(.system(size: 12))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Brand.textMuted)
                }.frame(width: 175, alignment: .leading)
            }.padding(.horizontal, 19).frame(height: 58).contentShape(Rectangle())
        }.buttonStyle(.plain).background(selected == area ? Brand.wash(0.045) : Color.clear)
    }
    @ViewBuilder private var detail: some View {
        if selected == "Models & archives" {
            OffloadPanel(drive: drive)
        } else if selected == "Finished exports" {
            HStack(alignment: .top, spacing: 28) {
                Image(systemName: "folder").font(.system(size: 31, weight: .light)).foregroundStyle(Brand.textSecondary)
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Finished exports").font(.system(size: 18, weight: .regular))
                        Text("A verified copy, with the original kept.").font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        copyStep("Choose file", active: true)
                        Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.top, 8)
                        copyStep("Review copy")
                        Rectangle().fill(Brand.separator).frame(height: 0.5).padding(.top, 8)
                        copyStep("Verify content")
                    }.padding(.vertical, 5)
                    if store.busy {
                        ProgressView().controlSize(.small)
                        Text("\(Fmt.size(store.copied)) copied · copy and verification in progress").font(.system(size: 11))
                        Button("View transfer") { showTransfers = true }.buttonStyle(ControlPanelButtonStyle(primary: true))
                    } else {
                        Button("Choose an export…") { chooseSource() }.buttonStyle(ControlPanelButtonStyle(primary: true)).disabled(preview || drive?.acceptsCopy != true)
                    }
                    DisclosureGroup("Copy details", isExpanded: $showCopyDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            info("Destination", drive?.name ?? "No eligible drive selected")
                            info("Accepted files", "Finished archives, PDFs and media. No folders, live databases or application state.")
                            Text("A second copy is not a versioned backup.").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }.font(.system(size: 12)).tint(Brand.textSecondary)
                    if !preview && drive?.acceptsCopy != true {
                        Text(drive?.exportStatus ?? "Connect a writable, encrypted APFS external drive to enable copying.")
                            .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)

            }
        } else if selected == "Build output" {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Supported-path guidance").font(.system(size: 17, weight: .regular))
                    Spacer()
                    Picker("Tool", selection: $selectedGuide) { ForEach(guides, id: \.self) { Text($0) } }.frame(width: 220)
                }
                Text(guideDetail(selectedGuide)).font(.system(size: 12)).foregroundStyle(Brand.textSecondary).fixedSize(horizontal: false, vertical: true)
                if selectedGuide == "npm cache" {
                    HStack {
                        Button(inspectingNpm ? "Checking npm…" : "Check current npm path") { inspectNpmCache() }
                            .buttonStyle(ControlPanelButtonStyle()).disabled(preview || inspectingNpm)
                        Spacer()
                    }
                    if !npmCacheStatus.isEmpty {
                        Text(npmCacheStatus).font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if let drive {
                        info("Selected drive", "\(drive.name) · \(drive.exportStatus)")
                        if drive.acceptsCopy {
                            info("Potential tool location", drive.url.appendingPathComponent("Cairn Tool Data/npm-cache").path + " · planning only; this folder has not been created")
                        }
                    }
                    Text("A safe migration still needs idle npm writers, a verified directory copy, configuration rollback and a missing-drive startup test. Cairn does not switch npm paths yet.")
                        .font(.system(size: 11)).foregroundStyle(Brand.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                Text("Cairn does not change these tool settings. Finish active work, verify a separate backup and plan for a missing drive before changing paths.").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                if let url = guideURL(selectedGuide) { Link("Read official documentation ↗", destination: url).font(.system(size: 12)) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Label("Keep your working state protected", systemImage: "lock.shield").font(.system(size: 17, weight: .regular))
                Text("Known conversation history, credentials, source repositories and recovery locations are excluded from cleanup. This screen does not move them.").font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                Text("Databases require application-aware backups. macOS manages swap. Ordinary folder synchronization is not a safe substitute for either.").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func copyStep(_ title: String, active: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: active ? "circle.fill" : "circle").font(.system(size: 11)).foregroundStyle(active ? Brand.room : Brand.textMuted)
            Text(title).font(.system(size: 11.5)).foregroundStyle(active ? Brand.textPrimary : Brand.textMuted).fixedSize()
        }
    }
    private func info(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 11)).foregroundStyle(Brand.textMuted); Text(text).font(.system(size: 12)).foregroundStyle(Brand.textSecondary).fixedSize(horizontal: false, vertical: true) }
    }
    private var transferSheet: some View {
        CairnDialog(title: "Transfers", subtitle: "Verified copies · originals retained", wide: true, height: 520) {
            VStack(alignment: .leading, spacing: 16) {
            if store.busy { CairnStateView(kind: .scanning, title: store.checkingCopy ? "Checking existing copy" : "Copy and verification in progress", message: store.checkingCopy ? "Reading the destination again. The original stays in place." : "\(Fmt.size(store.copied)) copied. The original stays in place.", compact: true) }
            if !store.message.isEmpty { Text(store.message).font(.system(size: 12)).foregroundStyle(Brand.textSecondary) }
            if store.records.isEmpty {
                WorkspaceEmpty(title: "No transfers yet", message: "Verified copies record their source, destination drive, result and content hash here.", icon: "arrow.right.doc.on.clipboard")
            } else {
                HStack(alignment: .top, spacing: 18) {
                    ScrollView { VStack(spacing: 0) { ForEach(store.records) { item in
                        Button { selectedRecord = item.id } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(URL(fileURLWithPath: item.source).lastPathComponent).lineLimit(1)
                                Text(item.status).foregroundStyle(Brand.textMuted)
                            }.font(.system(size: 12)).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(record?.id == item.id ? Brand.surfaceElevated : .clear)
                        }.buttonStyle(.plain)
                    } } }.frame(width: 215)
                    if let record {
                        ScrollView { VStack(alignment: .leading, spacing: 14) {
                            CairnStateView(kind: record.status == "Verified" ? .completed : record.status == "Copying" ? .scanning : .interrupted, title: record.status == "Verified" ? "Copy verified" : record.status == "Copying" ? "Copy in progress" : "Copy interrupted", message: record.detail, compact: true)
                            info("Original", record.source)
                            info("Destination", record.destination)
                            info("Drive identity", record.volumeID)
                            if !record.digest.isEmpty { info("SHA-256", record.digest) }
                            info("Recovery", "Original retained. Interrupted .partial files remain for inspection; they are not verified copies.")
                            Button("Show destination") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.destination)]) }.buttonStyle(ControlPanelButtonStyle()).disabled(preview)
                            Button("Check copy") { store.recheck(record) }.buttonStyle(ControlPanelButtonStyle()).disabled(preview || store.busy)
                        }.textSelection(.enabled) }.frame(maxWidth: .infinity)
                    }
                }
            }
            }
        } actions: {
            if store.busy { Button(store.checkingCopy ? "Stop check" : "Stop copy") { store.cancel() }.buttonStyle(ControlPanelButtonStyle()) }
            Button(store.busy ? "Continue in background" : "Done") { showTransfers = false }.buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction)
        }
    }
    private func areaSubtitle(_ area: String) -> String {
        switch area {
        case "Models & archives": return "Local AI models and Xcode archives."
        case "Build output": return "Build folders and tool-managed data."
        case "Finished exports": return "Saved archives, PDFs and media."
        default: return "Sessions, repositories and credentials."
        }
    }
    private func areaIcon(_ area: String) -> String { area == "Models & archives" ? "cpu" : area == "Build output" ? "hammer" : (area == "Finished exports" ? "folder" : "doc.text") }
    private func chooseSource() {
        guard !preview, !store.busy, let drive, drive.acceptsCopy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a finished archive, PDF or media export. Original files are retained."
        panel.allowedContentTypes = ArchiveCopy.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try ArchiveCopy.validateSource(url); source = url; plannedDrive = drive; confirm = true; localMessage = "" }
            catch { localMessage = error.localizedDescription }
        }
    }
    private func inspectNpmCache() {
        guard !preview, !inspectingNpm else { return }
        inspectingNpm = true
        Task {
            let status = await Task.detached(priority: .utility) { NpmCacheInspection.inspect() }.value
            npmCacheStatus = status
            inspectingNpm = false
        }
    }
    private func guideSummary(_ guide: String) -> String {
        switch guide {
        case "npm cache": return "Use npm’s cache configuration"
        case "Xcode build output": return "Set Derived Data in Xcode Locations"
        case "Docker disk image": return "Move through Docker Desktop settings"
        case "Archives & media": return "Copy finished exports and verify content"
        case "Cloud & remote machines": return "Offload files or run work remotely"
        default: return "Application-aware handling; no blanket relocation"
        }
    }
    private func guideDetail(_ guide: String) -> String {
        switch guide {
        case "npm cache": return "npm exposes a cache path setting. Configure the external path in npm after recording the existing value; keep the drive connected while installing packages. Cairn currently provides guidance and does not edit your npm configuration."
        case "Xcode build output": return "Xcode offers a custom Derived Data location in Settings → Locations. Keep source repositories, archives, signing data and simulator devices separate from disposable build output. Change the location in Xcode after builds finish."
        case "Docker disk image": return "Use Docker Desktop’s Resources settings to change its disk image location while following Docker’s prompts. Never copy or synchronize the live disk image as ordinary files."
        case "Archives & media": return "Use Copy an export on an eligible drive. The source stays in place and full content hashes must match before the copy is marked verified. Open and check the destination before deciding separately what to do with the original."
        case "Cloud & remote machines": return "Cloud storage can hold archives or exported backups, and a remote machine can run development services. Neither adds RAM to this Mac. Online-only files require network access; ordinary synchronization can propagate deletion and is not a versioned backup."
        default: return "Leave macOS virtual memory under system control. Keep conversation history and credentials protected. Databases require their own consistent backup/export procedure; live database directories are never copied by Cairn."
        }
    }
    private func guideURL(_ guide: String) -> URL? {
        let value: String
        switch guide {
        case "npm cache": value = "https://docs.npmjs.com/cli/v11/using-npm/config/#cache"
        case "Xcode build output": value = "https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings"
        case "Docker disk image": value = "https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/"
        default: value = "https://support.apple.com/guide/disk-utility/file-system-formats-dsku19ed921c/mac"
        }
        return URL(string: value)
    }
    private static let samples = [StorageDrive(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", uuid: PreviewStorageScenario.volumeID, capacity: PreviewStorageScenario.totalBytes, available: PreviewStorageScenario.availableBytes, external: false, writable: true, encrypted: true, format: "apfs"), StorageDrive(url: URL(fileURLWithPath: "/Volumes/Studio SSD"), name: "Studio SSD", uuid: "SAMPLE-DRIVE-IDENTITY", capacity: 1_000_000_000_000, available: 186_000_000_000, external: true, writable: true, encrypted: true, format: "apfs")]
}
