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
    let relaunchApp: () -> Void
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
    @AppStorage("appLanguage") private var appLanguage = "system"
    @State private var launchAtLogin = false
    @State private var importResult: String?

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show icon in Dock", isOn: $showDock)
                    .onChange(of: showDock) { actions.setDock(showDock) }
                Toggle("Show icon in menu bar", isOn: $showMenuBar)
                    .onChange(of: showMenuBar) { actions.setMenuBar(showMenuBar) }
            }

            Section("Grid") {
                HStack {
                    Text("Icon size")
                    Slider(value: $iconSize, in: 48...112, step: 2)
                        .onChange(of: iconSize) { actions.reloadLayout() }
                    Text("\(Int(iconSize))").monospacedDigit().foregroundStyle(.secondary)
                }
                Stepper("Icons per row: \(columns)", value: $columns, in: 4...10)
                    .onChange(of: columns) { actions.reloadLayout() }
                Stepper("Rows per page: \(rows)", value: $rows, in: 3...8)
                    .onChange(of: rows) { actions.reloadLayout() }
            }

            Section("Paging") {
                Toggle("Reverse two-finger swipe direction", isOn: $swipeReversed)
            }

            Section("Activation") {
                Toggle("Trackpad pinch gesture", isOn: $gestureEnabled)
                    .onChange(of: gestureEnabled) { actions.setGesture(gestureEnabled) }
                Toggle("Global shortcut ⌃⌥L", isOn: $hotkeyEnabled)
                    .onChange(of: hotkeyEnabled) { actions.setHotkey(hotkeyEnabled) }
                LabeledContent("Dock / menu-bar icon", value: "Click to open")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Picker("Language", selection: $appLanguage) {
                    Text("System").tag("system")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "中文").tag("zh-Hans")
                }
                .onChange(of: appLanguage) { actions.relaunchApp() }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { actions.setLogin(launchAtLogin) }
                HStack {
                    Button("Import classic Launchpad layout") {
                        let n = actions.importLegacy()
                        importResult = n >= 0 ? String(localized: "Imported \(n) items")
                                              : String(localized: "No classic Launchpad data found")
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
