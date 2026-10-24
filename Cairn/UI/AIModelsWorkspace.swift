import SwiftUI
import AppKit

/// Clean › AI Models: every model downloaded by a local AI tool, largest
/// first, with its size and when it was downloaded. Models take a long time
/// to fetch again, so nothing is selected for you. Removing one goes to the
/// Trash, or through the tool's own command where models share files.
struct AIModelsWorkspace: View {
    var search: String = ""

    @State private var models: [LocalModel] = []
    @State private var total: Int64 = 0
    @State private var loading = false
    @State private var loaded = false
    @State private var selected: String?
    @State private var confirmTrash: LocalModel?
    @State private var message = ""
    private let preview = CommandLine.arguments.contains("--preview-ui")

    private var visible: [LocalModel] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return models.filter { query.isEmpty || $0.name.lowercased().contains(query) || $0.tool.lowercased().contains(query) }
    }
    private var largest: Int64 { max(1, models.map(\.bytes).max() ?? 1) }
    private var chosen: LocalModel? { models.first { $0.id == selected } }
    private var tools: [String] {
        var seen = Set<String>()
        return models.map { $0.tool.components(separatedBy: " · ").first ?? $0.tool }.filter { seen.insert($0).inserted }
    }

    var body: some View {
        NightPage(eyebrow: "AI models",
                  title: models.isEmpty ? "AI models" : "\(Fmt.size(total)) of AI models",
                  subtitle: subtitle) {
            Button { Task { await load() } } label: {
                Label(loading ? "Looking…" : "Look again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ControlPanelButtonStyle(size: .small))
            .disabled(loading)
        } content: {
            list
        } footer: {
            if let model = chosen {
                NightTotal(strong: Fmt.size(model.bytes), rest: model.name)
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.url]) }
                    .buttonStyle(ControlPanelButtonStyle(size: .large))
                switch model.removal {
                case .command(let command):
                    Button("Copy \(command)") { copy(command) }
                        .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                        .help("Ollama models share files, so Ollama's own command frees exactly the right ones. Paste it into Terminal.")
                case .trash:
                    Button("Move to Trash") { confirmTrash = model }
                        .buttonStyle(ControlPanelButtonStyle(primary: true, size: .large))
                        .disabled(preview)
                }
            } else {
                NightTotal(strong: "\(models.count)", rest: models.count == 1 ? "model on this Mac" : "models on this Mac")
                Spacer()
                if !message.isEmpty {
                    Text(message).font(.system(size: 12)).foregroundStyle(Brand.textMuted).lineLimit(2)
                }
            }
        }
        .task { if !loaded { await load() } }
        .alert("Move \(confirmTrash?.name ?? "this model") to the Trash?", isPresented: Binding(get: { confirmTrash != nil }, set: { if !$0 { confirmTrash = nil } })) {
            Button("Cancel", role: .cancel) { confirmTrash = nil }
            Button("Move to Trash", role: .destructive) { if let model = confirmTrash { trash(model) } }
        } message: {
            Text("\(confirmTrash.map { Fmt.size($0.bytes) } ?? "") goes to the Trash, where you can put it back. \(confirmTrash?.tool ?? "The tool") will download it again the next time you use it, which can take a while.")
        }
    }

    private var subtitle: String {
        if models.isEmpty { return "Models downloaded by Ollama, LM Studio, Hugging Face, Whisper, ComfyUI and other local AI tools." }
        let names = tools.prefix(3).joined(separator: ", ")
        return "From \(names)\(tools.count > 3 ? " and \(tools.count - 3) more" : ""). Models are slow to download again, so Cairn never picks one for you."
    }

    @ViewBuilder private var list: some View {
        if loading && models.isEmpty {
            NightEmpty(title: "Looking for AI models", message: "Reading the folders local AI tools download models into.", busy: true)
        } else if models.isEmpty {
            NightEmpty(title: loaded ? "No AI models found" : "Not looked yet",
                       message: loaded ? "Cairn found no models from Ollama, LM Studio, Hugging Face, Whisper, ComfyUI or similar tools."
                                       : "Press Look again to list the models on this Mac.")
        } else if visible.isEmpty {
            NightEmpty(title: "No matching models", message: "Try another name. Escape clears the filter.")
        } else {
            NightList {
                ForEach(visible) { model in row(model) }
            }
        }
    }

    private func row(_ model: LocalModel) -> some View {
        Button { selected = selected == model.id ? nil : model.id } label: {
            HStack(spacing: 14) {
                NightName(logo: BrandLogo(name: nil, fallback: "brain.head.profile", size: 25),
                          title: model.name, subtitle: model.tool)
                NightMeter(share: Double(model.bytes) / Double(largest))
                Text((model.partial ? "≥ " : "") + Fmt.size(model.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit()
                    .frame(width: 90, alignment: .trailing)
                Text(updated(model)).font(.system(size: 12)).foregroundStyle(Brand.textMuted)
                    .lineLimit(1).frame(width: 120, alignment: .leading)
                NightPill(text: selected == model.id ? "Selected" : model.removal == .trash ? "Trash" : "Ollama command",
                          tone: selected == model.id ? .ok : .neutral)
                    .frame(width: 120, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .nightRow()
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.url]) }
            if case .command(let command) = model.removal { Button("Copy \(command)") { copy(command) } }
            Button("Copy path") { copy(model.url.path) }
        }
        .help(model.url.path)
    }

    private func updated(_ model: LocalModel) -> String {
        guard let date = model.updated else { return "Unknown" }
        return "Added " + date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        message = "Copied. Paste it into Terminal."
    }

    private func trash(_ model: LocalModel) {
        confirmTrash = nil
        guard !preview else { return }
        do {
            _ = try LocalModels.moveToTrash(model)
            models.removeAll { $0.id == model.id }
            total = max(0, total - model.bytes)
            selected = nil
            message = "\(model.name) is in the Trash. Empty the Trash to get the \(Fmt.size(model.bytes)) back."
        } catch {
            message = "\(model.name) was not moved: \(error.localizedDescription)"
        }
    }

    private func load() async {
        guard !preview else {
            models = Self.sample
            total = models.reduce(0) { $0 + $1.bytes }
            selected = models.dropFirst().first?.id
            loaded = true
            return
        }
        loading = true
        let (found, sum) = await Task.detached(priority: .userInitiated) { () -> ([LocalModel], Int64) in
            let found = LocalModels.find()
            return (found, LocalModels.total(found))
        }.value
        models = found
        total = sum
        if let selected, !found.contains(where: { $0.id == selected }) { self.selected = nil }
        loading = false
        loaded = true
    }

    /// Sample rows for `--preview-ui` screenshots. Nothing on disk.
    private static let sample: [LocalModel] = {
        let gb: Int64 = 1_000_000_000
        let now = Date()
        return [
            LocalModel(url: URL(fileURLWithPath: "/sample/ollama/llama3.1-70b"), name: "llama3.1:70b", tool: "Ollama", bytes: 40 * gb,
                       updated: now.addingTimeInterval(-80 * 86_400), removal: .command("ollama rm llama3.1:70b")),
            LocalModel(url: URL(fileURLWithPath: "/sample/hf/flux"), name: "black-forest-labs/FLUX.1-dev", tool: "Hugging Face", bytes: 23 * gb,
                       updated: now.addingTimeInterval(-40 * 86_400), removal: .trash),
            LocalModel(url: URL(fileURLWithPath: "/sample/lmstudio/qwen"), name: "Qwen2.5-Coder-32B-Instruct-GGUF", tool: "LM Studio", bytes: 19 * gb,
                       updated: now.addingTimeInterval(-12 * 86_400), removal: .trash),
            LocalModel(url: URL(fileURLWithPath: "/sample/ollama/qwen3"), name: "qwen3:8b", tool: "Ollama", bytes: 5 * gb,
                       updated: now.addingTimeInterval(-3 * 86_400), removal: .command("ollama rm qwen3:8b")),
            LocalModel(url: URL(fileURLWithPath: "/sample/whisper/large"), name: "large-v3.pt", tool: "Whisper", bytes: 3 * gb,
                       updated: now.addingTimeInterval(-200 * 86_400), removal: .trash),
        ]
    }()
}
