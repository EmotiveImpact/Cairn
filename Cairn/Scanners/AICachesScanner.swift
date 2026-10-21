import Foundation

/// Local AI model stores & tool caches — the novel pillar (SPEC §3.2).
///
/// Two kinds of target live here:
///  • MODEL STORES — multi-gigabyte downloaded weights (Ollama, Hugging Face,
///    PyTorch, LM Studio, Whisper, GPT4All, Stable Diffusion / ComfyUI, local
///    embeddings). These are expensive to re-download (the only local copy of a
///    multi-GB weight may be unique or costly to reacquire) → advice only. Trees can be huge, so sizing is file-capped and the size is
///    surfaced as a lower bound ("(partial size)" auto-appended by makeItem).
///  • APP CACHES — Electron/Chromium caches for AI desktop apps (Claude,
///    Windsurf). Pure throwaway caches recreated on launch → SAFE, pre-selected,
///    but blocked until the owning app quits (requiresQuitBundleIDs).
///
/// All targets are plain user-owned dirs (0700) → no Full Disk Access needed.
/// (Cursor is intentionally NOT included here — it is handled by IDECachesScanner.)
struct AICachesScanner: CairnScanner {
    let info = CategoryInfo(
        id: "ai-models",
        title: "AI Model Stores & Caches",
        subtitle: "Ollama, Hugging Face, PyTorch, LM Studio, Whisper, GPT4All, ComfyUI…",
        systemImage: "brain.head.profile",
        group: .ai,
        requiresFDA: false
    )

    /// Sizing cap for model stores — these trees can be enormous; when hit the
    /// size becomes a lower bound and "(partial size)" is auto-appended.
    private let modelMaxFiles = 60_000

    /// A model-store target: (home-relative path, note).
    private struct ModelStore { let rel: String; let note: String }

    /// A generated-media target: (home-relative path, note). Holds AI-rendered
    /// outputs — re-render to restore → REVIEW, never pre-selected.
    private struct GeneratedMedia { let rel: String; let note: String }

    /// An app-cache target: (home-relative path, app display name, owning bundle ids).
    private struct AppCache { let rel: String; let app: String; let bundleIDs: [String] }

    // MARK: - Model stores (advice only)

    private var modelStores: [ModelStore] {
        [
            .init(rel: ".ollama/models", note: "Ollama models — re-pull with 'ollama pull'"),
            .init(rel: ".cache/huggingface/hub", note: "Hugging Face model cache — most expensive to re-download"),
            .init(rel: ".cache/torch", note: "PyTorch model cache"),
            .init(rel: ".cache/torch/hub", note: "PyTorch model cache"),
            .init(rel: ".lmstudio/models", note: "LM Studio models"),
            .init(rel: ".cache/lm-studio/models", note: "LM Studio models"),
            .init(rel: "Library/Application Support/LM Studio/models", note: "LM Studio models"),
            .init(rel: ".cache/whisper", note: "Whisper models"),
            .init(rel: ".cache/whisper.cpp", note: "Whisper models"),
            .init(rel: "Library/Application Support/GPT4All", note: "GPT4All models"),
            .init(rel: "Library/Application Support/nomic.ai/GPT4All", note: "GPT4All models"),
            .init(rel: "stable-diffusion-webui/models", note: "Stable Diffusion / ComfyUI models"),
            .init(rel: "ComfyUI/models", note: "Stable Diffusion / ComfyUI models"),
            .init(rel: "comfyui/models", note: "Stable Diffusion / ComfyUI models"),
            .init(rel: ".cache/sentence_transformers", note: "local embedding model cache"),
            .init(rel: ".cache/clip", note: "local embedding model cache"),
            .init(rel: "Library/Application Support/Jan/data/models", note: "Jan models — re-download from the model hub"),
            .init(rel: ".jan", note: "Jan models — re-download from the model hub"),
            .init(rel: "invokeai/models", note: "InvokeAI models — re-download from the model hub"),
            .init(rel: ".invokeai/models", note: "InvokeAI models — re-download from the model hub"),
            .init(rel: "Fooocus/models", note: "Fooocus models — re-download from the model hub"),
        ]
    }

