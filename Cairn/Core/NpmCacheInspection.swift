import Foundation

/// A read-only probe in Cairn's process environment. npm may use a different
/// setting for another shell, project or command-line invocation, so this is
/// evidence for planning and never proof that relocation is safe or active.
enum NpmCacheInspection {
    static func parse(_ output: String) -> String? {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 4_096, !value.isEmpty,
              !value.contains("\n"), !value.contains("\r"), !value.contains("\0"),
              value.hasPrefix("/"), !value.hasPrefix("//") else { return nil }
        let normalized = URL(fileURLWithPath: value).standardizedFileURL.path
        guard normalized != "/", normalized == value else { return nil }
        return normalized
    }

    static func inspect() -> String {
        do {
            let result = try ToolRunner.run("npm", ["config", "get", "cache"], timeout: 6)
            guard result.ok, let path = parse(result.stdout) else {
                return "npm did not return one valid absolute cache path. No configuration was changed."
            }
            return "Effective for Cairn's environment: \(path). Other shells, projects, environment variables or CLI flags may override this value. No configuration was changed."
        } catch {
            return "Cairn could not read an npm cache path in this environment. No configuration was changed."
        }
    }
}
