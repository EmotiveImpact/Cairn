import Foundation

/// Connects Cairn's read-only MCP server (`Cairn mcp`) to AI coding tools on
/// this Mac by adding one `cairn` entry to each tool's own MCP config file.
///
/// Only that entry is written. Every other setting in the file is kept, a file
/// Cairn cannot parse (JSON with comments, for example) is left untouched, and
/// the previous file is kept beside it as `<name>.cairn-backup` before the
/// first change. Claude Code keeps its settings in a large, busy file, so it is
/// connected through its own `claude mcp add` command instead.
struct AgentTool: Identifiable, Equatable {
    enum Format: Equatable {
        /// `key` holds a server table; VS Code also wants `"type": "stdio"`.
        case json(key: String, typed: Bool)
        case codexTOML
        case claudeCLI
    }

    let id: String
    let title: String
    let config: URL
    let format: Format
    /// Folder whose presence shows the tool is installed or has been used.
    let marker: URL

    static let serverName = "cairn"

    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentTool] {
        let support = home.appendingPathComponent("Library/Application Support")
        return [
            AgentTool(id: "claude-code", title: "Claude Code", config: home.appendingPathComponent(".claude.json"),
                      format: .claudeCLI, marker: home.appendingPathComponent(".claude")),
            AgentTool(id: "claude-desktop", title: "Claude Desktop", config: support.appendingPathComponent("Claude/claude_desktop_config.json"),
                      format: .json(key: "mcpServers", typed: false), marker: support.appendingPathComponent("Claude")),
            AgentTool(id: "codex", title: "Codex", config: home.appendingPathComponent(".codex/config.toml"),
                      format: .codexTOML, marker: home.appendingPathComponent(".codex")),
            AgentTool(id: "cursor", title: "Cursor", config: home.appendingPathComponent(".cursor/mcp.json"),
                      format: .json(key: "mcpServers", typed: false), marker: home.appendingPathComponent(".cursor")),
            AgentTool(id: "gemini", title: "Gemini CLI", config: home.appendingPathComponent(".gemini/settings.json"),
                      format: .json(key: "mcpServers", typed: false), marker: home.appendingPathComponent(".gemini")),
            AgentTool(id: "vscode", title: "VS Code", config: support.appendingPathComponent("Code/User/mcp.json"),
                      format: .json(key: "servers", typed: true), marker: support.appendingPathComponent("Code/User")),
            AgentTool(id: "windsurf", title: "Windsurf", config: home.appendingPathComponent(".codeium/windsurf/mcp_config.json"),
                      format: .json(key: "mcpServers", typed: false), marker: home.appendingPathComponent(".codeium/windsurf")),
        ]
    }
}

enum AgentConnections {
    enum State: Equatable {
        case notInstalled
        case available
        case connected(current: Bool)
        /// The config exists but Cairn will not edit it; the text says why.
        case unreadable(String)
    }

    struct Failure: Error { let message: String }

    static let backupSuffix = ".cairn-backup"

    /// The executable an agent should launch. Inside an app bundle this is the
    /// bundle's own binary, so no command-line install is needed.
    static var command: String { Bundle.main.executableURL?.path ?? "/usr/local/bin/cairn" }

    /// Terminal command for tools Cairn does not edit, or when it cannot.
    static func manualCommand(_ command: String = command) -> String {
        "claude mcp add --scope user \(AgentTool.serverName) -- \(CLIInstallPolicy.quoteForShell(command)) mcp"
    }

    // MARK: - State

    static func state(_ tool: AgentTool, command: String = command) -> State {
        let fm = FileManager.default
        guard fm.fileExists(atPath: tool.marker.path) || fm.fileExists(atPath: tool.config.path) else { return .notInstalled }
        guard fm.fileExists(atPath: tool.config.path) else { return .available }
        switch tool.format {
        case .json(let key, _):
            guard let root = readJSON(tool.config) else { return .unreadable("\(tool.config.lastPathComponent) is not plain JSON, so Cairn leaves it alone.") }
            guard let entry = (root[key] as? [String: Any])?[AgentTool.serverName] as? [String: Any] else { return .available }
            return .connected(current: entry["command"] as? String == command)
        case .claudeCLI:
            guard let root = readJSON(tool.config) else { return .available }
            guard let entry = (root["mcpServers"] as? [String: Any])?[AgentTool.serverName] as? [String: Any] else { return .available }
            return .connected(current: entry["command"] as? String == command)
        case .codexTOML:
            guard let text = try? String(contentsOf: tool.config, encoding: .utf8) else { return .unreadable("Cairn could not read config.toml.") }
            guard let range = codexTable(in: text) else { return .available }
            return .connected(current: text[range].contains("command = \(tomlString(command))"))
        }
    }

    // MARK: - Connect and disconnect

