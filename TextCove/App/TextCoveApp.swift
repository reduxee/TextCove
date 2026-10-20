import SwiftUI

@main
struct TextCoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("TextCove", id: "main") {
            ContentView(workspace: appDelegate.workspace)
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    appDelegate.workspace.openFiles([url])
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            TextCoveCommands(workspace: appDelegate.workspace)
        }
    }
}