    // MARK: - Generated media (advice only)

    private var generatedMedia: [GeneratedMedia] {
        [
            .init(rel: "ComfyUI/output", note: "AI-generated outputs — re-render to restore"),
            .init(rel: "comfyui/output", note: "AI-generated outputs — re-render to restore"),
            .init(rel: "invokeai/outputs", note: "AI-generated outputs — re-render to restore"),
            .init(rel: "stable-diffusion-webui/outputs", note: "AI-generated outputs — re-render to restore"),
            .init(rel: "Fooocus/outputs", note: "AI-generated outputs — re-render to restore"),
        ]
    }

    // MARK: - App caches (SAFE · trash · pre-selected · quit-first)

    private var appCaches: [AppCache] {
        let claude = ["com.anthropic.claudefordesktop"]
        let windsurf = ["com.codeium.windsurf"]
        let chatgpt = ["com.openai.chat"]
        return [
            .init(rel: "Library/Application Support/Claude/Cache", app: "Claude", bundleIDs: claude),
            .init(rel: "Library/Application Support/Claude/Code Cache", app: "Claude", bundleIDs: claude),
            .init(rel: "Library/Application Support/Claude/GPUCache", app: "Claude", bundleIDs: claude),
            .init(rel: "Library/Application Support/Claude/Service Worker/CacheStorage", app: "Claude", bundleIDs: claude),
            .init(rel: "Library/Application Support/Windsurf/Cache", app: "Windsurf", bundleIDs: windsurf),
            .init(rel: "Library/Application Support/Windsurf/Code Cache", app: "Windsurf", bundleIDs: windsurf),
            .init(rel: "Library/Application Support/Windsurf/GPUCache", app: "Windsurf", bundleIDs: windsurf),
            .init(rel: "Library/Application Support/com.openai.chat/Cache", app: "ChatGPT", bundleIDs: chatgpt),
            .init(rel: "Library/Application Support/com.openai.chat/Code Cache", app: "ChatGPT", bundleIDs: chatgpt),
            .init(rel: "Library/Application Support/com.openai.chat/GPUCache", app: "ChatGPT", bundleIDs: chatgpt),
        ]
    }

    // MARK: - Scan

    func scan(_ ctx: ScanContext) async {
        // Model stores — expensive-to-reacquire weights → REVIEW, never pre-selected.
        for store in modelStores {
            if ctx.isCancelled() { return }
            let url = FileScan.home.appendingPathComponent(store.rel)
            ctx.progress(url.lastPathComponent)
            if let item = makeItem(
                at: url,
                severity: .review,
                minSize: ctx.minSizeBytes,
                isRegenerable: true,
                cleanMethod: .trash,
                note: store.note + " — re-downloaded when you next use the model",
                selectedIfSafe: false,
                maxFiles: modelMaxFiles
            ) {
                ctx.emit(item)
            }
        }

        // Generated media can be the only exact copy. Show size, never delete.
        for media in generatedMedia {
            if ctx.isCancelled() { return }
            let url = FileScan.home.appendingPathComponent(media.rel)
            ctx.progress(url.lastPathComponent)
            if let item = makeItem(
                at: url,
                severity: .review,
                minSize: ctx.minSizeBytes,
                isRegenerable: false,
                cleanMethod: .trash,
                note: media.note,
                selectedIfSafe: false,
                maxFiles: modelMaxFiles
            ) {
                ctx.emit(item)
            }
        }

        // App caches — throwaway Electron/Chromium caches → SAFE, pre-selected,
        // but blocked until the owning app quits.
        for cache in appCaches {
            if ctx.isCancelled() { return }
            let url = FileScan.home.appendingPathComponent(cache.rel)
            ctx.progress("\(cache.app) cache")
            if let item = makeItem(
                at: url,
                severity: .safe,
                minSize: ctx.minSizeBytes,
                isRegenerable: true,
                requiresQuitBundleIDs: cache.bundleIDs,
                cleanMethod: .trash,
                note: "\(cache.app) cache — recreated on launch",
                selectedIfSafe: true
            ) {
                ctx.emit(item)
            }
        }
    }
}
