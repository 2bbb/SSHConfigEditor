import Foundation

public struct ConfigError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// A source index, deliberately not an evaluator of OpenSSH's Host/Match state.
public struct Directive: Equatable, Sendable {
    public let key: String
    public let arguments: [String]
    public let argumentRanges: [Range<String.Index>]
    public let valueRange: Range<String.Index>
    public let malformed: Bool

    public static func parse(_ line: String) -> Directive? {
        var i = line.startIndex
        func space(_ c: Character) -> Bool { c == " " || c == "\t" || c == "\r" }
        while i < line.endIndex && space(line[i]) { i = line.index(after: i) }
        guard i < line.endIndex, line[i] != "#" else { return nil }
        let start = i
        while i < line.endIndex && !space(line[i]) && line[i] != "=" { i = line.index(after: i) }
        let key = String(line[start..<i]).lowercased()
        while i < line.endIndex && space(line[i]) { i = line.index(after: i) }
        if i < line.endIndex && line[i] == "=" { i = line.index(after: i) }
        while i < line.endIndex && space(line[i]) { i = line.index(after: i) }
        let valueStart = i
        var valueEnd = i
        var args: [String] = [], ranges: [Range<String.Index>] = [], token = "", inToken = false
        var tokenStart = i
        var quote: Character?
        while i < line.endIndex {
            let c = line[i]
            if !inToken && !space(c) { tokenStart = i }
            if c == "\\" {
                let next = line.index(after: i)
                // OpenSSH argv_split only unescapes backslash, quote and space.
                if next < line.endIndex, ["\\", "\"", "'", " "].contains(line[next]) {
                    token.append(line[next]); inToken = true
                    i = line.index(after: next); valueEnd = i; continue
                }
            }
            if let q = quote {
                if c == q { quote = nil } else { token.append(c) }
                inToken = true
            } else if c == "\"" || c == "'" {
                quote = c; inToken = true
            } else if c == "#" {
                break
            } else if space(c) {
                if inToken { args.append(token); ranges.append(tokenStart..<i); token = ""; inToken = false }
                i = line.index(after: i); continue
            } else { token.append(c); inToken = true }
            i = line.index(after: i); valueEnd = i
        }
        if inToken { args.append(token); ranges.append(tokenStart..<i) }
        return Directive(key: key, arguments: args, argumentRanges: ranges, valueRange: valueStart..<valueEnd,
                         malformed: quote != nil || key.isEmpty)
    }
}

public struct SourceBlock: Identifiable, Equatable, Sendable {
    public let id: Int // ordinal remains stable while fields inside a block change
    public let start: Int
    public let end: Int
    public let kind: String
    public let title: String
}

public struct ConfigDocument: Sendable {
    public var text: String
    public init(_ text: String) { self.text = text }
    public var lines: [String] { text.components(separatedBy: "\n") }
    public var newline: String { text.contains("\r\n") ? "\r\n" : "\n" }
    public var blocks: [SourceBlock] {
        let rows = lines
        var starts: [(Int, String, String)] = [(0, "global", "ファイル先頭")]
        for (i, line) in rows.enumerated() {
            guard let d = Directive.parse(line), d.key == "host" || d.key == "match" else { continue }
            if i == 0 { starts.removeAll() }
            starts.append((i, d.key, d.arguments.joined(separator: " ")))
        }
        return starts.enumerated().map { index, entry in
            SourceBlock(id: index, start: entry.0,
                        end: index + 1 < starts.count ? starts[index + 1].0 : rows.count,
                        kind: entry.1, title: entry.2)
        }
    }
    public func occurrences(_ key: String, in block: SourceBlock) -> [Int] {
        let rows = lines
        let end = min(block.end, rows.count)
        // SwiftUI may render an outgoing row once after a cross-file move has
        // shortened its document. Never subscript using a stale block range.
        guard block.start >= 0, block.start < end else { return [] }
        return (block.start..<end).filter {
            Directive.parse(rows[$0])?.key == key.lowercased()
        }
    }
    public func source(in block: SourceBlock) -> String {
        let rows = lines, end = min(block.end, lines.count)
        guard block.start >= 0, block.start < end else { return "" }
        return rows[block.start..<end].joined(separator: "\n")
    }
    public func value(_ key: String, in block: SourceBlock) -> String {
        guard let row = occurrences(key, in: block).first, let d = Directive.parse(lines[row]) else { return "" }
        return String(lines[row][d.valueRange])
    }
    public mutating func setValue(_ key: String, value: String, blockID: Int) throws {
        guard !value.contains("\n"), !value.contains("\r"), !value.contains("\0") else {
            throw ConfigError("フォームには1行の値を入力してください。")
        }
        guard let block = blocks.first(where: { $0.id == blockID }) else { return }
        let hits = occurrences(key, in: block)
        guard hits.count <= 1 else { throw ConfigError("\(key) は複数あります。原文で編集してください。") }
        var rows = lines
        if let row = hits.first, let d = Directive.parse(rows[row]) {
            if value.trimmingCharacters(in: .whitespaces).isEmpty && !["host", "match"].contains(key.lowercased()) {
                // Keep an inline comment as a standalone comment when removing a value.
                let suffix = String(rows[row][d.valueRange.upperBound...])
                if suffix.contains("#") {
                    let indent = String(rows[row].prefix(while: { $0 == " " || $0 == "\t" }))
                    rows[row] = indent + suffix.trimmingCharacters(in: .whitespaces)
                } else { rows.remove(at: row) }
            } else { rows[row].replaceSubrange(d.valueRange, with: value) }
        } else if !value.trimmingCharacters(in: .whitespaces).isEmpty {
            // Insert before Include so its first-value precedence is explicit and predictable.
            let insertion = block.kind == "global" ? block.start : block.start + 1
            if insertion == rows.count, !rows.isEmpty {
                rows[rows.count - 1] += newline == "\r\n" && !rows.last!.hasSuffix("\r") ? "\r" : ""
            }
            rows.insert("    \(key) \(value)" + (newline == "\r\n" ? "\r" : ""), at: insertion)
        }
        text = rows.joined(separator: "\n")
    }
    public mutating func appendHost() -> Int {
        let separator = newline
        if !text.isEmpty && !text.hasSuffix("\n") { text += separator }
        text += separator + "Host new-host" + separator + "    HostName example.com" + separator
        return blocks.last!.id
    }
    public var diagnostics: [String] {
        lines.enumerated().compactMap { index, line in
            guard let d = Directive.parse(line) else { return nil }
            if d.malformed { return "行 \(index + 1): 引用符が閉じられていません。" }
            if d.arguments.isEmpty { return "行 \(index + 1): \(d.key) に値がありません。" }
            if d.key == "port", d.arguments.count != 1 || Int(d.arguments[0]).map({ !(1...65535).contains($0) }) ?? true {
                return "行 \(index + 1): Port は1〜65535で指定してください。"
            }
            return nil
        }
    }
}
