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
    let reloadLayout: () -> Void
}

struct SettingsView: View {
    let actions: SettingsActions

    @AppStorage("showDock") private var showDock = true
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("gestureEnabled") private var gestureEnabled = true
    @AppStorage("hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("iconSize") private var iconSize = 74.0
    @AppStorage("columns") private var columns = 7
    @AppStorage("rows") private var rows = 5
    @AppStorage("swipeReversed") private var swipeReversed = false
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

            Section("网格") {
                HStack {
                    Text("图标大小")
                    Slider(value: $iconSize, in: 48...112, step: 2)
                        .onChange(of: iconSize) { actions.reloadLayout() }
                    Text("\(Int(iconSize))").monospacedDigit().foregroundStyle(.secondary)
                }
                Stepper("每行图标数：\(columns)", value: $columns, in: 4...10)
                    .onChange(of: columns) { actions.reloadLayout() }
                Stepper("每页行数：\(rows)", value: $rows, in: 3...8)
                    .onChange(of: rows) { actions.reloadLayout() }
            }

            Section("翻页") {
                Toggle("反转双指滑动方向", isOn: $swipeReversed)
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
