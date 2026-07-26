import SwiftUI

/// In-app transparency: What's New, a plain-language Bugs & Fixes log, and the
/// safety promises. Most cleaners hide behind marketing — Cairn shows its work.
enum AppInfo {
    static let version = "1.0.0"

    struct Release: Identifiable { let id = UUID(); let version: String; let date: String; let highlights: [String] }
    struct Fix: Identifiable { let id = UUID(); let title: String; let detail: String }

    static let releases: [Release] = [
        Release(version: "1.0.0", date: "2026", highlights: [
            "Three cleaning pillars: Developer, AI Models & Caches, and Creative Pro.",
            "Dev-Project Explorer: finds node_modules, Rust target, .venv, Pods, SwiftPM, Unity, Unreal and Flutter build artifacts across your disk.",
            "AI Space Cleaner: Ollama, Hugging Face, LM Studio, Stable Diffusion, Whisper and GPT4All model stores.",
            "Creative Pro Cleaner: Adobe, Final Cut, Motion, Logic, DaVinci, Topaz and CapCut caches, plus stray screen recordings and exports.",
            "Space Missions: one-click intents like Free 10 GB Fast, Clean AI Models and Prepare for Travel.",
            "Safety first: Trash-by-default with undo, computed SAFE/REVIEW/RISKY tiers, and a running-app guard.",
        ]),
    ]

    static let fixes: [Fix] = [
        Fix(title: "No more AppleScript for deletes",
            detail: "Removals use the system Trash API directly — recoverable, with no fragile scripting that a tricky file name could exploit."),
        Fix(title: "Honest sizes, never a silent undercount",
            detail: "If Full Disk Access is missing, items are flagged ‘partial’ instead of quietly reading as smaller than they are."),
        Fix(title: "Won't clean caches an app is actively using",
            detail: "Items owned by a running app (Xcode, Docker, your editor) are blocked until you quit it, so a live build is never corrupted."),
        Fix(title: "Fast scans on huge home folders",
            detail: "The whole-disk project hunt is bounded and sizes folders in parallel, so results stream in while you watch."),
        Fix(title: "node_modules is only ‘safe’ when it really is",
            detail: "Monorepo workspaces, npm-link, file: deps and patch-package are detected; anything uncertain is shown as Review, not auto-selected."),
    ]

    static let promises: [String] = [
        "Moves to the Trash by default — you can always put it back.",
        "Never touches your documents, photos, Mail, Messages, keychains or app databases.",
        "Runs the correct tool per target (git gc, simctl, docker prune) instead of blind rm.",
        "No background daemon, no account, no behavioural tracking.",
        "Every item shows what it is, why it exists, and whether it rebuilds itself.",
    ]
}

struct TransparencyPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "mountain.2.fill").foregroundStyle(Brand.brand)
                    Text("Cairn \(AppInfo.version)").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Brand.textPrimary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.textMuted) }
                    .buttonStyle(.plain)
            }
            .padding(16)

            Picker("", selection: $tab) {
                Text("What's New").tag(0)
                Text("Bugs & Fixes").tag(1)
                Text("Safety").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case 0: whatsNew
                    case 1: bugsAndFixes
                    default: safety
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .frame(width: 540, height: 460)
        .background(Brand.deepPanel)
    }

    private var whatsNew: some View {
        ForEach(AppInfo.releases) { r in
            VStack(alignment: .leading, spacing: 8) {
                Text("Version \(r.version) · \(r.date)")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.cyan)
                ForEach(r.highlights, id: \.self) { h in bullet(h, "sparkle") }
            }
        }
    }

    private var bugsAndFixes: some View {
        ForEach(AppInfo.fixes) { f in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.safeCyan).font(.system(size: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                    Text(f.detail).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }

    private var safety: some View {
        ForEach(AppInfo.promises, id: \.self) { p in bullet(p, "lock.shield.fill") }
    }

    private func bullet(_ text: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Brand.purple).font(.system(size: 12))
            Text(text).font(.system(size: 13)).foregroundStyle(Brand.textSecondary)
        }
    }
}
