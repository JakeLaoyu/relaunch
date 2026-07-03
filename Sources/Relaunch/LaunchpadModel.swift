import SwiftUI
import AppKit

// MARK: - Layout model

struct Folder: Identifiable, Hashable {
    let id: String
    var name: String
    var appPaths: [String]
}

/// A top-level grid entry: either a single app (by path) or a folder.
enum LaunchItem: Identifiable, Hashable {
    case app(String)        // app bundle path
    case folder(Folder)

    var id: String {
        switch self {
        case .app(let path): return "app:" + path
        case .folder(let f): return "folder:" + f.id
        }
    }

    var isFolder: Bool { if case .folder = self { return true }; return false }
}

// MARK: - Model

final class LaunchpadModel: ObservableObject {
    @Published var items: [LaunchItem] = []     // top-level, ordered
    @Published var query: String = ""
    @Published var openFolderID: String? = nil
    @Published var currentPage = 0
    var lastPageDir = 1     // +1 = moved to a later page, -1 = earlier (slide direction)

    // Configurable grid layout (persisted in UserDefaults via Settings).
    @Published var columns = 7
    @Published var rows = 5
    @Published var iconSize: CGFloat = 74

    var pageSize: Int { Swift.max(1, columns * rows) }
    var pageCount: Int { Swift.max(1, (items.count + pageSize - 1) / pageSize) }

    init() { applyLayoutSettings() }

    func applyLayoutSettings() {
        let d = UserDefaults.standard
        columns = Swift.max(4, Swift.min(d.object(forKey: "columns") as? Int ?? 7, 10))
        rows = Swift.max(3, Swift.min(d.object(forKey: "rows") as? Int ?? 5, 8))
        let size = d.object(forKey: "iconSize") != nil ? CGFloat(d.double(forKey: "iconSize")) : 74
        iconSize = Swift.max(40, Swift.min(size, 120))
        if currentPage >= pageCount { currentPage = pageCount - 1 }
    }

    func changePage(_ delta: Int) { setPage(currentPage + delta) }

    func setPage(_ page: Int) {
        let next = Swift.max(0, Swift.min(page, pageCount - 1))
        guard next != currentPage else { return }
        lastPageDir = next > currentPage ? 1 : -1
        currentPage = next
    }

    private(set) var appsByPath: [String: AppInfo] = [:]
    private var loaded = false

    // Lookups -----------------------------------------------------------------

    func app(_ path: String) -> AppInfo? { appsByPath[path] }

    func folder(_ id: String) -> Folder? {
        for case .folder(let f) in items where f.id == id { return f }
        return nil
    }

    var searchResults: [AppInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return appsByPath.values
            .filter { $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Up to 9 icons for a folder's mini preview.
    func previewIcons(_ folder: Folder) -> [AppInfo] {
        folder.appPaths.prefix(9).compactMap { appsByPath[$0] }
    }

    // Loading -----------------------------------------------------------------

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = AppScanner.scan()
            DispatchQueue.main.async {
                self.appsByPath = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let installed = Set(apps.map { $0.id })
                if !self.loaded {
                    if let saved = LayoutStore.loadFromDisk(installed: installed) {
                        self.items = saved
                        // Append any newly installed apps (sorted by name) and
                        // persist, so their order is stable across launches.
                        self.reconcile(installed: installed)
                    } else if let imported = LaunchpadImporter.importLayout(bundleIDToPath: self.bundleMap()) {
                        // First run with no saved layout: inherit the user's
                        // classic Launchpad page order and folders.
                        self.items = imported
                        self.reconcile(installed: installed)
                    } else {
                        self.items = apps.map { .app($0.id) }   // alphabetical
                        self.save()
                    }
                    self.loaded = true
                } else {
                    self.reconcile(installed: installed)
                }
            }
        }
    }

    private func bundleMap() -> [String: String] {
        var map: [String: String] = [:]
        for (path, info) in appsByPath where !info.bundleID.isEmpty { map[info.bundleID] = path }
        return map
    }

