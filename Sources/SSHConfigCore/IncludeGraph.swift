import Foundation
import Darwin

public struct IncludeNode: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let path: String?
    public let note: String?
    public let children: [IncludeNode]?
    public init(id: String, title: String, path: String? = nil, note: String? = nil, children: [IncludeNode]? = nil) {
        self.id = id; self.title = title; self.path = path; self.note = note; self.children = children
    }
}

public struct IncludeGraph {
    public let baseDirectory: URL
    public init(baseDirectory: URL) { self.baseDirectory = baseDirectory }

    public func expand(_ pattern: String, pendingFiles: [URL] = []) throws -> [URL] {
        var expanded = pattern
        let regex = try NSRegularExpression(pattern: #"\$\{([^}]+)\}"#)
        for match in regex.matches(in: expanded, range: NSRange(expanded.startIndex..., in: expanded)).reversed() {
            let name = (expanded as NSString).substring(with: match.range(at: 1))
            guard let value = ProcessInfo.processInfo.environment[name] else {
                throw ConfigError("Environment variable \(name) is not set.")
            }
            expanded = (expanded as NSString).replacingCharacters(in: match.range, with: value)
        }
        guard !expanded.contains("%") else {
            throw ConfigError("Connection-dependent % tokens are preserved in the source and are not expanded.")
        }
        expanded = (expanded as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : baseDirectory.appendingPathComponent(expanded).path
        var result = glob_t()
        defer { globfree(&result) }
        let status = glob(absolute, 0, nil, &result)
        guard status == 0 || status == GLOB_NOMATCH else { throw ConfigError("Could not expand Include: \(pattern)") }
        let existing = (0..<Int(result.gl_pathc)).compactMap { i in
            result.gl_pathv[i].map { URL(fileURLWithPath: String(cString: $0)).standardizedFileURL }
        }
        let pending = pendingFiles.filter { fnmatch(absolute, $0.path, FNM_PATHNAME | FNM_PERIOD) == 0 }
        return Array(Set(existing + pending)).sorted { $0.path < $1.path }
    }

    /// All syntactic includes are indexed, including conditional branches. No shell or SSH is run.
    public func build(root: URL, pendingFiles: [URL] = [], read: (URL) throws -> String) -> IncludeNode {
        var count = 0
        func visit(_ url: URL, ancestry: Set<String>, id: String) -> IncludeNode {
            let path = url.standardizedFileURL.path
            let canonical = url.resolvingSymlinksInPath().path
            guard !ancestry.contains(canonical) else {
                return IncludeNode(id: id, title: url.lastPathComponent, path: path, note: "Include cycle")
            }
            guard ancestry.count < 32, count < 512 else {
                return IncludeNode(id: id, title: url.lastPathComponent, path: path, note: "Traversal limit reached")
            }
            count += 1
            do {
                let text = try read(url)
                var children: [IncludeNode] = []
                var scope = "Global settings"
                for (line, raw) in ConfigDocument(text).lines.enumerated() {
                    guard let d = Directive.parse(raw) else { continue }
                    if d.key == "host" || d.key == "match" { scope = d.key.capitalized + " " + d.arguments.joined(separator: " ") }
                    guard d.key == "include" else { continue }
                    for (index, pattern) in d.arguments.enumerated() {
                        let key = "\(id)/\(line)/\(index)"
                        do {
                            let urls = try expand(pattern, pendingFiles: pendingFiles)
                            let descendants = urls.enumerated().map { n, child in
                                visit(child, ancestry: ancestry.union([canonical]), id: "\(key)/\(n)")
                            }
                            children.append(IncludeNode(id: key, title: pattern,
                                note: "Line \(line + 1) · \(scope)" + (urls.isEmpty ? " · No matches" : ""),
                                children: descendants.isEmpty ? nil : descendants))
                        } catch {
                            children.append(IncludeNode(id: key, title: pattern, note: error.localizedDescription))
                        }
                    }
                }
                return IncludeNode(id: id, title: url.lastPathComponent, path: path,
                                   children: children.isEmpty ? nil : children)
            } catch {
                return IncludeNode(id: id, title: url.lastPathComponent, path: path, note: error.localizedDescription)
            }
        }
        return visit(root, ancestry: [], id: "root")
    }
}
