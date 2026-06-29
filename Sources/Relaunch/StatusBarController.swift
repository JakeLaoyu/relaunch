import AppKit

/// Persistent menu-bar item with its dropdown menu.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem

    private let onOpen: () -> Void
    private let isLoginEnabled: () -> Bool
    private let setLogin: (Bool) -> Void
    private let isGestureEnabled: () -> Bool
    private let setGesture: (Bool) -> Void
    private let isHotkeyEnabled: () -> Bool
    private let setHotkey: (Bool) -> Void

    private let loginItem = NSMenuItem(title: "开机启动", action: #selector(toggleLogin), keyEquivalent: "")
    private let gestureItem = NSMenuItem(title: "捏合手势唤起", action: #selector(toggleGesture), keyEquivalent: "")
    private let hotkeyItem = NSMenuItem(title: "快捷键唤起 (⌃⌥L)", action: #selector(toggleHotkey), keyEquivalent: "")

    init(onOpen: @escaping () -> Void,
         isLoginEnabled: @escaping () -> Bool,
         setLogin: @escaping (Bool) -> Void,
         isGestureEnabled: @escaping () -> Bool,
         setGesture: @escaping (Bool) -> Void,
         isHotkeyEnabled: @escaping () -> Bool,
         setHotkey: @escaping (Bool) -> Void) {
        self.onOpen = onOpen
        self.isLoginEnabled = isLoginEnabled
        self.setLogin = setLogin
        self.isGestureEnabled = isGestureEnabled
        self.setGesture = setGesture
        self.isHotkeyEnabled = isHotkeyEnabled
        self.setHotkey = setHotkey

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

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let open = NSMenuItem(title: "打开启动台", action: #selector(openLaunchpad), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        for entry in [hotkeyItem, gestureItem, loginItem] {
            entry.target = self
            menu.addItem(entry)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Relaunch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    // Refresh checkmarks each time the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = isLoginEnabled() ? .on : .off
        gestureItem.state = isGestureEnabled() ? .on : .off
        hotkeyItem.state = isHotkeyEnabled() ? .on : .off
    }

    @objc private func openLaunchpad() { onOpen() }
    @objc private func toggleLogin() { setLogin(!isLoginEnabled()) }
    @objc private func toggleGesture() { setGesture(!isGestureEnabled()) }
    @objc private func toggleHotkey() { setHotkey(!isHotkeyEnabled()) }
    @objc private func quit() { NSApp.terminate(nil) }
}
