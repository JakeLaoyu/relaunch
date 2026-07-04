# CLAUDE.md

Guidance for working in this repository.

**Start with [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** — it has the build /
test loop, release process, architecture map, and the subsystem gotchas
(private multitouch framework, WAL-mode legacy db, overlay window). Everything
there applies; this file only adds agent-specific notes.

## Quick facts

- Build: `./build.sh` (no Xcode project; `Package.swift` is IDE-only and does
  not produce a runnable `.app`).
- Test loop: build, `pkill -x Relaunch`, copy to `/Applications`, `open` it.
- Release: `./release.sh` (see the development guide before running it).

## Verifying changes

**Screenshot caveat depends on activation policy.** When the Dock icon is
enabled (the default `.regular` policy), the app IS in the computer-use
allowlist and the overlay/Settings windows CAN be screenshotted — install it,
`request_access(["Relaunch"])`, then `open_application("Relaunch")` triggers the
reopen handler and shows the Launchpad. When the user switches to `.accessory`
(Dock off, menu-bar only), it drops out of the allowlist and cannot be
screenshotted. For logic that must be verified regardless:
- Verify non-UI logic directly with a standalone `swift` script (this is how the
  app scanner, the `MultitouchSupport` load, and the legacy importer were
  confirmed). Standalone scripts using SQLite must be compiled with `swiftc
  -lsqlite3` — the `swift` interpreter does not autolink it.
- For the trackpad gesture, `Tools/mtdiag.swift` prints live finger count + spread
  so thresholds can be tuned against real hardware (`swift Tools/mtdiag.swift`).
- Visual behavior (drag/drop, folder overlay, layout) must be verified by the user.

## Repo conventions

- Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, …).
- After pushing fixes for Codex review comments on a PR, comment `@codex review`
  on the PR to trigger a re-review of the new commits.
- The build is ad-hoc signed by default; export
  `CODESIGN_IDENTITY="Developer ID Application: … (TEAMID)"` for a real identity.
