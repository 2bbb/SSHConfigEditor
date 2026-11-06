import AppKit
import Observation
import SSHConfigCore

@MainActor @Observable
final class EditableFile: Identifiable {
    let id: String
    var snapshot: FileSnapshot
    var text: String
    var referenced = false
    init(url: URL) throws {
        let (snapshot, text) = try FileSnapshot.load(url)
        self.snapshot = snapshot; self.text = text; self.id = snapshot.target.path
    }
    var dirty: Bool { Data(text.utf8) != snapshot.original && !(snapshot.original == nil && text.isEmpty) }
    var parsed: ConfigDocument { ConfigDocument(text) }
    var name: String { snapshot.url.lastPathComponent }
    var displayPath: String { (snapshot.url.path as NSString).abbreviatingWithTildeInPath }
}

@MainActor @Observable
final class Workspace {
    var files: [EditableFile] = []
    var selectedFileID: String?
    var selectedBlockID: Int? = 0
    var rootURL: URL
    var baseURL: URL
    var graph: IncludeNode?
    var query = ""
    var editorMode = "fields"
    var errorMessage: String?
    var status = ""
    var lastBackup: URL?
    var showChanges = false
    var renameTarget: EditableFile?
    var dragSession: HostDragSession?
    var hoveredFileID: String?
    var springFileID: String?
    var collapsedFolders: Set<String> = []
    @ObservationIgnored private var springTask: Task<Void, Never>?
    @ObservationIgnored var nativeDragSource: AnyObject?
    @ObservationIgnored weak var dragSurface: NSView?
    let backupRoot: URL

