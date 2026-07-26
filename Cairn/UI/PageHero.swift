import SwiftUI

/// The shared full-bleed hero band every page wears — title, one line of copy,
/// actions on the left; the slim white-centred ring on the right; the mountain
/// artwork bleeding edge to edge behind it.
///
/// Deliberately NOT generic. An earlier generic version (`PageHero<Actions>` +
/// `HeroPage<Hero, Content>`) nested generic view types several layers deep on
/// every page, and SwiftUI burned 100% of the main thread instantiating generic
/// metadata — the app hung on navigation. Actions are type-erased to `AnyView`
/// once, here, so each page contributes one concrete view type.
struct PageHero: View {
    let title: String
    let subtitle: String
    /// Ring fill 0…1. Pass nil to hide the ring (pages with no headline total).
    var progress: Double?
    /// Big number in the ring, in bytes.
    var value: Int64 = 0
    var caption: String = "Reclaimable"
    var footnote: String = ""
    var actions: AnyView = AnyView(EmptyView())

    init(title: String,
         subtitle: String,
         progress: Double? = nil,
         value: Int64 = 0,
         caption: String = "Reclaimable",
         footnote: String = "",
         @ViewBuilder actions: () -> some View = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.value = value
        self.caption = caption
        self.footnote = footnote
        self.actions = AnyView(actions())
    }

    var body: some View {
        ZStack(alignment: .top) {
            HeroBanner()   // the real artwork, full width

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 11) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.textSecondary)
                        .frame(maxWidth: 400, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 9) { actions }
                        .padding(.top, 2)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 8)

                if let progress {
                    let split = Fmt.split(value)
                    ScanRing(progress: progress, value: split.value, unit: split.unit,
                             caption1: caption, caption2: footnote)
                        .frame(width: 158, height: 158)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .frame(maxWidth: Brand.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 196)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

extension View {
    /// Standard page padding under a hero: capped content width, consistent inset.
    func heroPageContent() -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: Brand.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}
