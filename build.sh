#!/bin/zsh
# Builds build/Jot.app, signed with your Apple Development identity when there is one (a stable signature keeps the
# Microphone and Accessibility grants across rebuilds). --install copies it to /Applications and opens it.
# --release ignores config.local.env and signs with Developer ID (hardened runtime + secure timestamp) for
# notarization: see ../Kit/tools/release-app.sh.
set -euo pipefail
cd "$(dirname "$0")"

# Optional, gitignored: BUNDLE_ID, SIGN_IDENTITY and PREVIOUS_BUNDLE_ID (settings are copied once from it), see config.example.env.
BUNDLE_ID=app.newitools.Jot
SIGN_IDENTITY=""
PREVIOUS_BUNDLE_ID=""
RELEASE=0; [[ "${1:-}" == "--release" ]] && RELEASE=1
# A public release never reads the local file: no previous id or personal settings in the shipped app.
[[ "$RELEASE" == 0 && -f config.local.env ]] && source ./config.local.env

swift build -c release
APP="build/Jot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Jot "$APP/Contents/MacOS/Jot"
# llama.cpp (the cleanup model's runtime) is a framework: it goes in Contents/Frameworks, found through this rpath.
mkdir -p "$APP/Contents/Frameworks"
ditto .build/release/llama.framework "$APP/Contents/Frameworks/llama.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Jot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
[[ -z "$PREVIOUS_BUNDLE_ID" ]] || /usr/libexec/PlistBuddy -c "Add :JotPreviousBundleID string $PREVIOUS_BUNDLE_ID" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"   # drawn once with Kit's tools/icon-tile.swift (338cfa, waveform)
for resource in .build/release/*.bundle(N); do cp -R "$resource" "$APP/Contents/Resources/"; done

KIT=../Kit; [[ -d "$KIT" ]] || KIT=.build/checkouts/mac-tools-kit
IDENTITY=$SIGN_IDENTITY
if [[ "$RELEASE" == 1 ]]; then
    [[ -n "$IDENTITY" ]] || IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
    [[ -n "$IDENTITY" ]] || { echo "No Developer ID Application identity in the keychain" >&2; exit 1; }
    echo "==> Signing for release with $IDENTITY"
    # Every nested binary gets the hardened runtime too; same team, so library validation loads llama and Sparkle.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/llama.framework"
    "$KIT/tools/embed-sparkle.sh" "$APP" "$IDENTITY" --release
    # audio-input: the hardened runtime blocks the microphone without it (call capture and Accessibility need none).
    codesign --force --options runtime --timestamp --entitlements Resources/Jot.entitlements --sign "$IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    echo "Built $APP (release)"; exit 0
fi
[[ -n "$IDENTITY" ]] || IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')
if [[ "${JOT_ADHOC:-0}" == "1" || -z "$IDENTITY" ]]; then
    echo "==> Ad-hoc signing (Microphone and Accessibility must be granted again after each build)"
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --timestamp=none "$APP/Contents/Frameworks/llama.framework"
# Sparkle (updates): embedded and its helpers signed inside-out before the app, see Kit's docs/updates.md.
"$KIT/tools/embed-sparkle.sh" "$APP" "$IDENTITY"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"

if [[ "${1:-}" == "--install" ]]; then
    if pgrep -x Jot >/dev/null; then
        echo 'Quit Jot normally before installing so an active recording is never interrupted.' >&2
        exit 1
    fi
    ditto "$APP" /Applications/Jot.app
    open /Applications/Jot.app
    echo 'Installed and launched /Applications/Jot.app'
else
    echo "Built $APP"
fi
