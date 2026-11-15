#!/bin/zsh
# Builds build/Jot.app, signed with your Apple Development identity when there is one (a stable signature keeps the
# Microphone and Accessibility grants across rebuilds). --install copies it to /Applications and opens it.
set -euo pipefail
cd "$(dirname "$0")"

# Optional, gitignored: BUNDLE_ID, SIGN_IDENTITY and PREVIOUS_BUNDLE_ID (settings are copied once from it), see config.example.env.
BUNDLE_ID=app.newitools.Jot
SIGN_IDENTITY=""
PREVIOUS_BUNDLE_ID=""
[[ -f config.local.env ]] && source ./config.local.env

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

IDENTITY=$SIGN_IDENTITY
[[ -n "$IDENTITY" ]] || IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')
if [[ "${JOT_ADHOC:-0}" == "1" || -z "$IDENTITY" ]]; then
    echo "==> Ad-hoc signing (Microphone and Accessibility must be granted again after each build)"
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --timestamp=none "$APP/Contents/Frameworks/llama.framework"
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
