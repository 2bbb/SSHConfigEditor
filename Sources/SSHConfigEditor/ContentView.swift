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
        .alert("操作を完了できませんでした", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
            Button("OK") { workspace.errorMessage = nil }
        } message: { Text(workspace.errorMessage ?? "") }
        .sheet(isPresented: $workspace.showChanges) { ChangesView(workspace: workspace) }
        .sheet(item: $workspace.renameTarget) { file in RenameFileView(workspace: workspace, file: file) }
    }

    private var navigation: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("表示", selection: $sidebarMode) {
                    Text("ファイル").tag("files")
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
                    Button(action: workspace.addFragment) { Image(systemName: "doc.badge.plus") }.help("設定ファイルを追加")
                    Button(action: workspace.openConfig) { Image(systemName: "folder") }.help("ルート設定を開く")
                    Button { workspace.renameTarget = workspace.selected } label: { Image(systemName: "pencil") }
                        .help("ファイル名を変更（編集内容は先に保存）")
                        .disabled(workspace.selected?.snapshot.original == nil || !workspace.dirtyFiles.isEmpty)
                    Spacer()
                    Text("\(workspace.files.count)ファイル").font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.borderless).padding(12)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 360)
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Host・設定を検索", text: $workspace.query).textFieldStyle(.plain)
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
                    Button(action: workspace.addHost) { Label("Hostを追加", systemImage: "plus") }
                        .disabled(workspace.selected == nil)
                    Spacer()
                }.buttonStyle(.borderless).padding(12)
            }.navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 400)
        } detail: {
            if let file = workspace.selected {
                FileEditor(workspace: workspace, file: file)
            } else {
                ContentUnavailableView("設定ファイルを選択", systemImage: "doc.text", description: Text("左の一覧から編集するファイルを選択してください。"))
            }
        }
        .navigationTitle("SSH設定")
        .toolbar {
            ToolbarItemGroup {
                Button(action: workspace.reloadFromDisk) { Image(systemName: "arrow.clockwise") }.help("ディスクから再読み込み")
                Button { workspace.showChanges = true } label: { Label("変更を確認", systemImage: "square.split.2x1") }
                    .disabled(workspace.dirtyFiles.isEmpty)
                Button { workspace.saveAll() } label: { Label("すべて保存", systemImage: "square.and.arrow.down") }
                    .disabled(workspace.dirtyFiles.isEmpty)
                    .keyboardShortcut("s")
            }
        }
    }

    private var statusBar: some View {
            HStack(spacing: 12) {
                Image(systemName: workspace.dirtyFiles.isEmpty ? "checkmark.circle" : "circle.fill")
                    .foregroundStyle(workspace.dirtyFiles.isEmpty ? .secondary : Color.orange)
                Text(workspace.dirtyFiles.isEmpty ? "保存済み" : "\(workspace.dirtyFiles.count)ファイルに未保存の変更")
                if workspace.dragSession != nil {
                    Text("ファイルに重ねて待つと、挿入位置を選択できます").foregroundStyle(.secondary)
                } else if !workspace.status.isEmpty { Text(workspace.status).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                if workspace.lastBackup != nil {
                    Button("バックアップ") { NSWorkspace.shared.open(workspace.backupRoot) }.buttonStyle(.link)
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
                HStack { Text(file.name).fontWeight(.medium); if file.dirty { Circle().fill(.orange).frame(width: 6, height: 6).accessibilityLabel("未保存") } }
                if !file.referenced { Text("未参照").font(.caption2).foregroundStyle(.secondary) }
                Text(file.displayPath).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 5).help(file.displayPath)
        .contextMenu {
            Button("名前を変更…", action: rename).disabled(!canRename || file.snapshot.original == nil)
            Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([file.snapshot.url]) }
            Button("パスをコピー") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.snapshot.url.path, forType: .string) }
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
                Text(block.title.isEmpty ? "未設定" : block.title).fontWeight(.medium).lineLimit(2)
                if let document, block.kind == "host", !document.value("HostName", in: block).isEmpty {
                    Text(document.value("HostName", in: block)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                } else { Text(block.kind == "match" ? "Match条件" : block.kind == "global" ? "先頭の設定・Include" : "Hostパターン").font(.caption).foregroundStyle(.secondary) }
                Text("行 \(block.start + 1)").font(.caption2).foregroundStyle(.tertiary)
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
                Picker("編集方法", selection: $workspace.editorMode) {
                    Text("項目").tag("fields")
                    Text("原文").tag("source")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 130)
            }.padding(20)
            Divider()
            if workspace.editorMode == "source" {
                TextEditor(text: $file.text)
                    .font(.system(size: 13, design: .monospaced)).padding(12)
                    .accessibilityLabel("設定ファイルの原文")
                HStack {
                    Text("\(file.parsed.lines.count)行 · UTF-8 · \(file.parsed.newline == "\r\n" ? "CRLF" : "LF")")
                    Spacer()
                    Text("ファイル全体を編集")
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            } else if let block {
                BlockFields(workspace: workspace, file: file, block: block)
            } else {
                ContentUnavailableView("ブロックを選択", systemImage: "server.rack")
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
                    Label("Match条件は原文で編集します", systemImage: "line.3.horizontal.decrease").font(.headline)
                    Text("条件の実行や接続は行いません。").foregroundStyle(.secondary)
                    sourceExcerpt
                    Button("原文を編集") { workspace.editorMode = "source" }
                } else {
                    if block.kind == "host" { field("Host", title: "Hostパターン") }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("このブロックの設定").font(.headline)
                        ForEach(fields, id: \.self) { key in field(key, title: key) }
                    }
                    Text("空欄は未指定。継承後の値ではありません。複数行の項目・その他の設定は原文で編集できます。")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("原文プレビュー").font(.headline)
                            Spacer()
                            Button("編集") { workspace.editorMode = "source" }.buttonStyle(.link)
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
            HStack { Text(title).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary); if duplicate { Text("複数行あり — 原文で編集").font(.caption).foregroundStyle(.orange) } }
            TextField("未指定", text: Binding(get: { file.parsed.value(key, in: block) }, set: { workspace.set(key, value: $0, blockID: block.id) }))
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced)).disabled(duplicate)
        }
    }
    private var sourceExcerpt: some View {
        Text(file.parsed.lines[block.start..<min(block.end, file.parsed.lines.count)].joined(separator: "\n"))
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
            Text("保存前の確認").font(.title2).fontWeight(.semibold)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(workspace.dirtyFiles) { file in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(file.displayPath).font(.headline)
                            HStack(alignment: .top, spacing: 16) {
                                source("保存済み", text: file.snapshot.original.flatMap { String(data: $0, encoding: .utf8) } ?? "（新規ファイル）")
                                source("変更後", text: file.text)
                            }
                        }
                    }
                }
            }
            HStack {
                Text("既存ファイルは保存前にバックアップします。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("すべて保存") { if workspace.saveAll() { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 880, height: 620)
        .alert("保存できませんでした", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
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
