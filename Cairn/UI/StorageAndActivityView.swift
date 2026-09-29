import SwiftUI

/// Read-only volume overview until a migration engine can verify volume identity,
/// encryption, capacity, copy integrity, disconnection and rollback.
struct StorageOverviewView: View {
    let store: ScanStore
    let onFiles: () -> Void
    let onDeveloper: () -> Void

    @State private var internalVolume: Volumes.Info?
    @State private var mountedVolumes: [Volumes.Info] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage").font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Brand.textPrimary)
                        Text("Available space on this Mac and mounted volumes.")
                            .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                    }
                    Spacer()
                    Button { refreshVolumes() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }.buttonStyle(GhostButtonStyle())
                }
                .padding(.bottom, 7)

                if let internalVolume {
                    volumeCard(internalVolume, icon: "internaldrive", subtitle: "Internal startup volume")
                } else {
                    volumeUnavailable("Internal volume data is unavailable.")
                }

                HStack {
                    Text("Mounted volumes").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                    Spacer()
                    Text("\(mountedVolumes.count)").font(.system(size: 11))
                        .foregroundStyle(Brand.textMuted)
                }.padding(.top, 4)
                if mountedVolumes.isEmpty {
                    volumeUnavailable("No additional volume is mounted.")
                } else {
                    ForEach(mountedVolumes, id: \.url.path) { volume in
                        volumeCard(volume, icon: "externaldrive", subtitle: volume.url.path)
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    Label("Find space to reclaim", systemImage: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Cairn can review large files and developer results through its existing scanners. A mounted drive is not yet a verified migration destination.")
                        .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 9) {
                        Button("Review large files", action: onFiles).buttonStyle(BrandButtonStyle())
                        Button("Review developer data", action: onDeveloper).buttonStyle(GhostButtonStyle())
                    }
                }.cairnCard(18)

                Text("Virtual memory stays managed by macOS. External storage adds file capacity; it does not add RAM or redirect swap.")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            .padding(24).frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: "volumeOverview") { refreshVolumes() }
    }

    private func refreshVolumes() {
        // Snapshot outside body: volume stat calls must never join layout passes.
        let home = FileManager.default.homeDirectoryForCurrentUser
        internalVolume = Volumes.info(for: FileScan.volumeURL(of: home))
        mountedVolumes = Volumes.mountedExternalVolumes().compactMap { Volumes.info(for: $0) }
    }

    private func volumeCard(_ volume: Volumes.Info, icon: String, subtitle: String) -> some View {
        let used = max(0, volume.totalCapacity - volume.availableImportant)
        let fraction = volume.totalCapacity > 0 ? Double(used) / Double(volume.totalCapacity) : 0
        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Brand.blue)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text("\(Fmt.size(volume.availableImportant)) free")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Brand.textPrimary)
            }
            ProgressView(value: fraction)
                .tint(fraction > 0.9 ? Brand.amber : Brand.blue)
            HStack {
                Text("\(Fmt.size(used)) used")
                Spacer()
                Text("\(Fmt.size(volume.totalCapacity)) total")
            }
            .font(.system(size: 10.5)).foregroundStyle(Brand.textMuted)
        }.cairnCard(16)
    }

    private func volumeUnavailable(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "externaldrive.badge.questionmark")
            Text(message)
            Spacer()
        }
        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
        .cairnCard(16)
    }
}

/// Full removal history and recovery route. This reads the existing persisted
/// removal log; it does not invent a second history database.
struct ActivityRecoveryView: View {
    let store: ScanStore
    @State private var restoreMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Activity & Recovery").font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                Text("Recent Cairn removals. Items moved to Trash can be put back while their Trash entry exists.")
                    .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                if let restoreMessage {
                    Text(restoreMessage).font(.system(size: 11.5))
                        .foregroundStyle(Brand.textSecondary).cairnCard(10)
                }
                if store.removalLog.isEmpty {
                    EmptyState(icon: "clock.arrow.circlepath", title: "No removal activity yet",
                               caption: "Reviewed cleanups will appear here with their recovery status.")
                        .cairnCard(0)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(store.removalLog) { entry in
                            HStack(spacing: 11) {
                                Image(systemName: entry.recoverable ? "arrow.uturn.backward.circle" : "trash.slash")
                                    .foregroundStyle(entry.recoverable ? Brand.blue : Brand.textMuted)
                                    .frame(width: 23)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.name).font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Brand.textPrimary)
                                    Text(entry.originalPath).font(.system(size: 10.5))
                                        .foregroundStyle(Brand.textMuted).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                Text(Fmt.size(entry.bytes)).font(.system(size: 11.5))
                                    .monospacedDigit().foregroundStyle(Brand.textSecondary)
                                Text(Fmt.relative(entry.date)).font(.system(size: 10.5))
                                    .foregroundStyle(Brand.textMuted).frame(width: 78, alignment: .trailing)
                                if entry.recoverable {
                                    Button("Put Back") {
                                        Task { restoreMessage = await store.restoreFromLog(entry)
                                            ? "Restored \(entry.name) to its original location."
                                            : "Could not restore \(entry.name). Check its Trash entry and original location." }
                                    }.buttonStyle(GhostButtonStyle())
                                } else {
                                    Text("Permanent").font(.system(size: 10.5))
                                        .foregroundStyle(Brand.textMuted).frame(width: 72)
                                }
                            }
                            .padding(.horizontal, 15).frame(height: 57)
                            .background(Brand.surfaceElevated)
                            .overlay(Rectangle().fill(Brand.border).frame(height: 1), alignment: .bottom)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Brand.rCard))
                    .overlay(RoundedRectangle(cornerRadius: Brand.rCard).stroke(Brand.border))
                }
                Text("A permanent tool action or emptied Trash cannot be restored from Cairn's history.")
                    .font(.system(size: 11)).foregroundStyle(Brand.textMuted)
            }
            .padding(24).frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}
