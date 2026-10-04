#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
./scripts/build.sh
preview_app="$PWD/.build/Secry Preview.app"
ditto .build/Build/Products/Debug/secry.app "$preview_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.secry.preview' "$preview_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Secry Preview' "$preview_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "$preview_app/Contents/Info.plist"
codesign --force --sign - "$preview_app"
open -n "$preview_app" --args --preview
