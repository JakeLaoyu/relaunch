import AppKit
import SwiftUI

/// Borderless window that can still take keyboard focus (for the search field).
final class LaunchpadWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the full-screen overlay window and its show/hide lifecycle.
final class LaunchpadController: NSObject, NSWindowDelegate {
    private var window: LaunchpadWindow?
    private let model = LaunchpadModel()

    var isOpen: Bool { window?.isVisible ?? false }

    func toggle() { isOpen ? close() : show() }

    @discardableResult
    func importFromLegacy() -> Int { model.importFromLegacy() }

    func show() {
        if window == nil { buildWindow() }
        guard let window else { return }

        // Always open to a clean state.
        model.query = ""
        model.openFolderID = nil
        model.reload()

        // Show on whichever screen the cursor is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.frame { window.setFrame(frame, display: true) }

        window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
        }
    }

    func close() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    // MARK: - Building

    private func buildWindow() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = LaunchpadWindow(contentRect: frame, styleMask: .borderless,
                                backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.delegate = self

        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]

        let root = LaunchpadView(
            model: model,
            onLaunch: { [weak self] in self?.launch($0) },
            onClose: { [weak self] in self?.close() }
        )
        let host = NSHostingView(rootView: root)
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)

        w.contentView = effect
        window = w
    }

    private func launch(_ app: AppInfo) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, _ in }
        close()
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Dismiss when the user switches away (e.g. ⌘-Tab).
        close()
    }
}
