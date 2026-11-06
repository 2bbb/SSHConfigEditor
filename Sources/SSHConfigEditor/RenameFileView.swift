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
            Text("Rename File").font(.title2).fontWeight(.semibold)
            Text(file.displayPath).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            TextField("New name or relative path", text: $name).textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text("Use folder/file to move into a subfolder. Missing folders will be created.")
                .font(.caption).foregroundStyle(.secondary)
            switch result {
            case .success(let plan):
                Text("Files with Include updates: \(plan.rewrites.count)").font(.headline)
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
                        if plan.rewrites.isEmpty { Text("No explicit references need updating. Include wildcards will be preserved.").foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Updates Include references in loaded files. Renaming can change wildcard expansion order.")
                    .font(.caption).foregroundStyle(.secondary)
            case .failure(let error):
                Text(error.localizedDescription).foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename and Update Includes") { if workspace.rename(file, to: name) { dismiss() } }
                    .keyboardShortcut(.defaultAction).disabled((try? result.get()) == nil)
            }
        }.padding(24).frame(width: 650, height: 440)
        .alert("Could Not Rename File", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
            Button("OK") { workspace.errorMessage = nil }
        } message: { Text(workspace.errorMessage ?? "") }
    }
}
