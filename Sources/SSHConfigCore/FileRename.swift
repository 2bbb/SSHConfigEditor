import Foundation
import Darwin

public struct IncludeRewrite: Sendable {
    public let url: URL
    public let before: String
    public let after: String
    public let lines: [Int]
}

public struct FileRenamePlan: Sendable {
    public let source: URL
    public let destination: URL
    public let rewrites: [IncludeRewrite]

    public init(source: URL, newName: String, documents: [URL: String], baseDirectory: URL) throws {
        let components = newName.components(separatedBy: "/")
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }),
              !newName.contains(where: { "\\\n\r\0*?[%".contains($0) }), !newName.contains("${") else {
            throw ConfigError("ファイル名、または hoge/bar のような相対パスを入力してください。空の名前・..・ワイルドカードは使えません。")
        }
        let source = source.standardizedFileURL
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName).standardizedFileURL
        guard source != destination else { throw ConfigError("現在と異なる名前を入力してください。") }
        guard source.resolvingSymlinksInPath() == source else {
            throw ConfigError("シンボリックリンク経由のファイル名変更には対応していません。実体のファイルを開いてください。")
        }
        guard destination.resolvingSymlinksInPath() == destination else {
            throw ConfigError("シンボリックリンクを経由する移動先には対応していません。")
        }
        guard !FileManager.default.fileExists(atPath: destination.path),
              (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == nil else {
            throw ConfigError("同じ名前のファイルがすでにあります。")
        }
        let resolver = IncludeGraph(baseDirectory: baseDirectory)
        var rewrites: [IncludeRewrite] = []
        for (url, text) in documents.sorted(by: { $0.key.path < $1.key.path }) {
            var rows = ConfigDocument(text).lines
            var changed: [Int] = []
            for (lineNumber, line) in rows.enumerated() {
                guard let d = Directive.parse(line), d.key == "include" else { continue }
                guard !d.malformed else { throw ConfigError("\(url.lastPathComponent): Includeの引用符を先に修正してください。") }
                var replacements: [(Range<String.Index>, String)] = []
                for (index, argument) in d.arguments.enumerated() {
                    let matches: [URL]
                    do { matches = try resolver.expand(argument, pendingFiles: [source]) }
                    catch { throw ConfigError("\(url.lastPathComponent) 行\(lineNumber + 1): 参照を確定できないため変更を中止します。\n\(error.localizedDescription)") }
                    guard matches.contains(where: { $0.standardizedFileURL == source }) else { continue }
                    let isGlob = argument.contains(where: { "*?[".contains($0) })
                    let quotedDestination = Self.quote(destination.path)
                    if isGlob {
                        let newMatches = try resolver.expand(argument, pendingFiles: [destination])
                        if !newMatches.contains(destination) {
                            // Keep the original glob (and every other file it includes).
                            replacements.append((d.argumentRanges[index], String(line[d.argumentRanges[index]]) + " " + quotedDestination))
                        }
                    } else {
                        // Preserve relative/tilde notation. Environment paths are made explicit.
                        let replacement: String
                        if argument.contains("${") { replacement = destination.path }
                        else if let slash = argument.lastIndex(of: "/") { replacement = String(argument[...slash]) + newName }
                        else { replacement = newName }
                        replacements.append((d.argumentRanges[index], Self.quote(replacement)))
                    }
                }
                for (range, value) in replacements.reversed() { rows[lineNumber].replaceSubrange(range, with: value) }
                if !replacements.isEmpty { changed.append(lineNumber + 1) }
            }
            if !changed.isEmpty { rewrites.append(IncludeRewrite(url: url, before: text, after: rows.joined(separator: "\n"), lines: changed)) }
        }
        self.source = source; self.destination = destination; self.rewrites = rewrites
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Move and update all known referrers; restore completed writes on a later failure.
    /// Cross-file atomicity cannot be provided by the filesystem; all originals are backed up.
    public func apply(snapshots: [FileSnapshot], backupRoot: URL) throws {
        let affected = Set(rewrites.map { $0.url.standardizedFileURL }).union([source])
        var originals: [URL: FileSnapshot] = [:]
        for url in affected {
            guard let snapshot = snapshots.first(where: { $0.url.standardizedFileURL == url }), snapshot.original != nil else {
                throw ConfigError("変更前にすべてのファイルを保存してください。")
            }
            try snapshot.verifyUnchanged()
            originals[url] = snapshot
        }
        for rewrite in rewrites {
            guard originals[rewrite.url.standardizedFileURL]?.original == Data(rewrite.before.utf8) else {
                throw ConfigError("参照元が更新されています。変更内容を再確認してください。")
            }
        }
        let fm = FileManager.default
        var createdDirectories: [URL] = []
        var parent = destination.deletingLastPathComponent()
        while !fm.fileExists(atPath: parent.path) {
            createdDirectories.append(parent)
            parent.deleteLastPathComponent()
        }
        var committed = false
        defer {
            // rmdir only removes empty directories; external contents are never removed.
            if !committed { for directory in createdDirectories { _ = rmdir(directory.path) } }
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // moveItem refuses an existing destination, including one created after the preview.
        try fm.moveItem(at: source, to: destination)
        var completed: [(FileSnapshot, String)] = []
        do {
            for rewrite in rewrites {
                let original = originals[rewrite.url.standardizedFileURL]!
                var snapshot = rewrite.url.standardizedFileURL == source ? try FileSnapshot.load(destination).0 : original
                guard snapshot.original == original.original else { throw ConfigError("名前変更中に内容が変更されました。") }
                try snapshot.save(rewrite.after, backupRoot: backupRoot)
                completed.append((snapshot, rewrite.before))
            }
            committed = true
        } catch {
            var rollbackErrors: [String] = []
            for (var snapshot, text) in completed.reversed() {
                do { try snapshot.save(text, backupRoot: backupRoot) }
                catch { rollbackErrors.append(error.localizedDescription) }
            }
            do { try fm.moveItem(at: destination, to: source) }
            catch { rollbackErrors.append(error.localizedDescription) }
            if rollbackErrors.isEmpty { throw ConfigError("名前変更を取り消しました。\n\(error.localizedDescription)") }
            throw ConfigError("名前変更の復元が一部未完了です。バックアップを確認してください。\n\(error.localizedDescription)\n\(rollbackErrors.joined(separator: "\n"))")
        }
    }
}
