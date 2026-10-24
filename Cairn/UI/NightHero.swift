import SwiftUI

/// The big light number that leads a page, from the feature mocks
/// (design/new-pages): 64 pt light number, a 19 pt muted phrase after it on
/// the same baseline, and one 13.5 pt line underneath.
struct NightHero: View {
    var number: String
    var phrase: String
    var lead: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(number).font(.system(size: 64, weight: .light)).tracking(-2.5)
                    .monospacedDigit().foregroundStyle(Brand.textPrimary)
                    .contentTransition(.numericText())
                Text(phrase).font(.system(size: 19)).foregroundStyle(Brand.textMuted)
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            if !lead.isEmpty {
                Text(lead).font(.system(size: 13.5)).foregroundStyle(Brand.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 600, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }
}

/// NightPage with a NightHero in place of the 40 pt title. Same padding,
/// eyebrow row and footer, 18 pt between sections as in the mocks.
struct NightNumberPage<Trailing: View, Content: View, Footer: View>: View {
    var eyebrow: String
    var number: String
    var phrase: String
    var lead: String = ""
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 8) {
                Text(eyebrow).nightEyebrow().lineLimit(1)
                Spacer(minLength: 12)
                trailing()
            }
            .frame(height: 28)
            NightHero(number: number, phrase: phrase, lead: lead)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .center, spacing: 12) { footer() }
        }
        .padding(.top, 22).padding(.horizontal, 40).padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Brand.textPrimary)
    }
}

/// A soft inset note under an opened row: amber when something needs care,
/// ice when it is information. 10 pt corners, a 1 pt inner edge.
struct NightNote<Trailing: View>: View {
    enum Tone { case info, warn }
    var tone: Tone = .info
    var strong: String = ""
    var text: String
    @ViewBuilder var trailing: () -> Trailing

    private var tint: Color { tone == .warn ? Brand.amber : Brand.room }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            (Text(strong.isEmpty ? "" : strong + " ").foregroundStyle(tone == .warn ? Brand.amber : Brand.textPrimary).fontWeight(.medium)
             + Text(text).foregroundStyle(Brand.textSecondary))
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(tone == .warn ? 0.06 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(tone == .warn ? 0.16 : 0.12), lineWidth: 1))
    }
}

extension NightNote where Trailing == EmptyView {
    init(tone: Tone = .info, strong: String = "", text: String) {
        self.init(tone: tone, strong: strong, text: text, trailing: { EmptyView() })
    }
}

/// A blue text action ("Copy git push", "Run now"): 12 pt ice, no box.
struct NightLink: View {
    var title: String
    var systemImage: String?
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 11)) }
                Text(title)
            }
            .font(.system(size: 12)).foregroundStyle(Brand.room)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
