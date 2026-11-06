import SwiftUI
import AppKit

@main
struct SSHConfigEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var workspace = Workspace()

    var body: some Scene {
        Window("SSH設定", id: "editor") {
            ContentView(workspace: workspace)
                .frame(minWidth: 980, minHeight: 620)
                .background(WindowGuard(workspace: workspace))
                .onAppear {
                    delegate.workspace = workspace
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("設定を開く…", action: workspace.openConfig).keyboardShortcut("o")
                Button("~/.ssh/config を開く", action: workspace.openDefault)
                Divider()
                Button("Hostを追加", action: workspace.addHost).keyboardShortcut("n")
                Button("設定ファイルを追加…", action: workspace.addFragment).keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("すべて保存") { workspace.saveAll() }.keyboardShortcut("s").disabled(workspace.dirtyFiles.isEmpty)
                Button("変更を確認…") { workspace.showChanges = true }.disabled(workspace.dirtyFiles.isEmpty)
                Button("ディスクから再読み込み", action: workspace.reloadFromDisk).keyboardShortcut("r")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var workspace: Workspace?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace?.confirmDiscard() == false ? .terminateCancel : .terminateNow
    }
}

struct WindowGuard: NSViewRepresentable {
    let workspace: Workspace
    func makeNSView(context: Context) -> GuardView {
        let view = GuardView(); view.workspace = workspace; return view
    }
    func updateNSView(_ nsView: GuardView, context: Context) {}
    @MainActor final class GuardView: NSView, NSWindowDelegate {
        var workspace: Workspace?
        override func viewDidMoveToWindow() {
            window?.delegate = self
            if window != nil { workspace?.dragSurface = self }
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool { workspace?.confirmDiscard() ?? true }
    }
}
