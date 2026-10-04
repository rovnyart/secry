import AppKit
import SwiftUI

/// Own the status item so secondary clicks have a native NSMenu, independent
/// of the SwiftUI content. Left-click retains the transient secret popover.
@MainActor final class MenuBarController: NSObject, NSMenuDelegate {
    private let vault: Vault
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let contextMenu = NSMenu()
    private var closeAccessItem: NSMenuItem!

    init(vault: Vault, title: String = "secry", symbol: String = "key.horizontal") {
        self.vault = vault
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.image?.isTemplate = true
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let content = NSHostingController(rootView: ContentView(vault: vault))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = true
        contextMenu.delegate = self
        contextMenu.autoenablesItems = false
        addMenuItem("Open secry", action: #selector(openFromMenu), symbol: "key.horizontal")
        contextMenu.addItem(.separator())
        closeAccessItem = addMenuItem("Close All Agent Access", action: #selector(closeAgentAccess), symbol: "lock")
        contextMenu.addItem(.separator())
        addMenuItem("Quit secry", action: #selector(quit), symbol: "power", key: "q")
    }

    @discardableResult
    private func addMenuItem(_ title: String, action: Selector, symbol: String, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        contextMenu.addItem(entry)
        return entry
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showContextMenu() {
        popover.performClose(nil)
        closeAccessItem.isEnabled = vault.grants.values.contains { $0 > Date() }
        item.menu = contextMenu
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Restore left-click behavior immediately after native menu tracking.
        item.menu = nil
    }

    @objc private func openFromMenu() {
        // Wait until menu tracking finishes before opening another surface.
        DispatchQueue.main.async { [weak self] in self?.showPopover() }
    }

    private func showPopover() {
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func closeAgentAccess() { vault.grants.removeAll() }
    @objc private func quit() { NSApp.terminate(nil) }
}

@MainActor final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController(vault: Vault())
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
