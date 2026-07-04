import AppKit
import SwiftUI

/// Borderless window that can still take keyboard focus (for the search field).
final class LaunchpadWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Content of the menu-bar cover; clicking it closes the overlay, matching a
/// click on any other empty part of the background.
private final class MenuBarCoverView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Owns the full-screen overlay window and its show/hide lifecycle.
final class LaunchpadController: NSObject, NSWindowDelegate {
    private var window: LaunchpadWindow?
    private var menuBarCover: NSWindow?
    private let model = LaunchpadModel()

    // Trackpad swipe accumulator for page flips.
    private var scrollAccum: CGFloat = 0
    private var scrollFired = false
    private var scrollMonitor: Any?

    // Bumped on every show()/close() so a close's fade-out completion can tell
    // whether a show() happened during the fade (and must not order out).
    private var showGeneration = 0

    /// Called when the user taps the "more" button in the search row.
    var onOpenSettings: (() -> Void)?

    var isOpen: Bool { window?.isVisible ?? false }

    func toggle() { isOpen ? close() : show() }

    @discardableResult
    func importFromLegacy() -> Int { model.importFromLegacy() }

    func show() {
        if window == nil { buildWindow() }
        guard let window else { return }
        showGeneration += 1

        // Always open to a clean state.
        model.query = ""
        model.openFolderID = nil
        model.currentPage = 0
        model.applyLayoutSettings()
        model.reload()

        // Show on whichever screen the cursor is on. The main window tiles
        // with the menu-bar cover (it stops where the strip begins) instead of
        // extending under it — the strip's blur must sample the wallpaper
        // directly, not our already-blurred output, to come out the same shade.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            var main = screen.frame
            main.size.height -= Self.menuBarRect(of: screen).height
            window.setFrame(main, display: true)
            model.dockInsets = Self.dockInsets(of: screen)
        }

        window.alphaValue = 0
        if let screen { showMenuBarCover(on: screen) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
            menuBarCover?.animator().alphaValue = 1
        }
    }

    func close() {
        guard let window, window.isVisible else { return }
        showGeneration += 1
        let gen = showGeneration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            window.animator().alphaValue = 0
            menuBarCover?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Skip if a show() re-opened the window during the fade.
            if self?.showGeneration == gen {
                window.orderOut(nil)
                self?.menuBarCover?.orderOut(nil)
            }
        })
    }

    // MARK: - Building

    private func buildWindow() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = LaunchpadWindow(contentRect: frame, styleMask: .borderless,
                                backing: .buffered, defer: false)
        // One level below the Dock: the overlay covers every normal window but
        // the Dock stays visible and clickable on top of it, like classic
        // Launchpad (clicking a Dock app resigns key and dismisses us).
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
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

        // Track display changes (resolution, monitor plug/unplug) while open.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let window = self.window, window.isVisible else { return }
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            if let screen {
                var main = screen.frame
                main.size.height -= Self.menuBarRect(of: screen).height
                window.setFrame(main, display: true)
                self.model.dockInsets = Self.dockInsets(of: screen)
                if let cover = self.menuBarCover, cover.isVisible {
                    cover.setFrame(Self.menuBarRect(of: screen), display: true)
                }
            }
        }
    }

    /// Edges of `screen` the Dock occupies (`visibleFrame` excludes it). The
    /// top is ignored — the menu bar is covered by `menuBarCover` while the
    /// overlay is up. With Dock auto-hide on, `visibleFrame` reaches the
    /// screen edge and the insets come out zero, which is what we want.
    private static func dockInsets(of screen: NSScreen) -> EdgeInsets {
        let f = screen.frame, v = screen.visibleFrame
        return EdgeInsets(top: 0,
                          leading: max(0, v.minX - f.minX),
                          bottom: max(0, v.minY - f.minY),
                          trailing: max(0, f.maxX - v.maxX))
    }

    // MARK: - Menu bar cover

    /// The overlay must stay *below* the Dock's window level, but the menu bar
    /// sits *above* the Dock — one window can't cover the menu bar without
    /// also covering the Dock. So the menu bar strip gets its own little
    /// higher-level window with the same blur, like classic Launchpad's
    /// all-blur, no-menu-bar look. (`NSMenu.setMenuBarVisible(false)` is not
    /// an option: it hides the Dock along with the menu bar.)
    private static func menuBarRect(of screen: NSScreen) -> NSRect {
        let f = screen.frame
        let h = f.maxY - screen.visibleFrame.maxY   // the Dock is never at the top
        return NSRect(x: f.minX, y: f.maxY - h, width: f.width, height: h)
    }

    private func showMenuBarCover(on screen: NSScreen) {
        let rect = Self.menuBarRect(of: screen)
        guard rect.height > 0 else {                // menu bar set to auto-hide
            menuBarCover?.orderOut(nil)
            return
        }
        if menuBarCover == nil { buildMenuBarCover() }
        guard let cover = menuBarCover else { return }
        cover.setFrame(rect, display: true)
        cover.alphaValue = 0
        cover.orderFront(nil)
    }

    private func buildMenuBarCover() {
        let cover = NSWindow(contentRect: .zero, styleMask: .borderless,
                             backing: .buffered, defer: false)
        cover.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        cover.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        cover.isOpaque = false
        cover.backgroundColor = .clear
        cover.hasShadow = false
        cover.appearance = NSAppearance(named: .darkAqua)

        // Same stack as the overlay background (hud blur + dark tint) so the
        // strip blends seamlessly into the page below it.
        let root = MenuBarCoverView()
        root.onClick = { [weak self] in self?.close() }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.frame = root.bounds
        blur.autoresizingMask = [.width, .height]
        root.addSubview(blur)
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        tint.frame = root.bounds
        tint.autoresizingMask = [.width, .height]
        root.addSubview(tint)
        cover.contentView = root
        menuBarCover = cover
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
        let sign = UserDefaults.standard.bool(forKey: "swipeReversed") ? -1 : 1

        if event.phase == [] {                               // discrete mouse wheel
            scrollAccum += dx
            if abs(scrollAccum) > 8 {
                let delta = (scrollAccum > 0 ? 1 : -1) * sign
                scrollAccum = 0
                withAnimation(.easeInOut) { self.model.changePage(delta) }
            }
            return
        }
        if event.phase == .began { scrollAccum = 0; scrollFired = false }
        scrollAccum += dx
        if !scrollFired, abs(scrollAccum) > 30 {
            scrollFired = true
            withAnimation(.easeInOut) { self.model.changePage((scrollAccum > 0 ? 1 : -1) * sign) }
        }
        if event.phase == .ended || event.phase == .cancelled { scrollAccum = 0; scrollFired = false }
    }

    func applyLayoutSettings() { model.applyLayoutSettings() }

    private func launch(_ app: AppInfo) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
            guard let error else { return }
            // A damaged/translocated app would otherwise just close the
            // overlay with no feedback at all.
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(
                    format: NSLocalizedString("Could not open “%@”", comment: ""), app.name)
                alert.informativeText = error.localizedDescription
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
        close()
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Dismiss when the user switches away (e.g. ⌘-Tab).
        close()
    }
}
