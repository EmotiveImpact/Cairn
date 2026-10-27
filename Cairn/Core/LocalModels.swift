import Foundation

/// One downloaded AI model on this Mac, as the tool that fetched it sees it.
struct LocalModel: Identifiable, Sendable, Equatable {
    enum Removal: Sendable, Equatable {
        /// The tool shares files between models, so only its own command frees the right ones.
        case command(String)
        /// A file or folder of its own, safe to move to the Trash.
        case trash
    }

    let url: URL
    let name: String
    let tool: String
    let bytes: Int64
    /// The last time the model's files changed, which is when it was
    /// downloaded or updated. macOS does not record when a model was last run.
    let updated: Date?
    let removal: Removal
    /// True when the size stopped at a measuring limit and is a lower bound.
    var partial = false

    var id: String { url.path }
}

/// Finds models in the stores that local AI tools use. Reads only metadata
/// and folder sizes: no model file is opened, and nothing is changed.
enum LocalModels {
    /// Files at least this large inside a generic models folder count as a model.
    static let minimumFileBytes: Int64 = 20 * 1_024 * 1_024
    private static let weightExtensions: Set<String> = ["gguf", "ggml", "safetensors", "ckpt", "pt", "pth", "bin", "onnx", "mlmodel", "mlpackage", "npz", "h5", "tflite"]

    static func find(home: URL = FileScan.home) -> [LocalModel] {
        var found: [LocalModel] = []
        found += ollama(home.appendingPathComponent(".ollama/models"))
        found += huggingFace(home.appendingPathComponent(".cache/huggingface/hub"))
        for root in [".lmstudio/models", ".cache/lm-studio/models", "Library/Application Support/LM Studio/models"] {
            found += folders(home.appendingPathComponent(root), depth: 2, tool: "LM Studio")
        }
        for root in ["Library/Application Support/nomic.ai/GPT4All", "Library/Application Support/GPT4All"] {
            found += files(home.appendingPathComponent(root), tool: "GPT4All", depth: 1)
        }
        for root in ["Library/Application Support/Jan/data/models", "jan/models"] {
            found += folders(home.appendingPathComponent(root), depth: 1, tool: "Jan")
        }
        found += files(home.appendingPathComponent(".cache/whisper"), tool: "Whisper", depth: 1)
        found += files(home.appendingPathComponent(".cache/whisper.cpp"), tool: "Whisper", depth: 2)
        found += files(home.appendingPathComponent(".cache/torch/hub/checkpoints"), tool: "PyTorch", depth: 1)
        for (root, tool) in [("ComfyUI/models", "ComfyUI"), ("comfyui/models", "ComfyUI"),
                             ("stable-diffusion-webui/models", "Stable Diffusion"), ("Fooocus/models", "Fooocus"),
                             ("invokeai/models", "InvokeAI"), (".invokeai/models", "InvokeAI"),
                             ("Library/Application Support/DiffusionBee/downloaded_assets", "DiffusionBee"),
                             ("Library/Containers/com.liuliu.draw-things/Data/Documents/Models", "Draw Things")] {
            found += files(home.appendingPathComponent(root), tool: tool, depth: 4)
        }
        // Two spellings of one folder (ComfyUI on a case-insensitive disk) must not count twice.
        var seen = Set<String>()
        return found.filter { seen.insert($0.url.resolvingSymlinksInPath().path.lowercased()).inserted }
            .sorted { $0.bytes > $1.bytes }
    }

    /// The sum the page shows. Ollama models can share layers, so their
    /// shared files are counted once.
    static func total(_ models: [LocalModel], home: URL = FileScan.home) -> Int64 {
        let others = models.filter { $0.tool != "Ollama" }.reduce(0) { $0 + $1.bytes }
        let ollama = models.contains { $0.tool == "Ollama" }
            ? FileScan.measure(home.appendingPathComponent(".ollama/models/blobs"), maxDuration: 6).allocatedSize : 0
        return others + ollama
    }

    // MARK: - Ollama

