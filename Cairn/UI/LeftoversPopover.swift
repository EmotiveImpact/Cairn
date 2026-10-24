import SwiftUI

/// The menu bar notice from leftovers.png: what an app that just went in the
/// Bin left behind, with Not now and Review leftovers. 380 pt wide, 18 pt in.
struct LeftoversPopover: View {
    let found: AppLeftovers.Found
    var onClose: () -> Void
    var onReview: () -> Void

    private struct Row: Identifiable {
        let title: String
        let detail: String
        let bytes: Int64
        var id: String { title + detail }
    }

    /// The two biggest support folders on their own, everything else together.
    private var rows: [Row] {
        let support = Array(found.support.prefix(2))
        var rows = support.map { part in
            Row(title: part.url.path.contains("/Containers/") ? "App container" : "Support files",
                detail: part.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), bytes: part.bytes)
        }
        let rest = found.parts.filter { part in !support.contains { $0.id == part.id } }
        if !rest.isEmpty {
            rows.append(Row(title: "Caches and preferences",
                            detail: rest.count == 1 ? "1 small item" : "\(rest.count) small items",
                            bytes: rest.reduce(0) { $0 + $1.bytes }))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cairn").nightEyebrow().padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(found.app) went in the Bin.").font(.system(size: 15, weight: .medium))
                (Text("It left ").foregroundStyle(Brand.textMuted)
                 + Text(Fmt.size(found.total)).foregroundStyle(Brand.room)
                 + Text(" behind.").foregroundStyle(Brand.textMuted))
                    .font(.system(size: 15))
            }
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Image(systemName: "archivebox").font(.system(size: 15, weight: .light))
                            .foregroundStyle(Brand.textMuted).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.system(size: 13, weight: .medium))
                            Text(row.detail).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.size(row.bytes)).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) { Rectangle().fill(Brand.wash(0.06)).frame(height: 1) }
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.wash(0.06)).frame(height: 1) }
            .padding(.top, 14)
            Text("Your documents stay where they are. Nothing goes until you review it.")
                .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.bottom, 14)
            HStack(spacing: 8) {
                Spacer()
                Button("Not now", action: onClose).buttonStyle(ControlPanelButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Review leftovers", action: onReview).buttonStyle(ControlPanelButtonStyle(primary: true))
            }
        }
        .foregroundStyle(Brand.textPrimary)
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 16)
        .frame(width: 380)
    }
}
