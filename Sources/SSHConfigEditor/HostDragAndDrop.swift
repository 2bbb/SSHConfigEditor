import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SSHConfigCore
import OSLog

struct HostDragSession {
    let token: String
    let sourceID: String
    let blockID: Int
    let originalText: String
}

enum HostDrag {
    static let type = UTType(exportedAs: "local.2bit.SSHConfigEditor.host-block")
    static let log = Logger(subsystem: "local.2bit.SSHConfigEditor", category: "drag")
}

/// AppKit provides the drag-ended callback SwiftUI onDrag lacks, including Escape
/// and drops outside the app. Only an opaque session token enters the pasteboard.
struct HostDragSource: NSViewRepresentable {
    let workspace: Workspace
    let file: EditableFile
    let block: SourceBlock

    func makeNSView(context: Context) -> DragView { DragView(workspace: workspace, file: file, block: block) }
    func updateNSView(_ view: DragView, context: Context) { view.file = file; view.block = block }

    @MainActor final class DragView: NSView, NSDraggingSource {
        let workspace: Workspace
        var file: EditableFile
        var block: SourceBlock
        private var downPoint: NSPoint?
        init(workspace: Workspace, file: EditableFile, block: SourceBlock) {
            self.workspace = workspace; self.file = file; self.block = block
            super.init(frame: .zero)
            setAccessibilityElement(false)
            toolTip = "別ファイルへドラッグして移動。重ねたまま待つと挿入位置を選択できます。"
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func mouseDown(with event: NSEvent) {
            downPoint = event.locationInWindow
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseUp(with event: NSEvent) {
            if downPoint != nil { workspace.selectedBlockID = block.id }
            downPoint = nil
        }
        override func mouseDragged(with event: NSEvent) {
            guard let point = downPoint, hypot(event.locationInWindow.x - point.x, event.locationInWindow.y - point.y) > 4 else { return }
            downPoint = nil
            let token = workspace.beginDrag(file: file, block: block)
            workspace.nativeDragSource = self
            let item = NSPasteboardItem()
            item.setString(token, forType: NSPasteboard.PasteboardType(HostDrag.type.identifier))
            let dragging = NSDraggingItem(pasteboardWriter: item)
            let image = NSImage(size: NSSize(width: 240, height: 36), flipped: false) { rect in
                NSColor.controlBackgroundColor.withAlphaComponent(0.95).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                ("Host " + self.block.title as NSString).draw(at: NSPoint(x: 12, y: 10), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor
                ])
                return true
            }
            dragging.setDraggingFrame(NSRect(x: 0, y: 0, width: 240, height: 36), contents: image)
            HostDrag.log.notice("Starting native Host drag")
            beginDraggingSession(with: [dragging], event: event, source: self)
            HostDrag.log.notice("Native Host drag session created")
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            HostDrag.log.notice("Native Host drag ended; operation=\(operation.rawValue)")
            workspace.endDrag()
        }
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    }
}

struct FileHostDrop: DropDelegate {
    let workspace: Workspace
    let file: EditableFile
    func validateDrop(info: DropInfo) -> Bool {
        workspace.dragSession.map { $0.sourceID != file.id } == true && info.hasItemsConforming(to: [HostDrag.type])
    }
    func dropEntered(info: DropInfo) { HostDrag.log.notice("File drop entered"); workspace.hoverFile(file) }
    func dropExited(info: DropInfo) { workspace.leaveFile(file) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: validateDrop(info: info) ? .move : .forbidden) }
    func performDrop(info: DropInfo) -> Bool { HostDrag.log.notice("File drop committed"); return workspace.moveDraggedHost(to: file) }
}

struct HostInsertionSlot: View {
    let workspace: Workspace
    let file: EditableFile
    let beforeBlockID: Int?
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
            Rectangle().frame(height: 2)
            Text(beforeBlockID == nil ? "末尾に移動" : "ここに移動").font(.caption).fixedSize()
        }
        .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.65))
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onDrop(of: [HostDrag.type], isTargeted: $targeted) { _ in
            workspace.moveDraggedHost(to: file, before: beforeBlockID)
        }
        .accessibilityLabel(beforeBlockID == nil ? "ファイル末尾へ移動" : "このブロックの前へ移動")
    }
}