    /// `manifests/<registry>/<namespace>/<model>/<tag>`, each a small JSON
    /// list of the layers that make up one model.
    static func ollama(_ root: URL) -> [LocalModel] {
        let manifests = root.appendingPathComponent("manifests")
        guard let enumerator = FileManager.default.enumerator(at: manifests, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]) else { return [] }
        var models: [LocalModel] = []
        for case let file as URL in enumerator {
            // The enumerator can hand back /private/var for /var, so count
            // levels rather than trimming the root's spelling off the path.
            guard enumerator.level == 4 else { continue }
            let parts = Array(file.pathComponents.suffix(4))
            guard parts.count == 4,
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: file), data.count < 1_000_000,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let layers = (json["layers"] as? [[String: Any]] ?? []) + [json["config"] as? [String: Any] ?? [:]]
            let bytes = layers.reduce(Int64(0)) { $0 + ((($1["size"] as? NSNumber)?.int64Value) ?? 0) }
            let (registry, namespace, model, tag) = (parts[0], parts[1], parts[2], parts[3])
            var name = namespace == "library" ? "\(model):\(tag)" : "\(namespace)/\(model):\(tag)"
            if registry != "registry.ollama.ai" { name = "\(registry)/\(name)" }
            let updated = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            models.append(LocalModel(url: file, name: name, tool: "Ollama", bytes: bytes, updated: updated,
                                     removal: .command("ollama rm \(name)")))
        }
        return models
    }

    // MARK: - Hugging Face

    /// `models--<org>--<name>` folders in the hub cache.
    static func huggingFace(_ hub: URL) -> [LocalModel] {
        (FileScan.children(of: hub) ?? []).compactMap { folder in
            let base = folder.lastPathComponent
            guard base.hasPrefix("models--") else { return nil }
            let name = base.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
            let stats = FileScan.measure(folder, maxDuration: 6)
            guard stats.allocatedSize > 0 else { return nil }
            return LocalModel(url: folder, name: name, tool: "Hugging Face", bytes: stats.allocatedSize,
                              updated: date(stats), removal: .trash, partial: stats.truncated)
        }
    }

    // MARK: - Plain folders and files

    /// Each folder `depth` levels down is one model (LM Studio: publisher/model).
    static func folders(_ root: URL, depth: Int, tool: String) -> [LocalModel] {
        var level = [root]
        for _ in 0..<depth {
            level = level.flatMap { folder in
                (FileScan.children(of: folder) ?? []).filter { child in
                    !child.lastPathComponent.hasPrefix(".") && (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                }
            }
        }
        return level.compactMap { folder in
            let stats = FileScan.measure(folder, maxDuration: 6)
            guard stats.allocatedSize >= minimumFileBytes else { return nil }
            return LocalModel(url: folder, name: folder.lastPathComponent, tool: tool, bytes: stats.allocatedSize,
                              updated: date(stats), removal: .trash, partial: stats.truncated)
        }
    }

    /// Model weight files up to `depth` levels down.
    static func files(_ root: URL, tool: String, depth: Int) -> [LocalModel] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var models: [LocalModel] = []
        var visited = 0
        for case let file as URL in enumerator {
            visited += 1
            if visited > 50_000 { break }
            if enumerator.level > depth { enumerator.skipDescendants(); continue }
            let ext = file.pathExtension.lowercased()
            guard weightExtensions.contains(ext), let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            // Core ML packages are folders; everything else is one file.
            let bytes: Int64
            if values.isDirectory == true {
                bytes = FileScan.measure(file, maxDuration: 4).allocatedSize
            } else {
                guard values.isRegularFile == true else { continue }
                bytes = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
            guard bytes >= minimumFileBytes else { continue }
            let kind = file.deletingLastPathComponent().path == root.path ? "" : file.deletingLastPathComponent().lastPathComponent
            models.append(LocalModel(url: file, name: file.lastPathComponent,
                                     tool: kind.isEmpty ? tool : "\(tool) · \(kind)", bytes: bytes,
                                     updated: values.contentModificationDate, removal: .trash))
        }
        return models
    }

    private static func date(_ stats: DirStats) -> Date? {
        stats.latestModified == .distantPast ? nil : stats.latestModified
    }

    /// Every folder Cairn looks in. A model can only be moved to the Trash
    /// from inside one of these.
    static func storeRoots(home: URL = FileScan.home) -> [URL] {
        [".cache/huggingface/hub", ".lmstudio/models", ".cache/lm-studio/models", "Library/Application Support/LM Studio/models",
         "Library/Application Support/nomic.ai/GPT4All", "Library/Application Support/GPT4All",
         "Library/Application Support/Jan/data/models", "jan/models", ".cache/whisper", ".cache/whisper.cpp",
         ".cache/torch/hub/checkpoints", "ComfyUI/models", "comfyui/models", "stable-diffusion-webui/models",
         "Fooocus/models", "invokeai/models", ".invokeai/models",
         "Library/Application Support/DiffusionBee/downloaded_assets",
         "Library/Containers/com.liuliu.draw-things/Data/Documents/Models"].map { home.appendingPathComponent($0) }
    }

    /// Moves one model to the Trash after the same safety check every clean
    /// uses. Returns the Trash location. The space comes back once the Trash
    /// is emptied, so callers must not report it as freed.
    static func moveToTrash(_ model: LocalModel, home: URL = FileScan.home) throws -> URL? {
        guard model.removal == .trash, FileManager.default.fileExists(atPath: model.url.path) else { return nil }
        if case .reject(let reason) = SafePaths.evaluate(model.url, allowedRoots: storeRoots(home: home)) {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "Cairn will not move this model: \(reason)."])
        }
        var trashed: NSURL?
        try FileManager.default.trashItem(at: model.url, resultingItemURL: &trashed)
        return trashed as URL?
    }
}
