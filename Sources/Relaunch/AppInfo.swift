import AppKit

/// A single launchable application.
struct AppInfo: Identifiable, Hashable {
    let id: String      // absolute path, used as stable identity
    let name: String
    let url: URL
    let icon: NSImage

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
