import Foundation

/// JSON with comments and trailing commas, as Cursor, Zed and opencode allow.
/// Reading strips the extras; editing splices one member in or out of the
/// original text, so every comment and line the person wrote stays as it was.
enum JSONC {
    private static let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\"), slash = UInt8(ascii: "/"),
                       star = UInt8(ascii: "*"), newline = UInt8(ascii: "\n"), comma = UInt8(ascii: ","),
                       colon = UInt8(ascii: ":"), openBrace = UInt8(ascii: "{"), closeBrace = UInt8(ascii: "}"),
                       openBracket = UInt8(ascii: "["), closeBracket = UInt8(ascii: "]"),
                       space = UInt8(ascii: " "), tab = UInt8(ascii: "\t"), carriageReturn = UInt8(ascii: "\r")

    /// Parses the text once comments and trailing commas are removed.
    static func parse(_ text: String) -> [String: Any]? {
        let plain = strip(text)
        if plain.allSatisfy(\.isWhitespace) { return [:] }
        return (try? JSONSerialization.jsonObject(with: Data(plain.utf8))) as? [String: Any]
    }

    /// The text without comments or trailing commas. Strings are kept intact.
    static func strip(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte == quote {
                let end = stringEnd(bytes, i)
                out.append(contentsOf: bytes[i..<end])
                i = end
            } else if let end = commentEnd(bytes, i) {
                // Keep line breaks so parse errors still point at the right line.
                out.append(contentsOf: bytes[i..<end].filter { $0 == newline })
                i = end
            } else if byte == comma, let next = nextSignificant(bytes, i + 1), bytes[next] == closeBrace || bytes[next] == closeBracket {
                i += 1
            } else {
                out.append(byte)
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Sets `name` inside the top-level object `object` to `value`, creating
    /// the object when it is missing. Nil when the text is not an object.
    static func setMember(in text: String, object: String, name: String, value: [String: Any]) -> String? {
        var bytes = Array(text.utf8)
        guard let root = nextSignificant(bytes, 0) else {
            // An empty file: write a fresh one.
            guard let body = encode([object: [name: value]], indent: "") else { return nil }
            return body + "\n"
        }
        guard bytes[root] == openBrace, let rootMembers = members(bytes, root) else { return nil }
        let unit = indentUnit(bytes)
        if let table = rootMembers.list.first(where: { $0.key == object }) {
            guard bytes[table.valueStart] == openBrace, let inner = members(bytes, table.valueStart) else { return nil }
            let indent = lineIndent(bytes, table.keyStart) + unit
            if let existing = inner.list.first(where: { $0.key == name }) {
                guard let encoded = encode(value, indent: indent) else { return nil }
                bytes.replaceSubrange(existing.valueStart..<existing.valueEnd, with: Array(encoded.utf8))
            } else {
                guard let encoded = encode(value, indent: indent) else { return nil }
                insert(&bytes, member: "\(jsonString(name)): \(encoded)", into: table.valueStart, members: inner, indent: indent,
                       closingIndent: lineIndent(bytes, table.keyStart))
            }
        } else {
            let indent = rootMembers.list.first.map { lineIndent(bytes, $0.keyStart) } ?? unit
            guard let encoded = encode([name: value], indent: indent) else { return nil }
            insert(&bytes, member: "\(jsonString(object)): \(encoded)", into: root, members: rootMembers, indent: indent,
                   closingIndent: lineIndent(bytes, root))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Removes `name` from the top-level object `object`. Nil when there is
    /// nothing to remove or the text is not an object.
    static func removeMember(in text: String, object: String, name: String) -> String? {
        var bytes = Array(text.utf8)
        guard let root = nextSignificant(bytes, 0), bytes[root] == openBrace,
              let table = members(bytes, root)?.list.first(where: { $0.key == object }),
              bytes[table.valueStart] == openBrace,
              let inner = members(bytes, table.valueStart),
              let index = inner.list.firstIndex(where: { $0.key == name }) else { return nil }
        let member = inner.list[index]
        var start = member.keyStart
        var end = member.valueEnd
        if let next = nextSignificant(bytes, end), bytes[next] == comma {
            end = next + 1
        } else if index > 0 {
            // The last member: take the comma that followed the one before it.
            let previous = inner.list[index - 1]
            if let separator = nextSignificant(bytes, previous.valueEnd), bytes[separator] == comma { start = separator }
        }
        // Take the member's own line with it when nothing else is on that line.
        var lineStart = start
        while lineStart > 0, bytes[lineStart - 1] == space || bytes[lineStart - 1] == tab { lineStart -= 1 }
        if lineStart > 0, bytes[lineStart - 1] == newline, start == member.keyStart { start = lineStart - 1 }
        bytes.removeSubrange(start..<end)
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Scanning

    private struct Member { let key: String; let keyStart: Int; let valueStart: Int; let valueEnd: Int }
    private struct Members { let list: [Member]; let close: Int }

    /// The members of the object whose `{` is at `open`.
    private static func members(_ bytes: [UInt8], _ open: Int) -> Members? {
        var list: [Member] = []
        var i = open + 1
        while true {
            guard let at = nextSignificant(bytes, i) else { return nil }
            if bytes[at] == closeBrace { return Members(list: list, close: at) }
            if bytes[at] == comma { i = at + 1; continue }
            guard bytes[at] == quote else { return nil }
            let keyEnd = stringEnd(bytes, at)
            guard let key = (try? JSONSerialization.jsonObject(with: Data(bytes[at..<keyEnd]), options: .fragmentsAllowed)) as? String,
                  let sep = nextSignificant(bytes, keyEnd), bytes[sep] == colon,
                  let valueStart = nextSignificant(bytes, sep + 1),
                  let valueEnd = valueEnd(bytes, valueStart) else { return nil }
            list.append(Member(key: key, keyStart: at, valueStart: valueStart, valueEnd: valueEnd))
            i = valueEnd
        }
    }

    /// One past the end of the value starting at `start`.
    private static func valueEnd(_ bytes: [UInt8], _ start: Int) -> Int? {
        let first = bytes[start]
        if first == quote { return stringEnd(bytes, start) }
        if first == openBrace || first == openBracket {
            var depth = 0
            var i = start
            while i < bytes.count {
                let byte = bytes[i]
                if byte == quote { i = stringEnd(bytes, i); continue }
                if let end = commentEnd(bytes, i) { i = end; continue }
                if byte == openBrace || byte == openBracket { depth += 1 }
                if byte == closeBrace || byte == closeBracket {
                    depth -= 1
                    if depth == 0 { return i + 1 }
                }
                i += 1
            }
            return nil
        }
        var i = start
        while i < bytes.count, ![comma, closeBrace, closeBracket, space, tab, newline, carriageReturn, slash].contains(bytes[i]) { i += 1 }
        return i > start ? i : nil
    }

    /// One past the closing quote of the string opening at `start`.
    private static func stringEnd(_ bytes: [UInt8], _ start: Int) -> Int {
        var i = start + 1
        while i < bytes.count {
            if bytes[i] == backslash { i += 2; continue }
            if bytes[i] == quote { return i + 1 }
            i += 1
        }
        return bytes.count
    }

    /// One past the end of a comment starting at `i`, or nil when none starts there.
    private static func commentEnd(_ bytes: [UInt8], _ i: Int) -> Int? {
        guard bytes[i] == slash, i + 1 < bytes.count else { return nil }
        if bytes[i + 1] == slash {
            var j = i + 2
            while j < bytes.count, bytes[j] != newline { j += 1 }
            return j
        }
        if bytes[i + 1] == star {
            var j = i + 2
            while j + 1 < bytes.count, !(bytes[j] == star && bytes[j + 1] == slash) { j += 1 }
            return min(bytes.count, j + 2)
        }
        return nil
    }

    /// The next byte that is not whitespace or a comment.
    private static func nextSignificant(_ bytes: [UInt8], _ from: Int) -> Int? {
        var i = from
        while i < bytes.count {
            let byte = bytes[i]
            if byte == space || byte == tab || byte == newline || byte == carriageReturn { i += 1; continue }
            if let end = commentEnd(bytes, i) { i = end; continue }
            return i
        }
        return nil
    }

    // MARK: - Writing

    private static func insert(_ bytes: inout [UInt8], member: String, into open: Int, members: Members, indent: String, closingIndent: String) {
        if let last = members.list.last {
            // After the last member, or after a trailing comma that follows it.
            var at = last.valueEnd
            var text = ",\n" + indent + member
            if let next = nextSignificant(bytes, at), bytes[next] == comma { at = next + 1; text = "\n" + indent + member }
            bytes.insert(contentsOf: Array(text.utf8), at: at)
        } else {
            bytes.replaceSubrange((open + 1)..<members.close, with: Array(("\n" + indent + member + "\n" + closingIndent).utf8))
        }
    }

    /// Pretty JSON whose continuation lines start at `indent`.
    private static func encode(_ value: [String: Any], indent: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return nil }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        return lines.enumerated().map { $0.offset == 0 ? String($0.element) : indent + $0.element }.joined(separator: "\n")
    }

    private static func jsonString(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes]) else { return "\"\(text)\"" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The spaces or tabs at the start of the line holding `index`.
    private static func lineIndent(_ bytes: [UInt8], _ index: Int) -> String {
        var start = index
        while start > 0, bytes[start - 1] != newline { start -= 1 }
        var end = start
        while end < bytes.count, bytes[end] == space || bytes[end] == tab { end += 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// The file's own step: a tab, or the smallest run of leading spaces.
    private static func indentUnit(_ bytes: [UInt8]) -> String {
        var smallest = Int.max
        var i = 0
        while i < bytes.count {
            var j = i
            while j < bytes.count, bytes[j] == space { j += 1 }
            if j < bytes.count, bytes[j] == tab, j == i { return "\t" }
            if j > i, j < bytes.count, bytes[j] != newline { smallest = min(smallest, j - i) }
            while j < bytes.count, bytes[j] != newline { j += 1 }
            i = j + 1
        }
        return String(repeating: " ", count: smallest == Int.max ? 2 : smallest)
    }
}

/// Goose's `~/.config/goose/config.yaml`. Only Cairn's entry under the
/// top-level `extensions:` map is ever added or removed; every other line,
/// comment and extension stays exactly as written.
enum GooseYAML {
    /// Cairn's lines, from `cairn:` to the end of its block.
    static func entry(in text: String) -> Range<String.Index>? {
        let lines = split(text)
        guard let block = extensionsBlock(lines), let range = entryLines(lines, block: block) else { return nil }
        return lines[range.lowerBound].range.lowerBound..<lines[range.upperBound - 1].range.upperBound
    }

    /// The text with Cairn's entry added or replaced. Nil when `extensions`
    /// is written in a form Cairn does not edit, such as an inline map.
    static func connect(_ text: String, command: String) -> String? {
        var text = text
        if let removed = disconnect(text) { text = removed }
        var lines = split(text)
        if let index = lines.firstIndex(where: { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == "extensions: {}" && !$0.content.hasPrefix(" ") }) {
            // An empty inline map becomes a block Cairn can add to.
            text.replaceSubrange(lines[index].range, with: "extensions:\n")
            lines = split(text)
        }
        guard let block = extensionsBlock(lines) else {
            if lines.contains(where: { isTopKey($0.content, "extensions") }) { return nil }
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            return text + "extensions:\n" + body(indent: "  ", command: command)
        }
        let indent = String(repeating: " ", count: block.childIndent)
        // After the block's last real line, before any blank lines that follow it.
        var last = block.header
        for index in (block.header + 1)..<block.end where !lines[index].content.trimmingCharacters(in: .whitespaces).isEmpty { last = index }
        let at = lines[last].range.upperBound
        var insertion = body(indent: indent, command: command)
        if !lines[last].content.hasSuffix("\n") { insertion = "\n" + insertion }
        text.insert(contentsOf: insertion, at: at)
        return text
    }

    /// The text without Cairn's entry, or nil when it has none.
    static func disconnect(_ text: String) -> String? {
        let lines = split(text)
        guard let block = extensionsBlock(lines), let range = entryLines(lines, block: block) else { return nil }
        var text = text
        text.removeSubrange(lines[range.lowerBound].range.lowerBound..<lines[range.upperBound - 1].range.upperBound)
        // Leave a valid empty map rather than a bare key when Cairn was the only extension.
        let after = split(text)
        if let again = extensionsBlock(after),
           !after[(again.header + 1)..<again.end].contains(where: { !$0.content.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let header = after[again.header]
            text.replaceSubrange(header.range, with: "extensions: {}" + (header.content.hasSuffix("\n") ? "\n" : ""))
        }
        return text
    }

    private static func body(indent: String, command: String) -> String {
        let inner = indent + indent
        return [
            "\(indent)\(AgentTool.serverName):",
            "\(inner)name: \(AgentTool.serverName)",
            "\(inner)display_name: Cairn",
            "\(inner)type: stdio",
            "\(inner)cmd: \(AgentConnections.tomlString(command))",
            "\(inner)args:",
            "\(inner)- mcp",
            "\(inner)enabled: true",
            "\(inner)envs: {}",
            "\(inner)env_keys: []",
            "\(inner)timeout: 300",
        ].joined(separator: "\n") + "\n"
    }

    // MARK: - Lines

    private struct Line { let content: String; let range: Range<String.Index> }
    private struct Block { let header: Int; let end: Int; let childIndent: Int }

    /// Lines with their own line breaks, so ranges cover whole lines.
    private static func split(_ text: String) -> [Line] {
        var lines: [Line] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text[start...].firstIndex(of: "\n").map { text.index(after: $0) } ?? text.endIndex
            lines.append(Line(content: String(text[start..<end]), range: start..<end))
            start = end
        }
        return lines
    }

    private static func leading(_ line: String) -> Int { line.prefix { $0 == " " }.count }

    private static func isBlankOrComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("#")
    }

    private static func isTopKey(_ line: String, _ key: String) -> Bool {
        !line.hasPrefix(" ") && !line.hasPrefix("\t") && line.hasPrefix(key + ":")
    }

    /// The `extensions:` header written as a block, and the lines under it.
    private static func extensionsBlock(_ lines: [Line]) -> Block? {
        guard let header = lines.firstIndex(where: { line in
            guard isTopKey(line.content, "extensions") else { return false }
            let rest = line.content.dropFirst("extensions:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty || rest.hasPrefix("#")
        }) else { return nil }
        var end = header + 1
        var childIndent: Int?
        while end < lines.count {
            let line = lines[end].content
            if !isBlankOrComment(line) {
                if leading(line) == 0 { break }
                if childIndent == nil { childIndent = leading(line) }
            }
            end += 1
        }
        return Block(header: header, end: end, childIndent: childIndent ?? 2)
    }

    /// The lines of Cairn's entry inside the block.
    private static func entryLines(_ lines: [Line], block: Block) -> Range<Int>? {
        guard let start = ((block.header + 1)..<block.end).first(where: { index in
            let line = lines[index].content
            let key = line.trimmingCharacters(in: .whitespaces)
            return leading(line) == block.childIndent && (key.hasPrefix("\(AgentTool.serverName):") || key.hasPrefix("\"\(AgentTool.serverName)\":"))
        }) else { return nil }
        var end = start + 1
        while end < block.end {
            let line = lines[end].content
            if !isBlankOrComment(line) && leading(line) <= block.childIndent { break }
            end += 1
        }
        // Blank lines at the end belong to whatever follows.
        while end - 1 > start, lines[end - 1].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { end -= 1 }
        return start..<end
    }
}
