#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="build/Jot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Jot "$APP/Contents/MacOS/Jot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ ! -f Resources/AppIcon.icns ]]; then
    swift scripts/icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for resource in .build/release/*.bundle(N); do cp -R "$resource" "$APP/Contents/Resources/"; done
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
if [[ "${JOT_ADHOC:-0}" == "1" ]]; then IDENTITY="-"; fi
codesign --force --sign "${IDENTITY:--}" --timestamp=none "$APP"
if [[ "${1:-}" == "--install" ]]; then
    if pgrep -x Jot >/dev/null; then
        echo 'Quit Jot normally before installing so an active recording is never interrupted.' >&2
        exit 1
    fi
    ditto "$APP" /Applications/Jot.app
    open /Applications/Jot.app
    echo 'Installed and launched /Applications/Jot.app'
fi
