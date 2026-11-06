import SwiftUI
import SSHConfigCore

struct ContentView: View {
    @Bindable var workspace: Workspace
    @State private var sidebarMode = "files"

    var body: some View {
        VStack(spacing: 0) {
            navigation
            Divider()
            statusBar
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: workspace.selected?.text) {
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            workspace.reloadGraph()
        }
        .alert("Could Not Complete Operation", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
            Button("OK") { workspace.errorMessage = nil }
        } message: { Text(workspace.errorMessage ?? "") }
        .sheet(isPresented: $workspace.showChanges) { ChangesView(workspace: workspace) }
        .sheet(item: $workspace.renameTarget) { file in RenameFileView(workspace: workspace, file: file) }
    }

    private var navigation: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("View", selection: $sidebarMode) {
                    Text("Files").tag("files")
                    Text("Include").tag("includes")
                }.pickerStyle(.segmented).labelsHidden().padding(12)
                if sidebarMode == "includes", let graph = workspace.graph {
                    List {
                        OutlineGroup([graph], children: \.children) { node in
                            VStack(alignment: .leading, spacing: 4) {
                                if let path = node.path {
                                    Button { workspace.select(path: path) } label: {
                                        Label(node.title, systemImage: "doc.text")
                                    }.buttonStyle(.plain).foregroundStyle(workspace.selectedFileID == path ? Color.accentColor : .primary)
                                } else {
                                    Label(node.title, systemImage: "arrow.turn.down.right").font(.system(.caption, design: .monospaced))
                                }
                                if let note = node.note { Text(note).font(.caption2).foregroundStyle(.secondary) }
                            }.padding(.vertical, 3).help(node.path ?? node.title)
                        }
                    }.listStyle(.sidebar)
                } else {
                    List(selection: $workspace.fileSelection) {
                        Section((workspace.baseURL.path as NSString).abbreviatingWithTildeInPath) {
                            ForEach(workspace.fileTree) { node in FileTreeRow(node: node, workspace: workspace) }
                        }
                    }.listStyle(.sidebar)
                }
                Divider()
                HStack {
                    Button(action: workspace.addFragment) { Image(systemName: "doc.badge.plus") }.help("Add Configuration File")
                    Button(action: workspace.openConfig) { Image(systemName: "folder") }.help("Open Root Configuration")
                    Button { workspace.renameTarget = workspace.selected } label: { Image(systemName: "pencil") }
                        .help("Rename file (save changes first)")
                        .disabled(workspace.selected?.snapshot.original == nil || !workspace.dirtyFiles.isEmpty)
                    Spacer()
                    Text("Files: \(workspace.files.count)").font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.borderless).padding(12)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 360)
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search hosts and settings", text: $workspace.query).textFieldStyle(.plain)
                }.padding(12)
                Divider()
                List(selection: $workspace.selectedBlockID) {
                    ForEach(workspace.visibleBlocks) { block in
                        if let file = workspace.selected {
                            HostListItem(workspace: workspace, file: file, block: block).tag(block.id)
                        }
                    }
                    if let file = workspace.selected, workspace.springFileID == file.id, workspace.dragSession != nil {
                        HostInsertionSlot(workspace: workspace, file: file, beforeBlockID: nil)
                    }
                }.listStyle(.inset)
                Divider()
                HStack {
                    Button(action: workspace.addHost) { Label("Add Host", systemImage: "plus") }
                        .disabled(workspace.selected == nil)
                    Spacer()
                }.buttonStyle(.borderless).padding(12)
            }.navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 400)
        } detail: {
            if let file = workspace.selected {
                FileEditor(workspace: workspace, file: file)
            } else {
                ContentUnavailableView("Select a Configuration File", systemImage: "doc.text", description: Text("Choose a file in the sidebar to start editing."))
            }
        }
        .navigationTitle("SSH Settings")
        .toolbar {
            ToolbarItemGroup {
                Button(action: workspace.reloadFromDisk) { Image(systemName: "arrow.clockwise") }.help("Reload from Disk")
                Button { workspace.showChanges = true } label: { Label("Review Changes", systemImage: "square.split.2x1") }
                    .disabled(workspace.dirtyFiles.isEmpty)
                Button { workspace.saveAll() } label: { Label("Save All", systemImage: "square.and.arrow.down") }
                    .disabled(workspace.dirtyFiles.isEmpty)
                    .keyboardShortcut("s")
            }
        }
    }

    private var statusBar: some View {
            HStack(spacing: 12) {
                Image(systemName: workspace.dirtyFiles.isEmpty ? "checkmark.circle" : "circle.fill")
                    .foregroundStyle(workspace.dirtyFiles.isEmpty ? .secondary : Color.orange)
                Text(workspace.dirtyFiles.isEmpty ? "Saved" : "Unsaved files: \(workspace.dirtyFiles.count)")
                if workspace.dragSession != nil {
                    Text("Hover over a file to choose an insertion point").foregroundStyle(.secondary)
                } else if !workspace.status.isEmpty { Text(workspace.status).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                if workspace.lastBackup != nil {
                    Button("Backups") { NSWorkspace.shared.open(workspace.backupRoot) }.buttonStyle(.link)
                }
            }.font(.caption).padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }
}

private struct HostListItem: View {
    let workspace: Workspace
    let file: EditableFile
    let block: SourceBlock
    var body: some View {
        VStack(spacing: 0) {
            if workspace.springFileID == file.id, workspace.dragSession != nil, block.kind != "global" {
                HostInsertionSlot(workspace: workspace, file: file, beforeBlockID: block.id)
            }
            BlockRow(block: block, document: file.parsed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    if block.kind == "host" { HostDragSource(workspace: workspace, file: file, block: block) }
                }
        }
    }
}

