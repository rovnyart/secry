import SwiftUI
import AppKit

@main enum EntryPoint {
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--cli" {
            exit(SecryCLI.run(Array(CommandLine.arguments.dropFirst(2))))
        }
        #if DEBUG
        if let flag = CommandLine.arguments.firstIndex(of: "--export-previews"),
           CommandLine.arguments.indices.contains(flag + 1) {
            exportPreviews(to: CommandLine.arguments[flag + 1])
            return
        }
        if CommandLine.arguments.contains("--preview") {
            SecryPreviewApp.main()
            return
        }
        #endif
        SecryApp.main()
    }
}

struct SecryApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
