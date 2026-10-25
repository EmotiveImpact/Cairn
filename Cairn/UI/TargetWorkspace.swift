import SwiftUI
import AppKit

/// "24 GB is what I need" (target.png): type a size, and Cairn picks the safest
/// set that gets there, caches first, stopping once there is enough. Ticking or
/// unticking a row plans again around it. The normal review takes it from there.
struct TargetWorkspace: View {
    let store: ScanStore
    /// Free space on this Mac now, when known.
    var freeNow: Int64?
    var onScan: () -> Void
    var onReview: () -> Void
    var onOpen: (NavSection) -> Void
    @State private var text = "20"
    @State private var forced = Set<String>()
    @State private var left = Set<String>()
    @FocusState private var fieldFocused: Bool
    private let preview = CommandLine.arguments.contains("--preview-ui")

    private struct Quick: Hashable { let name: String; let gb: Int }
    /// Space each one asks for on a typical Mac, rounded up.
    private static let quick = [Quick(name: "macOS update", gb: 27), Quick(name: "Xcode", gb: 35), Quick(name: "Premiere", gb: 30)]

    private var goal: Int64 {
        let typed = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let gb = Double(typed), gb > 0, gb < 100_000 else { return 0 }
        return Int64(gb * 1_000_000_000)
    }
    private var groups: [TargetPlan.Group] {
        TargetPlan.groups(preview ? Self.sample : store.buckets.map { (info: $0.info, items: $0.items) })
    }
    private var scanned: Bool { preview || store.hasScanned }

    var body: some View {
        let plan = TargetPlan.plan(groups, goal: goal, forced: forced, left: left)
        NightHeroPage(eyebrow: "Make room for something", lead: lead) {
            hero
        } trailing: {
            if !preview && (!store.hasScanned || store.isScanning) {
                Button { if store.isScanning { store.cancel() } else { onScan() } } label: {
                    Label(store.isScanning ? "Stop scan" : "Scan this Mac", systemImage: store.isScanning ? "stop.circle" : "arrow.clockwise")
                }
                .buttonStyle(ControlPanelButtonStyle(size: .small))
            }
        } content: {
            content(plan)
        } footer: {
            footer(plan)
        }
        .onChange(of: text) { _, _ in forced = []; left = [] }
        .onAppear { if preview { text = "24" } else { fieldFocused = true } }
    }

    // MARK: Hero

