import Foundation

/// What git says about a project: work that is not committed or not pushed.
/// Read with `git status`, which never changes the repository. Cairn passes
/// `--no-optional-locks` so the read cannot leave or wait on an index lock.
struct GitStatus: Equatable, Sendable {
    var branch: String?
    var upstream: String?
    var ahead = 0
    var behind = 0
    var changed = 0
    var untracked = 0

    /// Nothing that only exists on this Mac: committed, and pushed somewhere.
    var backedUp: Bool { changed == 0 && untracked == 0 && upstream != nil && ahead == 0 }

    /// Short words for the project row, such as "main · 2 changed · 3 not pushed".
    var summary: String {
        var parts: [String] = []
        if let branch { parts.append(branch) }
        if changed > 0 { parts.append("\(changed) changed") }
        if untracked > 0 { parts.append("\(untracked) new file\(untracked == 1 ? "" : "s")") }
        if upstream == nil { parts.append("not pushed anywhere") }
        else if ahead > 0 { parts.append("\(ahead) not pushed") }
        if backedUp { parts.append("all pushed") }
        return parts.joined(separator: " · ")
    }

    /// One plain sentence for the warning before a project is put to sleep.
    var warning: String? {
        guard !backedUp else { return nil }
        var parts: [String] = []
        if changed > 0 { parts.append("\(changed) file\(changed == 1 ? " has" : "s have") changes that are not committed") }
        if untracked > 0 { parts.append("\(untracked) new file\(untracked == 1 ? " is" : "s are") not in git yet") }
        if upstream == nil { parts.append("this branch has never been pushed") }
        else if ahead > 0 { parts.append("\(ahead) commit\(ahead == 1 ? " has" : "s have") not been pushed") }
        guard !parts.isEmpty else { return nil }
        let sentence = parts.joined(separator: ", ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + ". Sleeping only clears rebuildable files, but this work exists only on this Mac."
    }

    /// Parses `git status --porcelain=v2 --branch`.
    static func parse(_ output: String) -> GitStatus {
        var status = GitStatus()
        for line in output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                status.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.upstream ") {
                status.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                for part in line.dropFirst("# branch.ab ".count).split(separator: " ") {
                    if part.hasPrefix("+") { status.ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { status.behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("u ") {
                status.changed += 1
            } else if line.hasPrefix("? ") {
                status.untracked += 1
            }
        }
        return status
    }
}

enum ProjectGit {
    /// A real git, never `/usr/bin/git`: on a Mac without the developer tools
    /// that shim pops up an install dialog instead of answering.
    static let executable: String? = {
        let candidates = [
            "/opt/homebrew/bin/git", "/usr/local/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Nil when git is not installed, the folder is not a repository, or git
    /// does not answer within a few seconds.
    static func status(of repository: URL, git: String? = executable) -> GitStatus? {
        guard let git else { return nil }
        guard let result = try? ToolRunner.runExecutable(git, ["--no-optional-locks", "-C", repository.path,
                                                               "status", "--porcelain=v2", "--branch", "--untracked-files=normal"],
                                                         timeout: 5), result.ok else { return nil }
        return GitStatus.parse(result.stdout)
    }
}
