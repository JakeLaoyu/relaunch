import AppKit

/// Discovers installed applications by walking the standard application folders.
enum AppScanner {
    static func scan() -> [AppInfo] {
        let fm = FileManager.default
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
        roots.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))

        var seen = Set<String>()      // dedupe by bundle file name
        var result: [AppInfo] = []
        for root in roots {
            collect(root, into: &result, seen: &seen, depth: 0)
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func collect(_ dir: URL, into result: inout [AppInfo],
                                seen: inout Set<String>, depth: Int) {
        guard depth <= 4 else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in items {
            if url.pathExtension == "app" {
                let key = url.lastPathComponent
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                var name = fm.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 128, height: 128)
                result.append(AppInfo(id: url.path, name: name, url: url, icon: icon))
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                // Recurse into ordinary subfolders (e.g. Utilities), not into bundles.
                collect(url, into: &result, seen: &seen, depth: depth + 1)
            }
        }
    }
}
