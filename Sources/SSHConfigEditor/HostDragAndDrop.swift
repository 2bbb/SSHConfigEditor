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

    @MainActor final class DragView: NSView {
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
            let coordinator = HostDragCoordinator(workspace: workspace)
            workspace.nativeDragSource = coordinator
            let item = NSPasteboardItem()
            item.setString(token, forType: NSPasteboard.PasteboardType(HostDrag.type.identifier))
            let dragging = NSDraggingItem(pasteboardWriter: item)
            let title = block.title
            let image = NSImage(size: NSSize(width: 240, height: 36), flipped: false) { rect in
                NSColor.controlBackgroundColor.withAlphaComponent(0.95).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                ("Host " + title as NSString).draw(at: NSPoint(x: 12, y: 10), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor
                ])
                return true
            }
            // The source row disappears on spring loading. Start the session from
            // the persistent window surface so AppKit does not cancel it on removal.
            let surface = workspace.dragSurface ?? self
            let imagePoint = surface.convert(event.locationInWindow, from: nil)
            dragging.setDraggingFrame(NSRect(x: imagePoint.x - 20, y: imagePoint.y - 18, width: 240, height: 36), contents: image)
            HostDrag.log.notice("Starting native Host drag")
            surface.beginDraggingSession(with: [dragging], event: event, source: coordinator)
            HostDrag.log.notice("Native Host drag session created")
        }
    }
}

@MainActor final class HostDragCoordinator: NSObject, NSDraggingSource {
    let workspace: Workspace
    init(workspace: Workspace) { self.workspace = workspace }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        HostDrag.log.notice("Native Host drag ended; operation=\(operation.rawValue)")
        workspace.endDrag()
        // AppKit may still use the source while unwinding the end callback.
        DispatchQueue.main.async { [self] in
            if workspace.nativeDragSource === self { workspace.nativeDragSource = nil }
        }
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

struct NativeHostDropTarget: NSViewRepresentable {
    let workspace: Workspace
    let file: EditableFile
    var beforeBlockID: Int? = nil
    var springLoads = false
    var highlight: (Bool) -> Void = { _ in }
    func makeNSView(context: Context) -> DestinationView { DestinationView() }
    func updateNSView(_ view: DestinationView, context: Context) {
        view.workspace = workspace; view.file = file; view.beforeBlockID = beforeBlockID
        view.springLoads = springLoads; view.highlight = highlight
    }

    @MainActor final class DestinationView: NSView {
        var workspace: Workspace?
        var file: EditableFile?
        var beforeBlockID: Int?
        var springLoads = false
        var highlight: (Bool) -> Void = { _ in }
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([NSPasteboard.PasteboardType(HostDrag.type.identifier)])
            setAccessibilityElement(false)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            if springLoads, let file { workspace?.select(path: file.snapshot.url.path) }
        }
        private func accepts(_ sender: NSDraggingInfo) -> Bool {
            guard let drag = workspace?.dragSession, let file, drag.sourceID != file.id else { return false }
            return sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType(HostDrag.type.identifier)) == drag.token
        }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard accepts(sender), let file else { return [] }
            HostDrag.log.notice("Native destination entered")
            highlight(true)
            if springLoads { workspace?.hoverFile(file) }
            return .move
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .move : [] }
        override func draggingExited(_ sender: NSDraggingInfo?) {
            highlight(false)
            if springLoads, let file { workspace?.leaveFile(file) }
        }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard accepts(sender), let file else { return false }
            HostDrag.log.notice("Native destination committed; insertion=\(self.beforeBlockID != nil)")
            highlight(false)
            return workspace?.moveDraggedHost(to: file, before: beforeBlockID) ?? false
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            guard springLoads, let file, let workspace else { return nil }
            workspace.select(path: file.snapshot.url.path)
            let menu = NSMenu()
            let rename = menu.addItem(withTitle: "名前を変更…", action: #selector(renameFile), keyEquivalent: "")
            rename.target = self; rename.isEnabled = workspace.dirtyFiles.isEmpty && file.snapshot.original != nil
            let reveal = menu.addItem(withTitle: "Finderで表示", action: #selector(revealFile), keyEquivalent: "")
            reveal.target = self
            let copy = menu.addItem(withTitle: "パスをコピー", action: #selector(copyPath), keyEquivalent: "")
            copy.target = self
            menu.autoenablesItems = false
            return menu
        }
        @objc private func renameFile() { workspace?.renameTarget = file }
        @objc private func revealFile() { if let file { NSWorkspace.shared.activateFileViewerSelecting([file.snapshot.url]) } }
        @objc private func copyPath() {
            if let file { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.snapshot.url.path, forType: .string) }
        }
    }
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
        .overlay {
            NativeHostDropTarget(workspace: workspace, file: file, beforeBlockID: beforeBlockID,
                                 highlight: { targeted = $0 })
        }
        .accessibilityLabel(beforeBlockID == nil ? "ファイル末尾へ移動" : "このブロックの前へ移動")
    }
}
