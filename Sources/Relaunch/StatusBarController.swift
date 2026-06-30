import AppKit

/// Menu-bar status item and its dropdown menu. Created only when the user has
/// enabled the menu-bar icon; releasing the instance removes the item.
final class StatusBarController: NSObject {
    private let item: NSStatusItem

    private let onOpen: () -> Void
    private let onSettings: () -> Void
    private let importLegacy: () -> Int

    init(onOpen: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         importLegacy: @escaping () -> Int) {
        self.onOpen = onOpen
        self.onSettings = onSettings
        self.importLegacy = importLegacy

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            let image = NSImage(systemSymbolName: "square.grid.3x3.fill",
                                accessibilityDescription: "Relaunch")
            image?.isTemplate = true
            button.image = image
        }
        buildMenu()
    }

    deinit { NSStatusBar.system.removeStatusItem(item) }

    private func buildMenu() {
        let menu = NSMenu()

        let open = NSMenuItem(title: NSLocalizedString("Open Launchpad", comment: ""),
                              action: #selector(openLaunchpad), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: NSLocalizedString("Settings…", comment: ""),
                                  action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let importItem = NSMenuItem(title: NSLocalizedString("Import classic Launchpad layout", comment: ""),
                                    action: #selector(doImport), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: NSLocalizedString("Quit Relaunch", comment: ""),
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func openLaunchpad() { onOpen() }
    @objc private func openSettings() { onSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func doImport() {
        let count = importLegacy()
        let alert = NSAlert()
        if count >= 0 {
            alert.messageText = NSLocalizedString("Imported classic Launchpad layout", comment: "")
            alert.informativeText = String(format: NSLocalizedString("Restored page order and folders — %lld items.", comment: ""), count)
        } else {
            alert.messageText = NSLocalizedString("No classic Launchpad data", comment: "")
            alert.informativeText = NSLocalizedString("There is no classic Launchpad database to import on this Mac.", comment: "")
        }
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
