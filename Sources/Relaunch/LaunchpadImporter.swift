import Foundation
import SQLite3

/// Imports page order and folders from the legacy macOS Launchpad database
/// (managed by the Dock at `<DARWIN_USER_DIR>com.apple.dock.launchpad/db/db`).
/// Apps are matched to currently-installed ones by bundle identifier.
enum LaunchpadImporter {

    static func databaseExists() -> Bool { dbPath() != nil }

    static func dbPath() -> String? {
        var buf = [CChar](repeating: 0, count: 1024)
        let n = confstr(_CS_DARWIN_USER_DIR, &buf, buf.count)
        var dir: String?
        if n > 0 { dir = String(cString: buf) }
        if dir == nil {
            // Fallback: NSTemporaryDirectory() is <DARWIN_USER_DIR>/T/.
            dir = (NSTemporaryDirectory() as NSString).deletingLastPathComponent + "/"
        }
        guard let base = dir else { return nil }
        let path = base + "com.apple.dock.launchpad/db/db"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Returns top-level items in their original order, or nil if there is no
    /// usable legacy database.
    static func importLayout(bundleIDToPath: [String: String]) -> [LaunchItem]? {
        guard let path = dbPath() else { return nil }

        // The database is in WAL mode; opening it plain read-only makes SQLite
        // try to set up a -shm file and silently return no rows. Opening with
        // immutable=1 reads the (checkpointed) file directly, bypassing WAL and
        // locking.
        var db: OpaquePointer?
        let uri = "file:" + path + "?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        defer { sqlite3_close(db) }

        // bundle id per app item
        var appBundle: [Int64: String] = [:]
        query(db, "SELECT item_id, bundleid FROM apps") { st in
            let id = sqlite3_column_int64(st, 0)
            if let c = sqlite3_column_text(st, 1) { appBundle[id] = String(cString: c) }
        }

        // folder name per group item
        var folderName: [Int64: String] = [:]
        query(db, "SELECT item_id, title FROM groups WHERE title IS NOT NULL AND title <> ''") { st in
            let id = sqlite3_column_int64(st, 0)
            if let c = sqlite3_column_text(st, 1) { folderName[id] = String(cString: c) }
        }

        // item tree
        struct Row { var type: Int; var ordering: Int }
        var rows: [Int64: Row] = [:]
        var childrenOf: [Int64: [Int64]] = [:]
        query(db, "SELECT rowid, type, parent_id, ordering FROM items") { st in
            let rid = sqlite3_column_int64(st, 0)
            let type = Int(sqlite3_column_int(st, 1))
            let parent = sqlite3_column_int64(st, 2)
            let ordering = Int(sqlite3_column_int(st, 3))
            rows[rid] = Row(type: type, ordering: ordering)
            childrenOf[parent, default: []].append(rid)
        }
        guard !rows.isEmpty else { return nil }

        func sortedChildren(_ id: Int64) -> [Int64] {
            (childrenOf[id] ?? []).sorted { (rows[$0]?.ordering ?? 0) < (rows[$1]?.ordering ?? 0) }
        }
        func appCount(under id: Int64) -> Int {
            var n = 0
            for c in childrenOf[id] ?? [] {
                if rows[c]?.type == 4 { n += 1 } else { n += appCount(under: c) }
            }
            return n
        }

        // Types: 1 root, 2 folder/group, 3 page, 4 app.
        let roots = rows.filter { $0.value.type == 1 }.map { $0.key }
        guard let mainRoot = roots.max(by: { appCount(under: $0) < appCount(under: $1) }) else {
            return nil
        }

        var result: [LaunchItem] = []
        for page in sortedChildren(mainRoot) where rows[page]?.type == 3 {
            for child in sortedChildren(page) {
                guard let row = rows[child] else { continue }
                if row.type == 4 {
                    if let b = appBundle[child], let p = bundleIDToPath[b] {
                        result.append(.app(p))
                    }
                } else if row.type == 2 {
                    var paths: [String] = []
                    for fpage in sortedChildren(child) where rows[fpage]?.type == 3 {
                        for fapp in sortedChildren(fpage) where rows[fapp]?.type == 4 {
                            if let b = appBundle[fapp], let p = bundleIDToPath[b] { paths.append(p) }
                        }
                    }
                    let name = folderName[child] ?? "文件夹"
                    if paths.count >= 2 {
                        result.append(.folder(Folder(id: "lp-\(child)", name: name, appPaths: paths)))
                    } else if let only = paths.first {
                        result.append(.app(only))
                    }
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func query(_ db: OpaquePointer?, _ sql: String,
                              _ handle: (OpaquePointer?) -> Void) {
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW { handle(st) }
        }
        sqlite3_finalize(st)
    }
}
