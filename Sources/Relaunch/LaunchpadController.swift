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

    // Trackpad swipe accumulator for page flips.
    private var scrollAccum: CGFloat = 0
    private var scrollFired = false
    private var scrollMonitor: Any?

    /// Called when the user taps the "more" button in the search row.
    var onOpenSettings: (() -> Void)?

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
        model.currentPage = 0
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

        let root = LaunchpadView(
            model: model,
            onLaunch: { [weak self] in self?.launch($0) },
            onClose: { [weak self] in self?.close() },
            onOpenSettings: { [weak self] in
                self?.close()
                self?.onOpenSettings?()
            }
        )
        // Host the SwiftUI content as the window's contentViewController so it
        // sits properly in the responder chain — drag-and-drop sources need
        // this, otherwise taps work but drags silently fail. The blur is now a
        // SwiftUI background (VisualEffectView) instead of a wrapping NSView.
        w.contentViewController = NSHostingController(rootView: root)
        window = w
        setupScrollMonitor()
    }

    private func setupScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    /// Two-finger trackpad swipe (or horizontal wheel) flips pages.
    private func handleScroll(_ event: NSEvent) {
        guard let window, window.isVisible, window.isKeyWindow,
              model.openFolderID == nil, model.query.isEmpty else { return }
        if event.momentumPhase != [] { return }              // ignore inertia
        let dx = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY

        if event.phase == [] {                               // discrete mouse wheel
            scrollAccum += dx
            if abs(scrollAccum) > 8 {
                let delta = scrollAccum > 0 ? 1 : -1
                scrollAccum = 0
                withAnimation(.easeInOut) { self.model.changePage(delta) }
            }
            return
        }
        if event.phase == .began { scrollAccum = 0; scrollFired = false }
        scrollAccum += dx
        if !scrollFired, abs(scrollAccum) > 30 {
            scrollFired = true
            withAnimation(.easeInOut) { self.model.changePage(scrollAccum > 0 ? 1 : -1) }
        }
        if event.phase == .ended || event.phase == .cancelled { scrollAccum = 0; scrollFired = false }
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
