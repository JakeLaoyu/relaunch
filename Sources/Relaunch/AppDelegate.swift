import AppKit

/// Central coordinator. Owns the Launchpad window, the status-bar item, the
/// settings window, the global hotkey, and the trackpad gesture detector.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let launchpad = LaunchpadController()
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController!
    private var hotkey: HotkeyManager!
    private var gesture: MultitouchGesture!

    private let defaults = UserDefaults.standard
    private let gestureKey = "gestureEnabled"
    private let hotkeyKey = "hotkeyEnabled"
    private let dockKey = "showDock"
    private let menuBarKey = "showMenuBar"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First-run defaults.
        for key in [gestureKey, hotkeyKey, dockKey, menuBarKey] where defaults.object(forKey: key) == nil {
            defaults.set(true, forKey: key)
        }

        applyActivationPolicy()

        hotkey = HotkeyManager { [weak self] in self?.launchpad.toggle() }
        if defaults.bool(forKey: hotkeyKey), !hotkey.register() {
            defaults.set(false, forKey: hotkeyKey)
        }

        gesture = MultitouchGesture { [weak self] in self?.launchpad.show() }
        if defaults.bool(forKey: gestureKey) { gesture.start() }

        let actions = SettingsActions(
            setDock: { [weak self] in self?.setShowDock($0) },
            setMenuBar: { [weak self] in self?.setShowMenuBar($0) },
            setLogin: { LoginItem.set($0) },
            setGesture: { [weak self] in self?.setGesture($0) },
            setHotkey: { [weak self] in self?.setHotkey($0) },
            isLogin: { LoginItem.isEnabled },
            importLegacy: { [weak self] in self?.launchpad.importFromLegacy() ?? -1 }
        )
        settingsWindow = SettingsWindowController(actions: actions)
        launchpad.onOpenSettings = { [weak self] in self?.openSettings() }

        if defaults.bool(forKey: menuBarKey) { showStatusItem() }
    }

    /// Clicking the Dock icon opens the Launchpad.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !launchpad.isOpen { launchpad.show() }
        return true
    }

    // MARK: - Settings actions

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(defaults.bool(forKey: dockKey) ? .regular : .accessory)
    }

    private func setShowDock(_ on: Bool) {
        defaults.set(on, forKey: dockKey)
        applyActivationPolicy()
        // Keep at least one affordance visible.
        if !on && !defaults.bool(forKey: menuBarKey) { setShowMenuBar(true) }
    }

    private func setShowMenuBar(_ on: Bool) {
        defaults.set(on, forKey: menuBarKey)
        if on { showStatusItem() } else { statusBar = nil }
        if !on && !defaults.bool(forKey: dockKey) { setShowDock(true) }
    }

    private func showStatusItem() {
        guard statusBar == nil else { return }
        statusBar = StatusBarController(
            onOpen: { [weak self] in self?.launchpad.show() },
            onSettings: { [weak self] in self?.openSettings() },
            importLegacy: { [weak self] in self?.launchpad.importFromLegacy() ?? -1 }
        )
    }

    private func openSettings() { settingsWindow.show() }

    private func setGesture(_ on: Bool) {
        defaults.set(on, forKey: gestureKey)
        if on { gesture.start() } else { gesture.stop() }
    }

    private func setHotkey(_ on: Bool) {
        if on {
            let ok = hotkey.register()
            defaults.set(ok, forKey: hotkeyKey)
        } else {
            hotkey.unregister()
            defaults.set(false, forKey: hotkeyKey)
        }
    }
}
