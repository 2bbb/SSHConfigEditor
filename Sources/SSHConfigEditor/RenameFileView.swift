import SwiftUI
import SSHConfigCore

struct RenameFileView: View {
    @Bindable var workspace: Workspace
    let file: EditableFile
    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, file: EditableFile) {
        self.workspace = workspace; self.file = file
        // A one-time draft; changes are committed only by the explicit action.
        _name = State(initialValue: file.name)
    }
    private var result: Result<FileRenamePlan, Error> { Result { try workspace.planRename(file, to: name) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ファイル名を変更").font(.title2).fontWeight(.semibold)
            Text(file.displayPath).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            TextField("新しい名前・相対パス", text: $name).textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text("hoge/bar で現在のフォルダ内の hoge へ移動。必要なフォルダは作成します。")
                .font(.caption).foregroundStyle(.secondary)
            switch result {
            case .success(let plan):
                Text("参照元の更新：\(plan.rewrites.count)ファイル").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(plan.rewrites, id: \.url) { rewrite in
                            VStack(alignment: .leading, spacing: 5) {
                                Text((rewrite.url.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                                ForEach(rewrite.lines, id: \.self) { line in
                                    Text("\(line): " + ConfigDocument(rewrite.after).lines[line - 1])
                                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                }
                            }
                        }
                        if plan.rewrites.isEmpty { Text("直接指定の更新はありません。Includeのワイルドカードは維持されます。").foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("開いている設定内のIncludeが対象です。ワイルドカードの読み込み順はファイル名に応じて変わります。")
                    .font(.caption).foregroundStyle(.secondary)
            case .failure(let error):
                Text(error.localizedDescription).foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("名前と参照元を変更") { if workspace.rename(file, to: name) { dismiss() } }
                    .keyboardShortcut(.defaultAction).disabled((try? result.get()) == nil)
            }
        }.padding(24).frame(width: 650, height: 440)
        .alert("名前を変更できませんでした", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
            Button("OK") { workspace.errorMessage = nil }
        } message: { Text(workspace.errorMessage ?? "") }
    }
}
