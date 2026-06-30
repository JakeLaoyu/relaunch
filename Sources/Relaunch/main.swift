import AppKit

// Apply the language preference before any UI loads (default: English).
let appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
if appLanguage == "system" {
    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
} else {
    UserDefaults.standard.set([appLanguage], forKey: "AppleLanguages")
}

// Entry point. The Dock/menu-bar presence (activation policy) is decided by
// AppDelegate from the user's settings.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
