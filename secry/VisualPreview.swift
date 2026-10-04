#if DEBUG
import SwiftUI

/// Render the real library view with disposable data for documentation.
@MainActor func exportPreviews(to directory: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let fixtures = ["anthropic", "github", "sentry", "stripe"].map {
        SecretSet(name: $0, fields: [SecretField(key: "API_KEY", value: "demo-only")])
    }
    try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
        let vault = Vault(previewSets: fixtures)
        let host = NSHostingView(rootView: ContentView(vault: vault).preferredColorScheme(scheme))
        let frame = NSRect(x: 0, y: 0, width: 380, height: 426)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.frame = frame
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.center()
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), URL(fileURLWithPath: directory).appendingPathComponent("library-\(name).png").path]
        try! capture.run()
        capture.waitUntilExit()
        window.orderOut(nil)
    }
}

/// Runs the actual panel with disposable, memory-only fixtures. No Keychain or
/// socket connection is created. Used for visual checks of long/empty states.
struct SecryPreviewApp: App {
    @NSApplicationDelegateAdaptor(PreviewMenuDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("secry · Visual QA") { PreviewHost() }
            .windowResizability(.contentSize)

    }
}

@MainActor private final class PreviewMenuDelegate: NSObject, NSApplicationDelegate {
    static weak var current: PreviewMenuDelegate?
    private var controller: MenuBarController?
    func openContextMenu() { controller?.showContextMenu() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        controller = MenuBarController(vault: Vault(previewSets: [
            SecretSet(name: "delete-test", fields: [SecretField(key: "TEST_KEY", value: "disposable-test-value")]),
            SecretSet(name: "keep-test", fields: [SecretField(key: "TEST_KEY", value: "disposable-test-value")])
        ]), title: "secry · Menu QA", symbol: "key.horizontal.fill")
    }
}

private struct PreviewHost: View {
    @State private var vault = Vault(previewSets: Self.samples(30))
    @State private var count = 30
    @State private var dark = false
    @State private var generation = UUID()
    static func samples(_ count: Int) -> [SecretSet] {
        let names = ["anthropic", "aws-production", "figma", "github", "linear", "openai", "private-note", "sentry", "stripe", "vercel"]
        return (0..<count).map { index in
            let name = count > 10 ? String(format: "%02d-", index + 1) + names[index % names.count] : names[index % names.count]
            let fields = index == 6 ? [SecretField(key: "SECRET", value: "A private note.\nThis is only a visual test fixture.")] :
                (0..<(index == 0 ? 24 : index % 3 + 1)).map { SecretField(key: $0 == 0 ? "API_KEY" : "PROJECT_VARIABLE_\($0)", value: "demo-only-not-a-real-secret") }
            return SecretSet(name: name, fields: fields)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            ContentView(vault: vault).id(generation)
            Divider()
            Button("Menu-bar context menu") { PreviewMenuDelegate.current?.openContextMenu() }
                .padding(.top, 10)
            HStack {
                Picker("Fixtures", selection: $count) {
                    Text("Empty").tag(0); Text("One").tag(1); Text("30 sets").tag(30)
                }.frame(width: 210)
                Toggle("Dark", isOn: $dark).toggleStyle(.checkbox)
            }.padding(12).background(.bar)
        }.frame(width: 380).preferredColorScheme(dark ? .dark : .light)
            .onChange(of: count) { _, value in
                vault = Vault(previewSets: Self.samples(value)); generation = UUID()
            }
    }
}
#endif
