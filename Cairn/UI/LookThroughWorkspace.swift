import SwiftUI
import AppKit

/// Files › Look through: everything Cairn found that only the person can decide
/// on, in plain groups with one tick each. Built from look-through.png.
struct LookThroughWorkspace: View {
    var store: ScanStore
    var onReview: () -> Void
    var onOpen: (NavSection) -> Void = { _ in }
    @State private var expanded: Set<String> = []
    private let settings = AppSettings.shared

    private var groups: [LookGroup] {
        let titles = Dictionary(store.buckets.map { ($0.id, $0.info.title) }, uniquingKeysWith: { a, _ in a })
        return LookThrough.groups(from: store.buckets.flatMap(\.items), titles: titles)
    }
    /// Matches Home's "more to look through": the groups plus what is tidied elsewhere.
    private var totalBytes: Int64 { LookThrough.candidates(store.buckets.flatMap(\.items)).reduce(0) { $0 + $1.allocatedSize } }

    var body: some View {
        let groups = self.groups
        let picked = Set(store.selectedItems().map(\.id))
        let mine = groups.flatMap(\.items).filter { picked.contains($0.id) }
        let pickedBytes = mine.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let pickedGroups = groups.filter { g in g.items.contains { picked.contains($0.id) } }.count

        NightPage(eyebrow: store.grandTotal > 0 ? "Look through · \(Fmt.size(store.grandTotal)) found on this Mac" : "Look through",
                  title: totalBytes > 0 ? "\(Fmt.size(totalBytes)) to look through" : "Look through",
                  subtitle: "Your own files, grouped. Tick a group to clear all of it, or open it to pick. Your code, documents and AI chats are never listed.") {
            Button { if store.isScanning { store.cancel() } else { store.rescan() } } label: {
                Label(store.isScanning ? "Stop scan" : "Rescan", systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
            }
            .buttonStyle(ControlPanelButtonStyle(size: .small))
            .disabled(store.isCleaning)
        } content: {
            if groups.isEmpty && totalBytes == 0 {
                NightEmpty(title: store.isScanning ? "Looking through this Mac" : store.hasScanned ? "Nothing to look through" : "Nothing scanned yet",
                           message: store.isScanning ? "Groups appear as the scan finds them."
                               : store.hasScanned ? "No big old downloads, videos, installers or app leftovers were found."
                               : "Press Rescan and Cairn will group what it finds.",
                           busy: store.isScanning)
            } else {
                NightList {
                    ForEach(groups) { group in
                        groupRow(group, picked: picked)
                        if expanded.contains(group.id) {
                            ForEach(group.items) { item in itemRow(item, on: picked.contains(item.id)) }
                        }
                    }
                    elsewhereRow
                }
            }
        } footer: {
            if pickedBytes > 0 {
                NightTotal(strong: Fmt.size(pickedBytes),
                           rest: "selected from \(pickedGroups) group\(pickedGroups == 1 ? "" : "s") · " +
                                 (settings.removalMode == .delete ? "removed straight away" : "goes to the Trash, so you can put it back"))
                Spacer()
                Button("Select none") { setSelected(mine.map(\.id), false) }
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
                Button("Review cleanup · \(Fmt.size(pickedBytes))") {
                    store.beginScopedReview(Set(mine.map(\.id)))
                    onReview()
                }
                .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                .disabled(store.isCleaning || store.isScanning)
            } else {
                NightTotal(strong: Fmt.size(groups.reduce(0) { $0 + $1.oldBytes }), rest: "untouched for over a year")
                Spacer()
                Text("Tick a group to start").font(.system(size: 12)).foregroundStyle(Brand.textMuted)
            }
        }
    }

    // MARK: - Rows

    /// Git history, Docker, package stores and risky items: never one tick.
    /// Shown so this page still accounts for everything Home counts.
    @ViewBuilder private var elsewhereRow: some View {
        let items = LookThrough.elsewhere(store.buckets.flatMap(\.items))
        if !items.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                Color.clear.frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tidied with each tool's own command").font(.system(size: 14, weight: .medium))
                    Text("Git history, Docker, package stores and Xcode archives need their own clean-up, not the Trash")
                        .font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary)
                    HStack(spacing: 6) {
                        Text(items.prefix(3).map(LookThrough.shortName).joined(separator: " · ")).foregroundStyle(Brand.textMuted).lineLimit(1)
                        Button("Open in Clean") { onOpen(.developer) }.buttonStyle(.plain).foregroundStyle(Brand.room)
                    }
                    .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Fmt.size(items.reduce(0) { $0 + $1.allocatedSize })).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.textSecondary).monospacedDigit()
                    .frame(width: 170, alignment: .trailing)
            }
            .padding(.vertical, 2)
            .nightRow()
        }
    }

    private func groupRow(_ group: LookGroup, picked: Set<UUID>) -> some View {
        let count = group.items.filter { picked.contains($0.id) }.count
        let isOpen = expanded.contains(group.id)
        let tickable = group.oneTick
        let oneByOne = group.items.count - tickable.count
        return HStack(alignment: .top, spacing: 14) {
            // The tick takes only what is fine to clear together; it clears every pick in the group.
            NightCheck(on: count > 0, enabled: !tickable.isEmpty || count > 0) {
                if count > 0 { setSelected(group.items.map(\.id), false) } else { setSelected(tickable.map(\.id), true) }
            }
            .accessibilityLabel(count > 0 ? "Clear selection in \(group.title)" : "Select eligible items in \(group.title)")
            .accessibilityValue("\(count) of \(group.items.count) selected")
            .opacity(count > 0 && count < group.items.count ? 0.6 : 1)
            .help(count > 0 && count < group.items.count ? "\(count) of \(group.items.count) picked" : "")
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title).font(.system(size: 14, weight: .medium))
                Text(oneByOne == 0 ? group.line
                     : tickable.isEmpty ? group.line + " · pick one by one"
                     : group.line + " · \(oneByOne) to pick one by one")
                    .font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary)
                HStack(spacing: 6) {
                    Text(group.peek.joined(separator: " · ")).foregroundStyle(Brand.textMuted).lineLimit(1)
                    Button(isOpen ? "Hide" : "See all") { expanded.formSymmetricDifference([group.id]) }
                        .buttonStyle(.plain).foregroundStyle(Brand.room)
                        .accessibilityLabel("\(isOpen ? "Hide" : "Show") items in \(group.title)")
                }
                .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.size(group.bytes)).font(.system(size: 14, weight: .medium)).monospacedDigit()
                Text(ageLine(group)).font(.system(size: 12)).foregroundStyle(Brand.textMuted).monospacedDigit()
            }
            .frame(width: 170, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .nightRow()
    }

    private func itemRow(_ item: ScanItem, on: Bool) -> some View {
        HStack(spacing: 14) {
            NightCheck(on: on, enabled: item.severity != .risky) { setSelected([item.id], !on) }
                .accessibilityLabel(item.severity == .risky ? "\(item.resolvedURL.lastPathComponent) is protected" : "\(on ? "Deselect" : "Select") \(item.resolvedURL.lastPathComponent)")
                .accessibilityHint(item.resolvedURL.path)
            NightName(logo: nil, title: item.resolvedURL.lastPathComponent, subtitle: folder(item))
            Text(age(item)).font(.system(size: 12)).foregroundStyle(Brand.textMuted).frame(width: 110, alignment: .trailing)
            Text(Fmt.size(item.allocatedSize)).font(.system(size: 13)).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
        .padding(.leading, 36)
        .nightRow()
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.resolvedURL]) }
        }
    }

    // MARK: - Helpers

    private func setSelected(_ ids: [UUID], _ value: Bool) {
        let wanted = Set(ids)
        if value {
            store.select { item, _ in wanted.contains(item.id) }
        } else {
            let selected = Set(store.selectedItems().map(\.id))
            for id in ids where selected.contains(id) { store.toggle(id) }
        }
    }

    private func ageLine(_ group: LookGroup) -> String {
        let old = group.oldBytes
        if old == 0 { return "Changed this year" }
        if old == group.bytes { return "All over a year old" }
        return "\(Fmt.size(old)) over a year old"
    }

    private func age(_ item: ScanItem) -> String {
        guard item.latestModified > .distantPast else { return "" }
        let years = Int(item.ageDays / 365)
        if years >= 1 { return "\(years) year\(years == 1 ? "" : "s") old" }
        return item.latestModified.formatted(.relative(presentation: .named))
    }

    private func folder(_ item: ScanItem) -> String {
        let parent = item.resolvedURL.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return parent.hasPrefix(home) ? "~" + String(parent.dropFirst(home.count)) : parent
    }
}
