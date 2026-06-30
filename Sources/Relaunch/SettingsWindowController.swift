import AppKit
import SwiftUI

/// A standard titled window hosting the SwiftUI settings panel.
final class SettingsWindowController {
    private var window: NSWindow?
    private let actions: SettingsActions

    init(actions: SettingsActions) { self.actions = actions }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(actions: actions))
            let w = NSWindow(contentViewController: host)
            w.title = NSLocalizedString("Relaunch Settings", comment: "")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
