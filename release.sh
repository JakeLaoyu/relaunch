#!/bin/bash
# One-command release: pick a version, build a Developer ID-signed + notarized
# Relaunch.app, package it as DMG + ZIP, and publish a GitHub release.
#
# Usage:
#   ./release.sh              # interactive version picker
#   ./release.sh 1.2.0        # explicit version
#   ./release.sh patch        # bump: patch | minor | major
#
# One-time setup (notarization credentials, stored in the keychain):
#   xcrun notarytool store-credentials relaunch-notary \
#     --apple-id <your-apple-id> --team-id K285ZWD2P5 \
#     --password <app-specific password from appleid.apple.com>
#
# Overrides: CODESIGN_IDENTITY (defaults to the first "Developer ID Application"
# identity in the keychain), NOTARY_PROFILE (defaults to "relaunch-notary").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PLIST="$ROOT/Resources/Info.plist"
APP="$ROOT/build/Relaunch.app"
DIST="$ROOT/build/dist"
NOTARY_PROFILE="${NOTARY_PROFILE:-relaunch-notary}"
PB=/usr/libexec/PlistBuddy

# ---------- Pre-flight ----------

if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
    echo "ERROR: working tree is dirty — commit or stash first (the release commits the version bump)." >&2
    exit 1
fi

SIGN_ID="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$SIGN_ID" ]; then
    echo "ERROR: no 'Developer ID Application' identity in the keychain. Set CODESIGN_IDENTITY." >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<EOF
ERROR: no notarization credentials under keychain profile "$NOTARY_PROFILE".
One-time setup (needs an app-specific password from https://account.apple.com):

  xcrun notarytool store-credentials $NOTARY_PROFILE \\
    --apple-id <your-apple-id> --team-id K285ZWD2P5 --password <app-specific-password>
EOF
    exit 1
fi

gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated (run: gh auth login)." >&2; exit 1; }

# Resolve the GitHub repo up front (handles every remote URL form) so a bad
# remote fails pre-flight, not after the release commit/tag/push.
REPO="$(cd "$ROOT" && gh repo view --json nameWithOwner -q .nameWithOwner)"
[ -n "$REPO" ] || { echo "ERROR: could not resolve the GitHub repo from origin." >&2; exit 1; }

# ---------- Pick the version ----------

CURRENT="$($PB -c 'Print :CFBundleShortVersionString' "$PLIST")"
IFS=. read -r MAJ MIN PAT <<< "$CURRENT"
MIN="${MIN:-0}"; PAT="${PAT:-0}"
PATCH_V="$MAJ.$MIN.$((PAT + 1))"
MINOR_V="$MAJ.$((MIN + 1)).0"
MAJOR_V="$((MAJ + 1)).0.0"

case "${1:-}" in
    patch) VERSION="$PATCH_V" ;;
    minor) VERSION="$MINOR_V" ;;
    major) VERSION="$MAJOR_V" ;;
    "")
        echo "Current version: $CURRENT"
        echo "  1) patch  -> $PATCH_V"
        echo "  2) minor  -> $MINOR_V"
        echo "  3) major  -> $MAJOR_V"
        echo "  4) custom"
        read -rp "Choose [1-4, default 1]: " choice
        case "${choice:-1}" in
            1) VERSION="$PATCH_V" ;;
            2) VERSION="$MINOR_V" ;;
            3) VERSION="$MAJOR_V" ;;
            4) read -rp "Version: " VERSION ;;
            *) echo "ERROR: invalid choice" >&2; exit 1 ;;
        esac
        ;;
    *) VERSION="$1" ;;
esac

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "ERROR: '$VERSION' is not a valid version (e.g. 1.2.0)." >&2; exit 1; }
if git -C "$ROOT" rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    echo "ERROR: tag v$VERSION already exists." >&2
    exit 1
fi
# ls-remote --exit-code: 0 = tag exists, 2 = no matching refs; anything else
# means origin is unreachable — abort rather than fail later at git push.
rc=0
git -C "$ROOT" ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1 || rc=$?
case $rc in
    0) echo "ERROR: tag v$VERSION already exists on origin." >&2; exit 1 ;;
    2) ;;
    *) echo "ERROR: could not query origin for tags (git ls-remote exit $rc) — check network/auth." >&2; exit 1 ;;
esac

BUILD_NUM="$(( $($PB -c 'Print :CFBundleVersion' "$PLIST") + 1 ))"
echo "==> Releasing v$VERSION (build $BUILD_NUM), signing as: $SIGN_ID"

# If anything fails before the release commit, restore the plist so the
# pre-flight clean-tree check doesn't block the next attempt.
COMMITTED=0
restore_plist() {
    if [ "$COMMITTED" -ne 1 ]; then
        echo "==> Release aborted — restoring $PLIST" >&2
        git -C "$ROOT" checkout -- "$PLIST" || true
    fi
}
trap restore_plist EXIT

$PB -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
$PB -c "Set :CFBundleVersion $BUILD_NUM" "$PLIST"

# ---------- Build, notarize, staple ----------

CODESIGN_IDENTITY="$SIGN_ID" "$ROOT/build.sh"
codesign --verify --deep --strict "$APP"
# build.sh tolerates a missing slice for local builds; a release must be universal.
lipo "$APP/Contents/MacOS/Relaunch" -verify_arch arm64 x86_64 \
    || { echo "ERROR: release binary is not universal (arm64 + x86_64)." >&2; exit 1; }

rm -rf "$DIST"; mkdir -p "$DIST"
ZIP="$DIST/Relaunch-$VERSION.zip"
DMG="$DIST/Relaunch-$VERSION.dmg"

echo "==> Notarizing (this can take a few minutes)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl -a -t exec -vv "$APP"

# Re-zip the now-stapled app, and build a drag-to-Applications DMG around it.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Creating DMG"
STAGE="$DIST/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Relaunch $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --sign "$SIGN_ID" "$DMG"

# Notarize the DMG itself too — Apple recommends notarizing the outermost
# container that users download, so Gatekeeper accepts the disk image directly.
echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# ---------- Commit, tag, publish ----------

echo "==> Committing and tagging v$VERSION"
git -C "$ROOT" add "$PLIST"
git -C "$ROOT" commit -m "Release v$VERSION"
COMMITTED=1
git -C "$ROOT" tag "v$VERSION"
# --atomic: all-or-nothing, so a rejected branch push can't leave the tag
# published on origin without the version-bump commit and GitHub release.
git -C "$ROOT" push --atomic origin HEAD "v$VERSION"

echo "==> Creating GitHub release"
# --verify-tag: abort instead of auto-creating the tag if $REPO doesn't have
# it (e.g. gh resolved a different repo than the origin we pushed to).
gh release create "v$VERSION" "$DMG" "$ZIP" \
    --repo "$REPO" \
    --verify-tag \
    --title "Relaunch v$VERSION" \
    --generate-notes

echo "==> Done: v$VERSION published"
