import SwiftUI

/// The page layout from the approved Night screens (night-screens-v2.html):
/// small-caps eyebrow with one quiet button, a 40 pt light title and one grey
/// line, an open hairline list, and a footer with the total and the actions.
/// Values are copied from the mock's CSS, not approximated.
struct NightPage<Trailing: View, Content: View, Footer: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String = ""
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 8) {
                Text(eyebrow).nightEyebrow().lineLimit(1)
                Spacer(minLength: 12)
                trailing()
            }
            .frame(height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 40, weight: .light)).tracking(-0.8)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Brand.textMuted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .center, spacing: 10) { footer() }
                .padding(.top, 6)
        }
        .padding(.top, 22).padding(.horizontal, 40).padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Brand.textPrimary)
    }
}

extension NightPage where Footer == EmptyView {
    init(eyebrow: String, title: String, subtitle: String = "",
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle,
                  trailing: trailing, content: content, footer: { EmptyView() })
    }
}

extension View {
    /// 11 pt small caps, 0.14 em tracking, muted. The page eyebrow.
    func nightEyebrow() -> some View {
        font(.system(size: 11)).tracking(1.5).textCase(.uppercase).foregroundStyle(Brand.textMuted)
    }

    /// One list row: 12 pt above and below, a hairline on top.
    func nightRow() -> some View {
        padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { Rectangle().fill(Brand.wash(0.06)).frame(height: 1) }
    }
}

/// The open list: rows separated by hairlines, nothing boxed. Each row draws
/// its own top hairline, so the first one doubles as the list's top edge.
struct NightList<Rows: View>: View {
    @ViewBuilder var rows: () -> Rows
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) { rows() }
        }
        .scrollIndicators(.automatic)
    }
}

/// 16 pt rounded box. Filled ice with a dark tick when on.
struct NightCheck: View {
    var on: Bool
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(on ? Brand.room : Color.clear)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(on ? Brand.room : Brand.wash(enabled ? 0.25 : 0.12), lineWidth: 1.5)
                if on {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Brand.onRoom)
                }
            }
            .frame(width: 16, height: 16)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Logo (or thin symbol), a 13 pt medium name and a 12 pt muted line.
struct NightName: View {
    var logo: BrandLogo?
    var title: String
    var subtitle: String = ""
    var body: some View {
        HStack(spacing: 10) {
            if let logo { logo.frame(width: 22, height: 22) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 3 pt share bar: faint track, ice fill at 80%.
struct NightMeter: View {
    var share: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.wash(0.07))
                Capsule().fill(Brand.room.opacity(0.8))
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, share)))))
            }
        }
        .frame(width: 150, height: 3)
        .accessibilityHidden(true)
    }
}

/// Outline pill: neutral grey, ice for ready, amber when something needs closing first.
struct NightPill: View {
    enum Tone { case neutral, quiet, ok, warn }
    var text: String
    var tone: Tone = .neutral
    private var color: Color {
        switch tone {
        case .neutral: return Brand.textSecondary
        case .quiet: return Brand.textMuted
        case .ok: return Brand.room
        case .warn: return Brand.amber
        }
    }
    var body: some View {
        Text(text).font(.system(size: 11.5)).lineLimit(1).fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(tone == .neutral || tone == .quiet ? Color.clear : color.opacity(0.06)))
            .overlay(Capsule().strokeBorder(tone == .quiet ? Brand.wash(0.06) : tone == .neutral ? Brand.wash(0.10) : color.opacity(0.3), lineWidth: 1))
    }
}

/// "34.4 GB selected · rebuilt on their own": the number at 15 pt medium, the rest muted.
struct NightTotal: View {
    var strong: String
    var rest: String
    var body: some View {
        (Text(strong).font(.system(size: 15, weight: .medium)).foregroundStyle(Brand.textPrimary)
         + Text(" " + rest).font(.system(size: 13)).foregroundStyle(Brand.textMuted))
            .monospacedDigit().lineLimit(1)
    }
}

/// Plain words for an empty or waiting list. No box, no illustration.
struct NightEmpty: View {
    var title: String
    var message: String
    var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textPrimary)
            }
            Text(message).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Brand.wash(0.07)).frame(height: 1) }
    }
}
