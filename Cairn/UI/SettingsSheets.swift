import SwiftUI
import AppKit

/// "What Cairn looks for": every place Cairn checks, written from the scanners,
/// with a copy as Markdown for anyone who wants to publish or compare it.
struct RulesListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private let sections = RulesList.sections()

    var body: some View {
        CairnDialog(title: "What Cairn looks for", subtitle: "Written from the app itself, so it always matches what Cairn does.", wide: true, height: 620) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(RulesList.promises, id: \.self) { promise in
                            Label(promise, systemImage: "checkmark").font(.system(size: 12.5)).foregroundStyle(Brand.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(section.title).nightEyebrow().padding(.bottom, 4)
                            ForEach(section.entries) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title).font(.system(size: 13, weight: .medium))
                                    Text(entry.detail + (entry.needsFullDiskAccess ? " · needs Full Disk Access" : ""))
                                        .font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .nightRow()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } actions: {
            Button(copied ? "Copied" : "Copy as Markdown") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(RulesList.markdown(), forType: .string)
                copied = true
            }
            .buttonStyle(ControlPanelButtonStyle())
            Button("Done") { dismiss() }
                .buttonStyle(ControlPanelButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
        }
    }
}

/// "Send a report": the whole text, editable, before anything leaves the Mac.
/// Cairn sends nothing itself; Email hands the text to Mail for you to send.
struct ProblemReportSheet: View {
    let store: ScanStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        CairnDialog(title: "Send a report", subtitle: "This is everything in it. Add what happened at the top, change anything you like, then send it yourself. No file names, folder names or your account name are included.", wide: true, height: 600) {
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.wash(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Brand.wash(0.10), lineWidth: 1))
                .accessibilityLabel("Report text")
        } actions: {
            Button("Cancel") { dismiss() }
                .buttonStyle(ControlPanelButtonStyle()).keyboardShortcut(.cancelAction)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            }
            .buttonStyle(ControlPanelButtonStyle())
            if let address = ProblemReport.address, let mail = NSSharingService(named: .composeEmail) {
                Button("Email…") {
                    mail.recipients = [address]
                    mail.subject = ProblemReport.subject
                    mail.perform(withItems: [text])
                    dismiss()
                }
                .buttonStyle(ControlPanelButtonStyle(primary: true))
            }
        }
        .onAppear { if text.isEmpty { text = ProblemReport.text(store: store) } }
    }
}
