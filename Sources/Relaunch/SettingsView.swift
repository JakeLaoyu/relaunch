import SwiftUI

/// Actions the settings UI invokes on the coordinator (AppDelegate).
struct SettingsActions {
    let setDock: (Bool) -> Void
    let setMenuBar: (Bool) -> Void
    let setLogin: (Bool) -> Void
    let setGesture: (Bool) -> Void
    let setHotkey: (Bool) -> Void
    let isLogin: () -> Bool
    let importLegacy: () -> Int
}

struct SettingsView: View {
    let actions: SettingsActions

    @AppStorage("showDock") private var showDock = true
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("gestureEnabled") private var gestureEnabled = true
    @AppStorage("hotkeyEnabled") private var hotkeyEnabled = true
    @State private var launchAtLogin = false
    @State private var importResult: String?

    var body: some View {
        Form {
            Section("显示") {
                Toggle("在 Dock 显示图标", isOn: $showDock)
                    .onChange(of: showDock) { actions.setDock(showDock) }
                Toggle("在菜单栏显示图标", isOn: $showMenuBar)
                    .onChange(of: showMenuBar) { actions.setMenuBar(showMenuBar) }
            }

            Section("唤起方式") {
                Toggle("触控板捏合手势", isOn: $gestureEnabled)
                    .onChange(of: gestureEnabled) { actions.setGesture(gestureEnabled) }
                Toggle("全局快捷键 ⌃⌥L", isOn: $hotkeyEnabled)
                    .onChange(of: hotkeyEnabled) { actions.setHotkey(hotkeyEnabled) }
                LabeledContent("Dock 图标 / 菜单栏图标", value: "点击即可打开")
                    .foregroundStyle(.secondary)
            }

            Section("通用") {
                Toggle("开机启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { actions.setLogin(launchAtLogin) }
                HStack {
                    Button("导入旧版启动台分组") {
                        let n = actions.importLegacy()
                        importResult = n >= 0 ? "已导入 \(n) 个项目" : "未找到旧版启动台数据"
                    }
                    if let importResult {
                        Text(importResult).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent("Relaunch", value: "1.0")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 430)
        .onAppear { launchAtLogin = actions.isLogin() }
    }
}