struct FileRow: View {
    let file: EditableFile
    let canRename: Bool
    let rename: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: file.name == "config" ? "doc.text" : "doc.text.fill").foregroundStyle(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(file.name).fontWeight(.medium); if file.dirty { Circle().fill(.orange).frame(width: 6, height: 6).accessibilityLabel("Unsaved") } }
                if !file.referenced { Text("Not included").font(.caption2).foregroundStyle(.secondary) }
                Text(file.displayPath).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 5).help(file.displayPath)
        .contextMenu {
            Button("Rename…", action: rename).disabled(!canRename || file.snapshot.original == nil)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.snapshot.url]) }
            Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.snapshot.url.path, forType: .string) }
        }
    }
}

private struct BlockRow: View {
    let block: SourceBlock
    let document: ConfigDocument?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: block.kind == "host" ? (block.title.contains("*") ? "asterisk" : "server.rack") : block.kind == "match" ? "line.3.horizontal.decrease" : "slider.horizontal.3")
                .frame(width: 18).foregroundStyle(block.kind == "host" ? Color.accentColor : .secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(block.title.isEmpty ? "Untitled" : block.title).fontWeight(.medium).lineLimit(2)
                if let document, block.kind == "host", !document.value("HostName", in: block).isEmpty {
                    Text(document.value("HostName", in: block)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                } else { Text(block.kind == "match" ? "Match conditions" : block.kind == "global" ? "Global settings and Includes" : "Host patterns").font(.caption).foregroundStyle(.secondary) }
                Text("Line \(block.start + 1)").font(.caption2).foregroundStyle(.tertiary)
            }
        }.padding(.vertical, 7)
    }
}

private struct FileEditor: View {
    @Bindable var workspace: Workspace
    @Bindable var file: EditableFile
    var block: SourceBlock? { file.parsed.blocks.first { $0.id == workspace.selectedBlockID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workspace.editorMode == "source" ? file.name : block?.title ?? file.name).font(.title2).fontWeight(.semibold).lineLimit(1)
                    Text(file.displayPath).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Picker("Edit mode", selection: $workspace.editorMode) {
                    Text("Fields").tag("fields")
                    Text("Source").tag("source")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 130)
            }.padding(20)
            Divider()
            if workspace.editorMode == "source" {
                TextEditor(text: $file.text)
                    .font(.system(size: 13, design: .monospaced)).padding(12)
                    .accessibilityLabel("Configuration source")
                HStack {
                    Text("Lines: \(file.parsed.lines.count) · UTF-8 · \(file.parsed.newline == "\r\n" ? "CRLF" : "LF")")
                    Spacer()
                    Text("Editing the entire file")
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            } else if let block {
                BlockFields(workspace: workspace, file: file, block: block)
            } else {
                ContentUnavailableView("Select a Block", systemImage: "server.rack")
            }
            if !file.parsed.diagnostics.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(file.parsed.diagnostics, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }.background(Color(nsColor: .textBackgroundColor))
    }
}

private struct BlockFields: View {
    @Bindable var workspace: Workspace
    let file: EditableFile
    let block: SourceBlock
    private let fields = ["HostName", "User", "Port", "IdentityFile", "ProxyJump", "ServerAliveInterval", "ForwardAgent"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if block.kind == "match" {
                    Label("Edit Match conditions in Source", systemImage: "line.3.horizontal.decrease").font(.headline)
                    Text("Conditions are not evaluated. No connections are made.").foregroundStyle(.secondary)
                    sourceExcerpt
                    Button("Edit Source") { workspace.editorMode = "source" }
                } else {
                    if block.kind == "host" { field("Host", title: "Host patterns") }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Block settings").font(.headline)
                        ForEach(fields, id: \.self) { key in field(key, title: key) }
                    }
                    Text("Blank fields are unset. Inherited values are not shown. Use Source for repeated directives and other settings.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Source preview").font(.headline)
                            Spacer()
                            Button("Edit") { workspace.editorMode = "source" }.buttonStyle(.link)
                        }
                        sourceExcerpt
                    }
                }
            }.padding(24).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func field(_ key: String, title: String) -> some View {
        let duplicate = file.parsed.occurrences(key, in: block).count > 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary); if duplicate { Text("Repeated directive — edit in Source").font(.caption).foregroundStyle(.orange) } }
            TextField("Not set", text: Binding(get: { file.parsed.value(key, in: block) }, set: { workspace.set(key, value: $0, blockID: block.id, file: file) }))
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced)).disabled(duplicate)
        }
    }
    private var sourceExcerpt: some View {
        Text(file.parsed.source(in: block))
            .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ChangesView: View {
    @Bindable var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Changes").font(.title2).fontWeight(.semibold)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(workspace.dirtyFiles) { file in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(file.displayPath).font(.headline)
                            HStack(alignment: .top, spacing: 16) {
                                source("Saved", text: file.snapshot.original.flatMap { String(data: $0, encoding: .utf8) } ?? "(New file)")
                                source("After changes", text: file.text)
                            }
                        }
                    }
                }
            }
            HStack {
                Text("Existing files are backed up before saving.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save All") { if workspace.saveAll() { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 880, height: 620)
        .alert("Could Not Save Changes", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
            Button("OK") { workspace.errorMessage = nil }
        } message: { Text(workspace.errorMessage ?? "") }
    }
    private func source(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
