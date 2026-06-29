import SwiftUI

/// Observable state backing the Launchpad grid.
final class LaunchpadModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var query: String = ""

    var filtered: [AppInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = AppScanner.scan()
            DispatchQueue.main.async { self.apps = found }
        }
    }
}
