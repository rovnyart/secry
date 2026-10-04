#!/bin/zsh
# Run from a clean, already-pushed source checkout with a clean tap checkout.
set -euo pipefail
cd "${0:A:h}/.."
: "${1:?Usage: scripts/publish.sh RELEASE_NOTES_FILE TAP_CHECKOUT}"
: "${2:?Provide the rovnyart/homebrew-secry checkout path}"
notes=${1:A}
tap=${2:A}
[[ -f "$notes" && -d "$tap/.git" ]] || { print -u2 'Missing notes file or tap checkout'; exit 1; }
[[ -z "$(git status --porcelain)" && -z "$(git -C "$tap" status --porcelain)" ]] || { print -u2 'Both checkouts must be clean'; exit 1; }
[[ "$(git branch --show-current)" == main && "$(git -C "$tap" branch --show-current)" == main ]] || { print -u2 'Run from main in both checkouts'; exit 1; }
git fetch origin main
git -C "$tap" pull --ff-only
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { print -u2 'Push source changes before publishing'; exit 1; }
version=$(awk '/MARKETING_VERSION =/ {gsub(/;/, "", $3); print $3; exit}' secry.xcodeproj/project.pbxproj)
if gh release view "v$version" --repo rovnyart/secry >/dev/null 2>&1; then
  print -u2 "Release v$version already exists; bump MARKETING_VERSION first."
  exit 1
fi
scripts/test.sh
scripts/release.sh signed
archive=".build/release/secry-$version-macos-universal.zip"
gh release create "v$version" "$archive" "$archive.sha256" --repo rovnyart/secry \
  --target "$(git rev-parse HEAD)" --title "secry $version" --notes-file "$notes"
scripts/make-cask.sh "$archive" > "$tap/Casks/secry.rb"
git -C "$tap" add Casks/secry.rb
git -C "$tap" commit -m "Update secry to $version"
git -C "$tap" push
print "Published secry $version and updated rovnyart/secry."
