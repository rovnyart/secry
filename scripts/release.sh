#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mode=${1:-build}
version=$(awk '/MARKETING_VERSION =/ {gsub(/;/, "", $3); print $3; exit}' secry.xcodeproj/project.pbxproj)
out="$PWD/.build/release"
archive="$out/secry-$version-macos-universal.zip"
case "$mode" in
  build|signed) ;;
  *) print -u2 'Usage: scripts/release.sh [build|signed]'; exit 1 ;;
esac
if [[ "$mode" == signed ]]; then
  : "${SECRY_SIGN_IDENTITY:?Set SECRY_SIGN_IDENTITY to your Developer ID Application identity}"
  : "${SECRY_NOTARY_PROFILE:?Set SECRY_NOTARY_PROFILE to a notarytool Keychain profile}"
fi
mkdir -p "$out"
# Use a fresh path so repeated stapling does not reuse stale filesystem metadata.
stage=$(mktemp -d "$out/staging.XXXXXX")
app="$stage/secry.app"
xcodebuild -project secry.xcodeproj -scheme secry -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath .build/release-derived \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  ENABLE_HARDENED_RUNTIME=YES MARKETING_VERSION="$version" build
ditto .build/release-derived/Build/Products/Release/secry.app "$app"
install -m 755 packaging/secry "$app/Contents/Resources/secry-cli"
architectures=$(lipo -archs "$app/Contents/MacOS/secry")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
if [[ "$mode" == build ]]; then
  codesign --force --sign - "$app"
  "$app/Contents/Resources/secry-cli" --help
  print "Local unsigned-distribution build: $app"
  exit 0
fi
codesign --force --options runtime --timestamp --sign "$SECRY_SIGN_IDENTITY" "$app"
"$app/Contents/Resources/secry-cli" --help
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dv --verbose=4 "$app" 2>&1
# Submit a temporary archive; only distribute the archive made after stapling.
ditto -c -k --keepParent "$app" "$out/notarization.zip"
xcrun notarytool submit "$out/notarization.zip" --keychain-profile "$SECRY_NOTARY_PROFILE" --wait --output-format json > "$out/notarization-result.json"
python3 - "$out/notarization-result.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization not accepted. Inspect .build/release/notarization-result.json')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$archive"
(cd "$out" && shasum -a 256 "${archive:t}" > "${archive:t}.sha256")
rm "$out/notarization.zip"
print "Verified release: $archive"
