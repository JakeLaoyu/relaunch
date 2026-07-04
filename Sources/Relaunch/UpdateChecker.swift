import AppKit

/// Checks GitHub releases for a newer version. The app is distributed as a
/// GitHub release (see release.sh), so instead of embedding an update
/// framework we compare the latest release tag against the bundle version and
/// send the user to the release page to download.
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/JakeLaoyu/relaunch/releases/latest")!
    private let releasesPage = URL(string: "https://github.com/JakeLaoyu/relaunch/releases/latest")!

    private let defaults = UserDefaults.standard
    private let autoCheckKey = "autoCheckUpdates"
    private let lastCheckKey = "lastUpdateCheckDate"
    private let lastNotifiedKey = "lastNotifiedUpdateVersion"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// User asked from Settings or the menu: always report the outcome.
    func checkManually() { check(userInitiated: true) }

    /// Launch-time check: respects the settings toggle, runs at most once a
    /// day, and only speaks up the first time it sees a given new version.
    func checkAutomatically() {
        guard defaults.bool(forKey: autoCheckKey) else { return }
        if let last = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        check(userInitiated: false)
    }

    // MARK: - Implementation

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    private func check(userInitiated: Bool) {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            // Record the attempt even on failure so a failing endpoint (e.g.
            // no release yet) doesn't defeat the daily throttle and hit
            // GitHub on every launch. Manual checks are never throttled.
            self.defaults.set(Date(), forKey: self.lastCheckKey)
            let status = (response as? HTTPURLResponse)?.statusCode
            guard let data, status == 200,
                  let release = try? JSONDecoder().decode(Release.self, from: data) else {
                if userInitiated {
                    // 404 means the network is fine — there is just no
                    // published release to compare to. Anything else (rate
                    // limit, 5xx, transport error) is a failed check.
                    DispatchQueue.main.async {
                        if status == 404 {
                            self.showNoRelease()
                        } else {
                            self.showCheckFailed()
                        }
                    }
                }
                return
            }
            let latest = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst()) : release.tag_name
            let page = URL(string: release.html_url) ?? self.releasesPage

            DispatchQueue.main.async {
                if Self.isVersion(latest, newerThan: Self.currentVersion) {
                    // Auto checks nag once per version; manual checks always show.
                    if !userInitiated,
                       self.defaults.string(forKey: self.lastNotifiedKey) == latest { return }
                    self.defaults.set(latest, forKey: self.lastNotifiedKey)
                    self.showUpdateAvailable(latest, page: page)
                } else if userInitiated {
                    self.showUpToDate()
                }
            }
        }.resume()
    }

    /// Numeric component-wise compare: "1.10" > "1.9", "1.2" == "1.2.0".
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Alerts

    private func showUpdateAvailable(_ version: String, page: URL) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("A new version of Relaunch is available", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString("Relaunch %@ is available — you have %@.", comment: ""),
            version, Self.currentVersion)
        alert.addButton(withTitle: NSLocalizedString("Download", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(page)
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("You're up to date", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString("Relaunch %@ is the latest version.", comment: ""),
            Self.currentVersion)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showNoRelease() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Could not check for updates", comment: "")
        alert.informativeText = NSLocalizedString("No published releases were found.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showCheckFailed() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Could not check for updates", comment: "")
        alert.informativeText = NSLocalizedString("Check your network connection and try again.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