    private var fieldWidth: CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 64, weight: .light)
        return ceil(((text.isEmpty ? "0" : text) as NSString).size(withAttributes: [.font: font]).width) + 6
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("0", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 64, weight: .light).monospacedDigit())
                        .frame(width: fieldWidth)
                        .focused($fieldFocused)
                        .onSubmit { fieldFocused = false }
                        .accessibilityLabel("Space you need, in gigabytes")
                    Text("GB").font(.system(size: 28, weight: .light)).foregroundStyle(Brand.textMuted)
                }
                .padding(.trailing, 6).padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Brand.room.opacity(0.5)).frame(height: 1.5) }
                Text("is what I need").font(.system(size: 19)).foregroundStyle(Brand.textMuted)
            }
            HStack(spacing: 8) {
                ForEach(Self.quick, id: \.self) { option in
                    Button { text = String(option.gb) } label: {
                        Text("\(option.name) · \(option.gb) GB").font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                            .padding(.horizontal, 11).padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(Brand.wash(0.12), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    private var lead: String {
        if let freeNow, goal > 0, freeNow >= goal {
            return "You already have \(Fmt.size(freeNow)) free, which covers this. Cairn can still free it if you want room to spare."
        }
        return "Cairn picks the safest set that gets you there, caches first, and stops as soon as you have enough."
    }

    // MARK: Rows

    @ViewBuilder private func content(_ plan: TargetPlan.Result) -> some View {
        if !scanned {
            NightEmpty(title: store.isScanning ? "Reading your files" : "Cairn needs a scan first",
                       message: store.isScanning ? "The plan appears when the scan finishes. Nothing is removed." : "Scan this Mac and Cairn works out what gets you there.",
                       busy: store.isScanning)
        } else if goal == 0 {
            NightEmpty(title: "How much space do you need?", message: "Type a size, or pick one of the sizes above.")
        } else if plan.rows.isEmpty {
            NightEmpty(title: "Nothing Cairn can free without your own files",
                       message: "The last scan found no caches or rebuildable files. Look through your own files for the rest.")
        } else {
            VStack(alignment: .leading, spacing: 18) {
                reach(plan)
                NightList { ForEach(visibleRows(plan)) { row(for: $0, plan: plan) } }
            }
        }
    }

    /// Rows in the plan, rows you left out, then the next two it didn't need.
    private func visibleRows(_ plan: TargetPlan.Result) -> [TargetPlan.Row] {
        var spare = 0
        return plan.rows.filter { row in
            if row.included || left.contains(row.id) { return true }
            spare += 1
            return spare <= 2
        }
    }

    private func row(for row: TargetPlan.Row, plan: TargetPlan.Result) -> some View {
        let dim = !row.included && !left.contains(row.id)
        return HStack(spacing: 16) {
            NightCheck(on: row.included) { toggle(row) }
                .accessibilityLabel(row.included ? "Leave out \(row.group.title)" : "Add \(row.group.title)")
            NightName(logo: nil, title: row.group.title, subtitle: line(row, plan: plan), titleSize: 13.5)
            Text(Fmt.size(row.included ? row.bytes : row.group.bytes))
                .font(.system(size: 13.5, weight: .medium)).monospacedDigit()
                .frame(width: 70, alignment: .trailing)
            Text(row.included ? "→ \(Fmt.size(row.runningTotal))" : "")
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted).monospacedDigit()
                .frame(width: 100, alignment: .trailing)
        }
        .nightHeroRow()
        .opacity(dim ? 0.45 : 1)
    }

    private func line(_ row: TargetPlan.Row, plan: TargetPlan.Result) -> String {
        if left.contains(row.id) { return "Left out by you" }
        if !row.included { return plan.reached ? "Not needed: target already reached" : "Not needed" }
        let all = row.group.items.count
        let partial = row.chosen.count < all
        let count = partial ? "\(row.chosen.count) of \(all) items" : all == 1 ? "1 item" : "\(all) items"
        switch row.group.tier {
        case .madeAgain: return partial ? "\(count) · made again on their own" : "Made again on their own"
        case .alreadyInstalled: return "\(count) for apps you've already installed · you choose"
        case .downloadedAgain: return partial ? "\(count) · downloaded again when needed · worth a look" : "Downloaded again when needed · worth a look"
        case .youChoose: return row.group.bucketID == "trash" ? "Already in the Bin, gone for good · you choose" : "\(count) · you choose"
        }
    }

    private func toggle(_ row: TargetPlan.Row) {
        if row.included {
            if forced.contains(row.id) { forced.remove(row.id) } else { left.insert(row.id) }
        } else {
            left.remove(row.id)
            forced.insert(row.id)
        }
    }

    // MARK: Reach bar

    private static func shade(_ index: Int) -> Double { [1, 0.75, 0.55, 0.38][min(index, 3)] }

    private func reach(_ plan: TargetPlan.Result) -> some View {
        let segments = plan.rows.filter(\.included)
        let scale = Double(max(plan.goal, plan.total)) * 1.18
        // The bar is 6 points tall and the goal mark 16, centred on it, all inside the
        // reader's frame so nothing spills onto the line below.
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Brand.wash(0.07)).frame(height: 6)
                    HStack(spacing: 2) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, row in
                            RoundedRectangle(cornerRadius: 3).fill(Brand.room.opacity(Self.shade(index)))
                                .frame(width: max(2, width * CGFloat(Double(row.bytes) / scale) - 2), height: 6)
                        }
                    }
                    Rectangle().fill(Brand.textPrimary).frame(width: 1.5, height: 16)
                        .offset(x: width * CGFloat(Double(plan.goal) / scale))
                }
                .frame(width: width, height: geo.size.height, alignment: .leading)
            }
            .frame(height: 16)
            .accessibilityHidden(true)
            HStack {
                (Text(Fmt.size(plan.total)).fontWeight(.medium).foregroundStyle(Brand.room)
                 + Text(reachNote(plan)).foregroundStyle(Brand.textMuted))
                Spacer()
                (Text("Goal ").foregroundStyle(Brand.textMuted)
                 + Text(Fmt.size(plan.goal)).fontWeight(.medium).foregroundStyle(Brand.textPrimary))
            }
            .font(.system(size: 12)).monospacedDigit()
        }
    }

    private func reachNote(_ plan: TargetPlan.Result) -> String {
        if !plan.reached { return " found without touching your own files" }
        return plan.toCheck == 0 ? " found, all of it safe" : " found, \(Fmt.size(plan.toCheck)) of it for you to check"
    }

    // MARK: Footer

    @ViewBuilder private func footer(_ plan: TargetPlan.Result) -> some View {
        if scanned && goal > 0 {
            NightTotal(strong: Fmt.size(plan.total), rest: footNote(plan), large: true)
        }
        Spacer()
        if scanned && goal > 0 && !plan.reached {
            Button("Look through your files") { onOpen(.lookThrough) }
                .buttonStyle(ControlPanelButtonStyle(size: .large))
        }
        Button(plan.total > 0 ? "Review and free \(Fmt.size(plan.total))" : "Review and free") { review(plan) }
            .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
            .disabled(plan.chosen.isEmpty || (!preview && (store.isScanning || store.isCleaning)))
    }

    private func footNote(_ plan: TargetPlan.Result) -> String {
        if !plan.reached { return "of \(Fmt.size(plan.goal)) · the rest would have to come from your own files" }
        return plan.toCheck == 0 ? "gets you there · nothing of yours is touched" : "gets you there · you check \(Fmt.size(plan.toCheck)) of it first"
    }

    private func review(_ plan: TargetPlan.Result) {
        guard !preview else { return }
        let ids = Set(plan.chosen.map(\.id))
        store.clearSelection()
        store.select { item, _ in ids.contains(item.id) }
        if store.selectedCount > 0 { onReview() }
    }

    // MARK: Preview

    /// The approved picture's numbers. Preview only; never acted on.
    private static let sample: [(info: CategoryInfo, items: [ScanItem])] = {
        func bucket(_ id: String, _ title: String, _ group: CategoryGroup, _ sizes: [Double],
                    severity: Severity = .safe, regenerable: Bool = true) -> (info: CategoryInfo, items: [ScanItem]) {
            let info = CategoryInfo(id: id, title: title, subtitle: "", systemImage: "folder", group: group, requiresFDA: false)
            let items = sizes.enumerated().map { index, gb in
                ScanItem(url: URL(fileURLWithPath: "/Sample/\(id)/\(index)"), allocatedSize: Int64(gb * 1_000_000_000),
                         categoryID: id, severity: severity, isRegenerable: regenerable)
            }
            return (info: info, items: items)
        }
        return [
            bucket("app-caches", "Browser and app caches", .general, [9.8]),
            bucket("xcode", "Xcode build files", .developer, [7.1]),
            bucket("dev-caches", "npm and pip caches", .developer, [5.1]),
            bucket("installers", "Old installers in Downloads", .general, [1.2, 0.6, 0.5]),
            bucket("docker", "Docker images", .developer, [9.8], severity: .review),
        ]
    }()
}
