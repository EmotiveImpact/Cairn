import SwiftUI

/// Pro status + activation card (used on the Settings page).
struct ProStatusCard: View {
    @ObservedObject var license: LicenseManager
    @State private var key = ""
    @State private var showKeyField = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                IconTile(systemImage: "sparkles", tint: Brand.purple, size: 30, glyphScale: 0.5)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cairn Pro")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.textPrimary)
                    Text(statusLine).font(.system(size: 11)).foregroundStyle(statusColor)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            Divider().overlay(Brand.border)

            VStack(alignment: .leading, spacing: 10) {
                if license.isLoading {
                    HStack { ProgressView().controlSize(.small); Text("Checking saved license…").font(.system(size: 12)) }
                }
                if let message = license.storageMessage {
                    Text(message).font(.system(size: 12)).foregroundStyle(Brand.textSecondary).fixedSize(horizontal: false, vertical: true)
                    Button("Check again") { Task { await license.reloadStorage() } }
                        .buttonStyle(ControlPanelButtonStyle()).disabled(license.isLoading || license.isBusy)
                }
                if license.hasRequestedStorage && !license.isLoading && license.storageMessage == nil && !license.isPro {
                    Text("Purchases are not offered in this build. Broad tool cleanups are review-only while their safety checks are completed; supported actions remain available without an upgrade.")
                        .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).fixedSize(horizontal: false, vertical: true)
                    Button(showKeyField ? "Hide key" : "Enter existing key") { showKeyField.toggle() }.buttonStyle(GhostButtonStyle())
                    if showKeyField {
                        HStack(spacing: 8) {
                            HStack(spacing: 7) {
                                Image(systemName: "key.fill").font(.system(size: 11)).foregroundStyle(Brand.textMuted)
                                TextField("Paste your license key", text: $key)
                                    .textFieldStyle(.plain).font(.system(size: 12))
                                    .onSubmit { if !key.isEmpty && !license.isBusy && !license.isLoading { Task { _ = await license.activate(key: key) } } }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Brand.rSm, style: .continuous).fill(Brand.surfaceSubtle)
                                .overlay(RoundedRectangle(cornerRadius: Brand.rSm, style: .continuous)
                                    .stroke(license.lastError == nil ? Brand.inputBorder : Brand.danger.opacity(0.6), lineWidth: 1)))
                            Button("Activate") { Task { _ = await license.activate(key: key) } }
                                .buttonStyle(BrandButtonStyle(enabled: !key.isEmpty && !license.isBusy))
                                .disabled(key.isEmpty || license.isBusy || license.isLoading || license.storageMessage != nil)
                        }
                        if let err = license.lastError {
                            Text(err).font(.system(size: 11)).foregroundStyle(Brand.danger)
                        }
                    }
                } else if license.isPro {
                    HStack {
                        Text("Licensed on this Mac · thank you!").font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                        Spacer()
                        Button("Deactivate") { Task { await license.deactivate() } }.buttonStyle(GhostButtonStyle()).disabled(license.isBusy || license.isLoading)
                    }
                }
            }
            .padding(16)
        }
        .background(CardBackground())
        .task { await license.loadIfNeeded() }
    }

    private var statusLine: String {
        if !license.hasRequestedStorage { return "Your license is checked here when needed" }
        if license.isLoading { return "Checking saved license · Cairn remains available" }
        if license.storageMessage != nil { return "Saved license unavailable · free features available" }
        if license.isPro { return "Active licence · supported actions available" }
        return "Supported actions available without an upgrade"
    }
    private var statusColor: Color {
        if license.isPro { return Brand.safeCyan }
        return Brand.textMuted
    }
}
