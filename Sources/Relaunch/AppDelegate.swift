import AppKit

/// Central coordinator. Owns the Launchpad window, the status-bar item, the
/// global hotkey, and the trackpad gesture detector, and wires them together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let launchpad = LaunchpadController()
    private var statusBar: StatusBarController!
    private var hotkey: HotkeyManager!
    private var gesture: MultitouchGesture!

    private let defaults = UserDefaults.standard
    private let gestureKey = "gestureEnabled"
    private let hotkeyKey = "hotkeyEnabled"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // First-run defaults.
        if defaults.object(forKey: gestureKey) == nil { defaults.set(true, forKey: gestureKey) }
        if defaults.object(forKey: hotkeyKey) == nil { defaults.set(true, forKey: hotkeyKey) }

        // Global hotkey (⌃⌥L by default). If registration fails (e.g. the
        // combo is already taken), reflect the real disabled state.
        hotkey = HotkeyManager { [weak self] in self?.launchpad.toggle() }
        if defaults.bool(forKey: hotkeyKey), !hotkey.register() {
            defaults.set(false, forKey: hotkeyKey)
        }

        // Trackpad gesture: thumb + three/four-finger pinch-in.
        gesture = MultitouchGesture { [weak self] in self?.launchpad.show() }
        if defaults.bool(forKey: gestureKey) { gesture.start() }

        // Persistent menu-bar icon.
        statusBar = StatusBarController(
            onOpen: { [weak self] in self?.launchpad.show() },
            isLoginEnabled: { LoginItem.isEnabled },
            setLogin: { LoginItem.set($0) },
            isGestureEnabled: { [weak self] in self?.defaults.bool(forKey: self?.gestureKey ?? "") ?? false },
            setGesture: { [weak self] in self?.setGesture($0) },
            isHotkeyEnabled: { [weak self] in self?.defaults.bool(forKey: self?.hotkeyKey ?? "") ?? false },
            setHotkey: { [weak self] in self?.setHotkey($0) }
        )
    }

    private func setGesture(_ on: Bool) {
        defaults.set(on, forKey: gestureKey)
        if on { gesture.start() } else { gesture.stop() }
    }

    private func setHotkey(_ on: Bool) {
        if on {
            // Only persist "enabled" if registration actually succeeded.
            let ok = hotkey.register()
            defaults.set(ok, forKey: hotkeyKey)
        } else {
            hotkey.unregister()
            defaults.set(false, forKey: hotkeyKey)
        }
    }
}
