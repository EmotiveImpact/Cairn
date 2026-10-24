import SwiftUI
import AppKit

/// Settings › AI tools: one-click setup of `Cairn mcp` in each AI coding tool.
struct AgentConnectionsPanel: View {
    @State private var states: [String: AgentConnections.State] = [:]
    @State private var message = ""
    @State private var working: String?
    @Bindable private var settings = AppSettings.shared
    private let tools = AgentTool.all()
    private let preview = CommandLine.arguments.contains("--preview-ui")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Let your AI coding tools ask Cairn what is using space, plan a cleanup and, if you allow it, free the space for you.")
                .font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 18)
            VStack(alignment: .leading, spacing: 10) {
                Text("When an AI tool wants to clean").font(.system(size: 13, weight: .medium))
                CairnSegmentedControl(label: "AI tool cleaning", selection: $settings.agentCleaning,
                                      options: AgentCleaningMode.allCases.map { ($0.title, $0) })
                    .frame(width: 460)
                Text(settings.agentCleaning.detail + " Only caches and build files that rebuild themselves qualify. Your files, AI chats and the Trash are never touched.")
                    .font(.system(size: 11.5)).foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.bottom, 18)
            Rectangle().fill(Brand.separator).frame(height: 0.5)
            ForEach(tools) { tool in row(tool) }
            HStack(spacing: 12) {
                Button("Copy Terminal command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AgentConnections.manualCommand(), forType: .string)
                    message = "Copied the Claude Code command. Other tools take the same command with the argument mcp."
                }.buttonStyle(ControlPanelButtonStyle())
                Text("For tools not listed here.").font(.system(size: 11.5)).foregroundStyle(Brand.textMuted)
            }.padding(.vertical, 18)
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Text("ChatGPT and Grok connect only to online services, so they cannot reach Cairn on this Mac yet.")
                .font(.system(size: 11.5)).foregroundStyle(Brand.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
        }
        .onAppear(perform: refresh)
    }

    private func row(_ tool: AgentTool) -> some View {
        let state: AgentConnections.State = preview ? (tool.id == "claude-code" ? .connected(current: true) : .available) : (states[tool.id] ?? .notInstalled)
        return VStack(spacing: 0) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tool.title).font(.system(size: 13, weight: .medium))
                    Text(detail(state)).font(.system(size: 11.5))
                        .foregroundStyle(state == .connected(current: true) ? Brand.safeCyan : Brand.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                switch state {
                case .available:
                    Button("Connect") { run(tool) { try AgentConnections.connect(tool) } }
                        .buttonStyle(ControlPanelButtonStyle(primary: true)).disabled(working != nil)
                case .connected(let current):
                    if !current {
                        Button("Update") { run(tool) { try AgentConnections.connect(tool) } }
                            .buttonStyle(ControlPanelButtonStyle()).disabled(working != nil)
                    }
                    Button("Disconnect") { run(tool) { try AgentConnections.disconnect(tool) } }
                        .buttonStyle(ControlPanelButtonStyle()).disabled(working != nil)
                case .notInstalled, .unreadable:
                    EmptyView()
                }
            }.padding(.vertical, 16)
            Rectangle().fill(Brand.separator).frame(height: 0.5)
        }
    }

    private func detail(_ state: AgentConnections.State) -> String {
        switch state {
        case .notInstalled: return "Not found on this Mac"
        case .available: return "Ready to connect"
        case .connected(true): return "Connected"
        case .connected(false): return "Connected to an older copy of Cairn"
        case .unreadable(let why): return why
        }
    }

    private func run(_ tool: AgentTool, _ action: @escaping () throws -> Void) {
        guard !preview else { return }
        working = tool.id
        Task.detached {
            let result: String
            do { try action(); result = "\(tool.title) updated. Restart it to pick up the change." }
            catch let failure as AgentConnections.Failure { result = failure.message }
            catch { result = "\(tool.title) was not changed: \(error.localizedDescription)" }
            await MainActor.run {
                message = result
                working = nil
                refresh()
            }
        }
    }

    private func refresh() {
        guard !preview else { return }
        var next: [String: AgentConnections.State] = [:]
        for tool in tools { next[tool.id] = AgentConnections.state(tool) }
        states = next
    }
}
