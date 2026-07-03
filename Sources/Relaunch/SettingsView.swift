import SwiftUI

/// Actions the settings UI invokes on the coordinator (AppDelegate).
struct SettingsActions {
    let setDock: (Bool) -> Void
    let setMenuBar: (Bool) -> Void
    let setLogin: (Bool) -> Bool   // false = registration failed, roll the toggle back
    let setGesture: (Bool) -> Void
    let setHotkey: (Bool) -> Void
    let isLogin: () -> Bool
    let importLegacy: () -> Int
    let reloadLayout: () -> Void
    let relaunchApp: () -> Void
}

struct SettingsView: View {
    // Supported languages (code, native name). Shown sorted by name.
    static let languages: [(code: String, name: String)] = [
        ("de", "Deutsch"), ("en", "English"), ("es", "Español"), ("fr", "Français"),
        ("ja", "日本語"), ("ko", "한국어"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
    ]

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
                LabeledContent("Dock / menu-bar icon") {
                    Text("Click to open").foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Picker("Language", selection: $appLanguage) {
                    Text("System").tag("system")
                    // Languages sorted alphabetically by their own name.
                    ForEach(Self.languages.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }, id: \.code) { lang in
                        Text(verbatim: lang.name).tag(lang.code)
                    }
                }
                .onChange(of: appLanguage) { actions.relaunchApp() }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        // Roll back to the real registration state on failure,
                        // like the hotkey toggle does.
                        if !actions.setLogin(launchAtLogin) { launchAtLogin = actions.isLogin() }
                    }
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
                Button("Restore Defaults", role: .destructive) { restoreDefaults() }
                LabeledContent("Relaunch", value: "1.0")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 620)
        .onAppear { launchAtLogin = actions.isLogin() }
    }

    private func restoreDefaults() {
        showDock = true
        showMenuBar = true
        gestureEnabled = true
        hotkeyEnabled = true
        iconSize = 74
        columns = 7
        rows = 5
        swipeReversed = false
        // Re-apply (covers values that were already at default, where the
        // @AppStorage onChange wouldn't fire).
        actions.setDock(true)
        actions.setMenuBar(true)
        actions.setGesture(true)
        actions.setHotkey(true)
        actions.reloadLayout()
        _ = actions.setLogin(false)   // launch-at-login is opt-in; default is off
        launchAtLogin = false
        appLanguage = "system"   // relaunches only if the language actually changed
    }
}
