import SwiftUI

struct FileTreeNode: Identifiable {
    let id: String
    let title: String
    var file: EditableFile?
    var children: [FileTreeNode] = []

    mutating func insert(_ file: EditableFile, components: ArraySlice<String>, directory: URL) {
        guard let first = components.first else { return }
        if components.count == 1 {
            children.append(FileTreeNode(id: file.id, title: first, file: file))
            return
        }
        let folder = directory.appendingPathComponent(first, isDirectory: true)
        let id = "folder:" + folder.path
        if !children.contains(where: { $0.id == id }) {
            children.append(FileTreeNode(id: id, title: first))
        }
        let index = children.firstIndex { $0.id == id }!
        children[index].insert(file, components: components.dropFirst(), directory: folder)
    }
    mutating func sort() {
        for index in children.indices { children[index].sort() }
        children.sort {
            if ($0.file == nil) != ($1.file == nil) { return $0.file == nil }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}

struct FileTreeRow: View {
    let node: FileTreeNode
    @Bindable var workspace: Workspace
    var body: some View {
        if let file = node.file {
            FileRow(file: file, canRename: workspace.dirtyFiles.isEmpty) { workspace.renameTarget = file }
                .tag(file.id)
                .listRowBackground(workspace.hoveredFileID == file.id ? Color.accentColor.opacity(0.22) : Color.clear)
                .overlay { NativeHostDropTarget(workspace: workspace, file: file, springLoads: true) }
        } else {
            DisclosureGroup(isExpanded: Binding(get: { !workspace.collapsedFolders.contains(node.id) }, set: { expanded in
                if expanded { workspace.collapsedFolders.remove(node.id) } else { workspace.collapsedFolders.insert(node.id) }
            })) {
                ForEach(node.children) { child in FileTreeRow(node: child, workspace: workspace) }
            } label: {
                Label(node.title, systemImage: "folder").foregroundStyle(.secondary).padding(.vertical, 3)
            }
        }
    }
}
