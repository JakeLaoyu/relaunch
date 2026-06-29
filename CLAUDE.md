# CLAUDE.md

Guidance for working in this repository.

## What this is

**Relaunch** is a native macOS menu-bar app that recreates the classic
full-screen Launchpad (removed/changed in macOS 26). It's a Swift + AppKit +
SwiftUI app that runs as an `LSUIElement` accessory (no Dock icon).

Core features: paged icon grid with type-to-search, folders with drag-to-organize,
import of the user's existing (classic) Launchpad layout, and four ways to open
it — trackpad pinch, global hotkey (⌃⌥L), menu-bar icon click, launch at login.

## Build, run, test

There is **no Xcode project**. The canonical build is `./build.sh`, which uses
`swiftc` directly:

```bash
./build.sh        # -> build/Relaunch.app (universal arm64+x86_64, ad-hoc signed)
```

Standard local test loop (the app installs to `/Applications` for stable login-item
registration and so the OS indexes it):

```bash
./build.sh \
  && pkill -x Relaunch 2>/dev/null \
  && rm -rf /Applications/Relaunch.app && cp -R build/Relaunch.app /Applications/ \
  && open /Applications/Relaunch.app
```

`Package.swift` exists only for IDE support / `swift build`; it does **not**
produce a runnable `.app` bundle (no Info.plist / LSUIElement).

Build specifics that matter:
- Compiled with `-swift-version 5` (avoids Swift 6 strict-concurrency errors around
  the C callbacks).
- Targets `macos14.0` (needs `.scrollTargetBehavior(.paging)`, `onKeyPress`, etc.).
- Links `-lsqlite3` for the legacy importer and `-framework Carbon` for the hotkey.

## Verifying changes

**The full-screen overlay and the menu-bar UI cannot be screenshotted by the
assistant's computer-use tooling** — an `LSUIElement` app is excluded from the
screenshot allowlist. So:
- Verify non-UI logic directly with a standalone `swift` script (this is how the
  app scanner, the `MultitouchSupport` load, and the legacy importer were
  confirmed). Standalone scripts using SQLite must be compiled with `swiftc
  -lsqlite3` — the `swift` interpreter does not autolink it.
- For the trackpad gesture, `Tools/mtdiag.swift` prints live finger count + spread
  so thresholds can be tuned against real hardware (`swift Tools/mtdiag.swift`).
- Visual behavior (drag/drop, folder overlay, layout) must be verified by the user.

## Architecture

Entry point is plain AppKit (`main.swift` → `AppDelegate`), not the SwiftUI App
lifecycle, so we control the borderless overlay window and accessory activation.

| File | Responsibility |
|------|----------------|
| `main.swift` | Entry point; sets `.accessory` activation policy |
| `AppDelegate.swift` | Coordinator wiring window + status bar + hotkey + gesture + login |
| `AppInfo.swift` | App model (path, name, url, icon, **bundleID** for import matching) |
| `AppScanner.swift` | Walks `/Applications`, `/System/Applications`, `~/Applications` |
| `LaunchpadModel.swift` | Editable layout (apps + folders), search, drag ops, JSON persistence (`LayoutStore`) |
| `LaunchpadView.swift` | SwiftUI grid, folder cells, folder overlay, drag/drop, cross-page edge-flip |
| `LaunchpadController.swift` | Borderless key-capable overlay window (`LaunchpadWindow`), show/hide |
| `StatusBarController.swift` | Menu-bar `NSStatusItem` and its menu |
| `HotkeyManager.swift` | Carbon global hotkey (`RegisterEventHotKey`) |
| `MultitouchGesture.swift` | Trackpad pinch detection via private `MultitouchSupport` |
| `LoginItem.swift` | Launch at login via `SMAppService` |
| `LaunchpadImporter.swift` | Reads the classic Launchpad SQLite db |

## Subsystem gotchas

**Trackpad gesture** (`MultitouchGesture.swift`): the private
`MultitouchSupport.framework` is `dlopen`'d at runtime (no build-time link). The C
contact callback can't capture context, so state lives in a file-private singleton.
Each contact record is a fixed 96-byte stride; we read only the fields we need by
byte offset (pos.x @32, pos.y @36, size @48) instead of mirroring the C struct.
Detection: thumb + three fingers == 4 contacts; fire when the mean spread starts
wide (>0.20), shrinks by a clear absolute amount (>0.07), and falls below ~66% of
its widest — tuned to real data (a pinch starts ~0.30 and bottoms out ~0.17 before
a finger lifts). A four-finger *swipe* translates without converging, so it won't
fire.

**Global hotkey** (`HotkeyManager.swift`): Carbon hotkeys are system-wide and need
no Accessibility permission. `register()` checks the `OSStatus` and returns success;
`AppDelegate`/the menu only show "enabled" when registration actually succeeded.

**Legacy import** (`LaunchpadImporter.swift`): the classic Launchpad db lives at
`<DARWIN_USER_DIR>com.apple.dock.launchpad/db/db` (locate via
`confstr(_CS_DARWIN_USER_DIR)`). It is **WAL-mode**; opening it plain
`SQLITE_OPEN_READONLY` returns **zero rows silently** — open it with
`file:<path>?immutable=1` + `SQLITE_OPEN_URI`. Schema: `items.type` 1=root,
2=folder/group, 3=page, 4=app; folder names in `groups.title`; bundle ids in
`apps.bundleid`. Apps are matched to installed ones by bundle id; uninstalled ones
are skipped. Auto-imports on first run when no `layout.json` exists; otherwise via
the menu item.

**Layout persistence**: `~/Library/Application Support/Relaunch/layout.json`. On
load, missing apps are dropped and newly installed apps appended; folders with <2
apps auto-dissolve.

**Overlay window** (`LaunchpadController.swift`): borderless, `CGShieldingWindowLevel`
(covers Dock + menu bar), `.darkAqua`, dismissed on resign-key. `LaunchpadWindow`
overrides `canBecomeKey` so the search field can take focus.

## Repo conventions

- Work happens on `feat/classic-launchpad` → PR #1 (base `main`).
- App bundle id: `com.jake.relaunch`. The build is ad-hoc signed.
