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

        let open = NSMenuItem(title: "打开启动台", action: #selector(openLaunchpad), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let importItem = NSMenuItem(title: "导入旧版启动台分组",
                                    action: #selector(doImport), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Relaunch", action: #selector(quit), keyEquivalent: "q")
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
            alert.messageText = "已导入旧版启动台布局"
            alert.informativeText = "已还原页面顺序与文件夹分组,共 \(count) 个项目。"
        } else {
            alert.messageText = "未找到旧版启动台数据"
            alert.informativeText = "这台 Mac 上没有可导入的旧版启动台数据库。"
        }
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
