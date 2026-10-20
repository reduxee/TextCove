import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let workspace = WorkspaceModel()

    func application(_ application: NSApplication, open urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        workspace.openFiles(fileURLs)

        NSApp.activate(ignoringOtherApps: true)
        if let window = application.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, let window = sender.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