    init(root: URL? = nil, includeBase: URL? = nil, backups: URL? = nil) {
        let args = ProcessInfo.processInfo.arguments
        let configIndex = args.firstIndex(of: "--config")
        rootURL = root ?? configIndex.flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        let baseIndex = args.firstIndex(of: "--include-base")
        baseURL = includeBase ?? baseIndex.flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        backupRoot = backups ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SSHConfigEditor/Backups", isDirectory: true)
        reloadGraph()
        selectedFileID = rootURL.resolvingSymlinksInPath().path
    }
    var selected: EditableFile? { files.first { $0.id == selectedFileID } }
    var fileSelection: String? {
        get { selectedFileID }
        set {
            selectedFileID = newValue
            selectedBlockID = selected?.parsed.blocks.first?.id
        }
    }
    var dirtyFiles: [EditableFile] { files.filter(\.dirty) }
    var fileTree: [FileTreeNode] {
        var root = FileTreeNode(id: "base", title: "")
        var external = FileTreeNode(id: "external", title: "外部参照")
        let prefix = baseURL.standardizedFileURL.path + "/"
        for file in files {
            let path = file.snapshot.url.standardizedFileURL.path
            if path.hasPrefix(prefix) {
                root.insert(file, components: String(path.dropFirst(prefix.count)).components(separatedBy: "/")[...], directory: baseURL)
            } else {
                let parent = file.snapshot.url.deletingLastPathComponent()
                let id = "folder:" + parent.path
                if !external.children.contains(where: { $0.id == id }) {
                    external.children.append(FileTreeNode(id: id, title: (parent.path as NSString).abbreviatingWithTildeInPath))
                }
                let index = external.children.firstIndex { $0.id == id }!
                external.children[index].children.append(FileTreeNode(id: file.id, title: file.name, file: file))
            }
        }
        root.sort(); external.sort()
        return root.children + (external.children.isEmpty ? [] : [external])
    }
    var rootFile: EditableFile? { files.first { $0.id == rootURL.resolvingSymlinksInPath().path } }
    var visibleBlocks: [SourceBlock] {
        guard let file = selected else { return [] }
        return file.parsed.blocks.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || file.parsed.lines[$0.start..<$0.end].joined(separator: "\n").localizedCaseInsensitiveContains(query)
        }
    }

    func select(path: String) {
        selectedFileID = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        selectedBlockID = selected?.parsed.blocks.first?.id
    }
    private func load(_ url: URL) throws -> EditableFile {
        let id = url.resolvingSymlinksInPath().path
        if let existing = files.first(where: { $0.id == id }) { return existing }
        guard files.count < 512 else { throw ConfigError("ファイル数が上限に達しました。") }
        let file = try EditableFile(url: url)
        files.append(file)
        return file
    }
    func reloadGraph() {
        files.forEach { $0.referenced = false }
        let pending = files.filter { $0.snapshot.original == nil }.map { $0.snapshot.url }
        graph = IncludeGraph(baseDirectory: baseURL).build(root: rootURL, pendingFiles: pending) { url in
            let file = try load(url)
            file.referenced = true
            return file.text
        }
        // conf.d is a conventional folder, not an implicit OpenSSH include.
        let directory = baseURL.appendingPathComponent("conf.d", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            var visited = 0
            while let url = enumerator.nextObject() as? URL {
                visited += 1
                if visited > 4096 { status = "conf.dの探索上限に達しました"; break }
                if enumerator.level > 32 { enumerator.skipDescendants(); continue }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                do { _ = try load(url) }
                catch { status = "conf.d: \(error.localizedDescription)" }
            }
        }
    }
    func set(_ key: String, value: String, blockID: Int, file: EditableFile) {
        do {
            var parsed = file.parsed
            try parsed.setValue(key, value: value, blockID: blockID)
            file.text = parsed.text
        } catch { errorMessage = error.localizedDescription }
    }
    func addHost() {
        guard let file = selected else { return }
        var parsed = file.parsed
        selectedBlockID = parsed.appendHost()
        file.text = parsed.text
        query = ""; editorMode = "fields"
    }
    func beginDrag(file: EditableFile, block: SourceBlock) -> String {
        endDrag()
        let drag = HostDragSession(token: UUID().uuidString, sourceID: file.id, blockID: block.id, originalText: file.text)
        dragSession = drag
        return drag.token
    }
    func hoverFile(_ file: EditableFile) {
        guard let dragSession, dragSession.sourceID != file.id else { return }
        springTask?.cancel()
        hoveredFileID = file.id
        springTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            guard self.dragSession != nil, hoveredFileID == file.id else { return }
            springFileID = file.id
            query = ""
            select(path: file.snapshot.url.path)
        }
    }
    func leaveFile(_ file: EditableFile) {
        if hoveredFileID == file.id { hoveredFileID = nil; springTask?.cancel() }
    }
    func endDrag() {
        springTask?.cancel(); springTask = nil
        dragSession = nil; hoveredFileID = nil; springFileID = nil
    }
    @discardableResult func moveDraggedHost(to destination: EditableFile, before blockID: Int? = nil) -> Bool {
        guard let drag = dragSession, let source = files.first(where: { $0.id == drag.sourceID }), source.id != destination.id else { return false }
        do {
            guard source.text == drag.originalText else { throw ConfigError("移動元が変更されています。もう一度ドラッグしてください。") }
            let move = try HostMoveResult(source: source.text, blockID: drag.blockID, destination: destination.text, beforeBlockID: blockID)
            source.text = move.source
            destination.text = move.destination
            select(path: destination.snapshot.url.path)
            selectedBlockID = move.insertedBlockID
            editorMode = "fields"
            status = "Hostを\(destination.name)へ移動しました（未保存）"
            endDrag()
            return true
        } catch { errorMessage = error.localizedDescription; endDrag(); return false }
    }
    func planRename(_ file: EditableFile, to name: String) throws -> FileRenamePlan {
        guard dirtyFiles.isEmpty else { throw ConfigError("名前を変更する前に、編集内容を保存してください。") }
        return try FileRenamePlan(source: file.snapshot.url, newName: name,
            documents: Dictionary(uniqueKeysWithValues: files.map { ($0.snapshot.url, $0.text) }), baseDirectory: baseURL)
    }
    @discardableResult func rename(_ file: EditableFile, to name: String) -> Bool {
        do {
            let plan = try planRename(file, to: name)
            try plan.apply(snapshots: files.map(\.snapshot), backupRoot: backupRoot)
            if rootURL.standardizedFileURL == plan.source { rootURL = plan.destination }
            files = []; reloadGraph()
            _ = try load(plan.destination)
            select(path: plan.destination.path)
            status = "\(name) に変更しました（参照元\(plan.rewrites.count)ファイル更新）"
            renameTarget = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func openConfig() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.title = "ルート設定を開く"
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = baseURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        files = []; rootURL = url
        // Even -F files resolve user Include paths relative to ~/.ssh.
        baseURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        reloadGraph(); select(path: url.path)
    }
    func openDefault() {
        guard confirmDiscard() else { return }
        baseURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        rootURL = baseURL.appendingPathComponent("config")
        files = []; reloadGraph(); select(path: rootURL.path)
    }
    func reloadFromDisk() {
        guard confirmDiscard() else { return }
        let selection = selectedFileID
        files = []; reloadGraph()
        selectedFileID = files.contains(where: { $0.id == selection }) ? selection : rootFile?.id
        selectedBlockID = 0; status = "ディスクから再読み込みしました"
    }
    func addFragment() {
        guard let root = rootFile else { return }
        let panel = NSSavePanel()
        panel.title = "設定ファイルを追加"
        panel.prompt = "追加"
        panel.directoryURL = baseURL.appendingPathComponent("conf.d")
        panel.nameFieldStringValue = "hosts.conf"
        panel.showsHiddenFiles = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard !FileManager.default.fileExists(atPath: url.path),
                  !files.contains(where: { $0.id == url.resolvingSymlinksInPath().path }) else {
                throw ConfigError("既存ファイルは左の一覧から開いてください。")
            }
            guard !url.path.contains("\n"), !url.path.contains("\r"), !url.path.contains("%"), !url.path.contains("${"),
                  !url.path.contains("*"), !url.path.contains("?"), !url.path.contains("[") else {
                throw ConfigError("Includeで特別な意味を持つ文字を含まないファイル名を指定してください。")
            }
            let file = try load(url)
            file.text = "# \(url.lastPathComponent)\n\nHost new-host\n    HostName example.com\n"
            // Avoid duplicate includes when an existing glob already covers the new path.
            let patternCovered = files.contains { candidate in
                candidate.referenced && candidate.parsed.lines.contains { line in
                    guard let d = Directive.parse(line), d.key == "include" else { return false }
                    return d.arguments.contains { pattern in
                        (try? IncludeGraph(baseDirectory: baseURL).expand(pattern, pendingFiles: [url]).contains(url)) == true
                    }
                }
            }
            if !patternCovered {
                let quoted = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                root.text = "Include \"\(quoted)\"" + root.parsed.newline + root.text
            }
            select(path: url.path)
            status = "新規ファイルを追加しました。「すべて保存」でディスクに反映します。"
            reloadGraph()
        } catch { errorMessage = error.localizedDescription }
    }
    @discardableResult func saveAll() -> Bool {
        let pending = dirtyFiles.sorted { a, b in
            if a.id == rootFile?.id { return false }
            if b.id == rootFile?.id { return true }
            return a.id < b.id
        }
        guard !pending.isEmpty else { return true }
        var saved = 0
        do {
            // Preflight every file before changing the first one.
            for file in pending {
                try file.snapshot.verifyUnchanged()
                if let issue = file.parsed.diagnostics.first { throw ConfigError("\(file.name): \(issue)") }
            }
            for file in pending {
                if let backup = try file.snapshot.save(file.text, backupRoot: backupRoot) { lastBackup = backup }
                saved += 1
            }
            status = "\(saved)ファイルを保存しました"
            reloadGraph()
            return true
        } catch {
            errorMessage = (saved == 0 ? "" : "\(saved)ファイルは保存済みです。残りは未保存です。\n") + error.localizedDescription
            return false
        }
    }
    func confirmDiscard() -> Bool {
        guard !dirtyFiles.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "未保存の変更があります"
        alert.informativeText = "\(dirtyFiles.count)ファイルの変更を保存しますか？"
        alert.addButton(withTitle: "すべて保存")
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "変更を破棄")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveAll()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
}
