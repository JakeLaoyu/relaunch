import AppKit

// Entry point. The Dock/menu-bar presence (activation policy) is decided by
// AppDelegate from the user's settings.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