    static func connect(_ tool: AgentTool, command: String = command, claudeBinary: URL? = findClaude()) throws {
        switch tool.format {
        case .json(let key, let typed):
            var root: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: tool.config.path) {
                guard let existing = readJSON(tool.config) else { throw Failure(message: "\(tool.title)'s settings file is not plain JSON, so Cairn left it unchanged.") }
                root = existing
            }
            var servers = root[key] as? [String: Any] ?? [:]
            var entry: [String: Any] = ["command": command, "args": ["mcp"]]
            if typed { entry["type"] = "stdio" }
            servers[AgentTool.serverName] = entry
            root[key] = servers
            try writeJSON(root, to: tool.config)
        case .codexTOML:
            var text = (try? String(contentsOf: tool.config, encoding: .utf8)) ?? ""
            removeCodexTable(from: &text)
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            if !text.isEmpty && !text.hasSuffix("\n\n") { text += "\n" }
            text += "[mcp_servers.\(AgentTool.serverName)]\ncommand = \(tomlString(command))\nargs = [\"mcp\"]\n"
            try write(Data(text.utf8), to: tool.config)
        case .claudeCLI:
            guard let claude = claudeBinary else {
                throw Failure(message: "Cairn could not find the claude command. Paste this into Terminal instead: \(manualCommand(command))")
            }
            // Replace an entry that points at an older copy of Cairn.
            if case .connected(current: false) = state(tool, command: command) {
                _ = try runClaude(claude, ["mcp", "remove", "--scope", "user", AgentTool.serverName])
            }
            let output = try runClaude(claude, ["mcp", "add", "--scope", "user", AgentTool.serverName, "--", command, "mcp"])
            guard output.status == 0 else { throw Failure(message: "claude mcp add failed: \(output.text)") }
        }
    }

    static func disconnect(_ tool: AgentTool, claudeBinary: URL? = findClaude()) throws {
        guard FileManager.default.fileExists(atPath: tool.config.path) else { return }
        switch tool.format {
        case .json(let key, _):
            guard var root = readJSON(tool.config) else { throw Failure(message: "\(tool.title)'s settings file is not plain JSON, so Cairn left it unchanged.") }
            guard var servers = root[key] as? [String: Any], servers[AgentTool.serverName] != nil else { return }
            servers.removeValue(forKey: AgentTool.serverName)
            root[key] = servers
            try writeJSON(root, to: tool.config)
        case .codexTOML:
            guard var text = try? String(contentsOf: tool.config, encoding: .utf8), removeCodexTable(from: &text) else { return }
            try write(Data(text.utf8), to: tool.config)
        case .claudeCLI:
            guard let claude = claudeBinary else { throw Failure(message: "Cairn could not find the claude command. Run: claude mcp remove --scope user cairn") }
            let output = try runClaude(claude, ["mcp", "remove", "--scope", "user", AgentTool.serverName])
            guard output.status == 0 else { throw Failure(message: "claude mcp remove failed: \(output.text)") }
        }
    }

    // MARK: - Files

    static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try write(data + Data("\n".utf8), to: url)
    }

    /// Keeps the first pre-Cairn version as a backup, then replaces the file
    /// atomically. A config reached through a link is written at the link's
    /// target, so dotfile managers keep working.
    private static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let target = url.resolvingSymlinksInPath()
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = URL(fileURLWithPath: target.path + backupSuffix)
        if fm.fileExists(atPath: target.path) && !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: target, to: backup)
        }
        try data.write(to: target, options: .atomic)
    }

    // MARK: - Codex TOML

    /// The `[mcp_servers.cairn]` table, from its header to the next table.
    static func codexTable(in text: String) -> Range<String.Index>? {
        let header = "[mcp_servers.\(AgentTool.serverName)]"
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let lineEnd = text[index...].firstIndex(of: "\n").map { text.index(after: $0) } ?? text.endIndex
            let line = text[index..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            if let begin = start {
                // Sub-tables such as [mcp_servers.cairn.env] belong to the entry.
                if line.hasPrefix("[") && !line.hasPrefix("[mcp_servers.\(AgentTool.serverName).") {
                    return begin..<index
                }
            } else if line == header {
                start = index
            }
            index = lineEnd
        }
        return start.map { $0..<text.endIndex }
    }

    /// Removes the table and the blank line Cairn put before it.
    @discardableResult
    static func removeCodexTable(from text: inout String) -> Bool {
        guard let range = codexTable(in: text) else { return false }
        var start = range.lowerBound
        if text[..<start].hasSuffix("\n\n") { start = text.index(before: start) }
        text.removeSubrange(start..<range.upperBound)
        return true
    }

    static func tomlString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Claude Code

    /// GUI apps do not inherit the shell PATH, so look in the usual places.
    static func findClaude(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func runClaude(_ binary: URL, _ arguments: [String]) throws -> (status: Int32, text: String) {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