    /// Re-import page order + folders from the legacy Launchpad database,
    /// replacing the current layout. Returns the item count, or -1 if there is
    /// no legacy database to import from.
    @discardableResult
    func importFromLegacy() -> Int {
        if appsByPath.isEmpty {
            let apps = AppScanner.scan()
            appsByPath = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        // `loaded` only flips on success: a failed import must leave the next
        // reload() free to read layout.json, or reconcile() would rebuild an
        // alphabetical layout from empty items and save over the user's one.
        guard let imported = LaunchpadImporter.importLayout(bundleIDToPath: bundleMap()) else {
            return -1
        }
        items = imported
        reconcile(installed: Set(appsByPath.keys))
        loaded = true
        return items.count
    }

    /// Drop uninstalled apps and append newly installed ones.
    private func reconcile(installed: Set<String>) {
        var present = Set<String>()
        var newItems: [LaunchItem] = []
        for item in items {
            switch item {
            case .app(let p):
                if installed.contains(p) { newItems.append(.app(p)); present.insert(p) }
            case .folder(var f):
                f.appPaths = f.appPaths.filter { installed.contains($0) }
                f.appPaths.forEach { present.insert($0) }
                newItems.append(.folder(f))
            }
        }
        for p in installed.subtracting(present).sorted(by: {
            (appsByPath[$0]?.name ?? "").localizedCaseInsensitiveCompare(appsByPath[$1]?.name ?? "") == .orderedAscending
        }) {
            newItems.append(.app(p))
        }
        items = newItems
        cleanup()
        save()
    }

    // Mutations ---------------------------------------------------------------

    func renameFolder(_ id: String, _ name: String) {
        guard let i = items.firstIndex(where: { $0.id == "folder:" + id }),
              case .folder(var f) = items[i] else { return }
        f.name = name.isEmpty ? f.name : name
        items[i] = .folder(f)
        save()
    }

    func removeFromFolder(_ folderID: String, _ path: String) {
        guard let i = items.firstIndex(where: { $0.id == "folder:" + folderID }),
              case .folder(var f) = items[i] else { return }
        f.appPaths.removeAll { $0 == path }
        items[i] = .folder(f)
        // Place the app back on the grid right after its old folder.
        items.insert(.app(path), at: min(i + 1, items.count))
        cleanup()
        if folder(folderID) == nil { openFolderID = nil }   // folder dissolved
        save()
    }

    /// Move an app within a folder to an absolute index among the remaining apps.
    func moveInFolder(_ folderID: String, move path: String, toIndex index: Int) {
        guard let i = items.firstIndex(where: { $0.id == "folder:" + folderID }),
              case .folder(var f) = items[i] else { return }
        f.appPaths.removeAll { $0 == path }
        let target = Swift.max(0, Swift.min(index, f.appPaths.count))
        f.appPaths.insert(path, at: target)
        items[i] = .folder(f)
        save()
    }

    // MARK: - Live custom drag (no disk writes until commitLayout)

    /// Move an item to a new absolute index. Used continuously while dragging.
    func moveItem(id: String, toIndex index: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let target = max(0, min(index, items.count - 1))
        if from == target { return }
        let item = items.remove(at: from)
        items.insert(item, at: min(target, items.count))
    }

    /// Merge the dragged app into the target app (new folder) or folder (append).
    func makeOrJoinFolder(draggingID: String, targetID: String) {
        guard draggingID != targetID,
              let dragItem = items.first(where: { $0.id == draggingID }),
              case .app(let dragPath) = dragItem,
              let targetItem = items.first(where: { $0.id == targetID }) else {
            commitLayout(); return
        }
        items.removeAll { $0.id == draggingID }
        switch targetItem {
        case .folder(let f):
            if let i = items.firstIndex(where: { $0.id == "folder:" + f.id }),
               case .folder(var ff) = items[i] {
                if !ff.appPaths.contains(dragPath) { ff.appPaths.append(dragPath) }
                items[i] = .folder(ff)
            }
        case .app(let targetPath):
            if let i = items.firstIndex(where: { $0.id == "app:" + targetPath }) {
                items[i] = .folder(Folder(id: UUID().uuidString, name: String(localized: "Folder"),
                                          appPaths: [targetPath, dragPath]))
            }
        }
        cleanup(); save()
    }

    /// Persist the current order once a drag finishes.
    func commitLayout() { cleanup(); save() }

    /// Dissolve folders that have fallen to 0 or 1 apps.
    private func cleanup() {
        var result: [LaunchItem] = []
        for item in items {
            if case .folder(let f) = item {
                if f.appPaths.isEmpty { continue }
                if f.appPaths.count == 1 { result.append(.app(f.appPaths[0])); continue }
            }
            result.append(item)
        }
        items = result
    }

    private func save() { LayoutStore.save(items) }
}

// MARK: - Persistence

enum LayoutStore {
    private struct Entry: Codable {
        var type: String         // "app" | "folder"
        var path: String?
        var id: String?
        var name: String?
        var apps: [String]?
    }

    private static var fileURL: URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("Relaunch", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }

    /// Returns the saved layout, or nil if no layout file exists yet.
    static func loadFromDisk(installed: Set<String>) -> [LaunchItem]? {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return nil
        }
        var present = Set<String>()
        var items: [LaunchItem] = []
        for e in entries {
            if e.type == "folder", let id = e.id {
                let paths = (e.apps ?? []).filter { installed.contains($0) }
                paths.forEach { present.insert($0) }
                if paths.count >= 2 {
                    items.append(.folder(Folder(id: id, name: e.name ?? String(localized: "Folder"), appPaths: paths)))
                } else if let only = paths.first {
                    items.append(.app(only))
                }
            } else if e.type == "app", let p = e.path, installed.contains(p) {
                items.append(.app(p)); present.insert(p)
            }
        }
        // Newly installed apps are appended by the model's reconcile(), which
        // orders them by name and persists the result.
        return items
    }

    static func save(_ items: [LaunchItem]) {
        guard let url = fileURL else { return }
        let entries: [Entry] = items.map { item in
            switch item {
            case .app(let p): return Entry(type: "app", path: p, id: nil, name: nil, apps: nil)
            case .folder(let f): return Entry(type: "folder", path: nil, id: f.id, name: f.name, apps: f.appPaths)
            }
        }
        do {
            // Atomic, so a crash mid-write can't leave a truncated file that
            // the next launch would misread as "no layout" and overwrite.
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        } catch {
            // A full disk would otherwise silently discard every reorder.
            NSLog("Relaunch: failed to save layout: \(error)")
            warnSaveFailedOnce()
        }
    }

    private static var warnedSaveFailure = false
    private static func warnSaveFailedOnce() {
        guard !warnedSaveFailure else { return }
        warnedSaveFailure = true
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = NSLocalizedString("Could not save the layout", comment: "")
            alert.informativeText = NSLocalizedString(
                "Your icon layout could not be written to disk. Check the available disk space.", comment: "")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
