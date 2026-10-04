#!/bin/zsh
set -euo pipefail
: "${1:?Usage: scripts/make-cask.sh path/to/secry-0.1.0-macos-universal.zip}"
filename=${1:t}
version=${filename#secry-}
version=${version%-macos-universal.zip}
[[ "$filename" == "secry-$version-macos-universal.zip" && "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Unexpected archive name'; exit 1; }
checksum=$(shasum -a 256 "$1" | awk '{print $1}')
cat <<CASK
cask "secry" do
  version "$version"
  sha256 "$checksum"

  url "https://github.com/rovnyart/secry/releases/download/v#{version}/secry-#{version}-macos-universal.zip"
  name "secry"
  desc "Local Keychain vault with temporary secret access for developer tools"
  homepage "https://github.com/rovnyart/secry"

  depends_on macos: ">= :sonoma"

  app "secry.app"
  binary "#{appdir}/secry.app/Contents/Resources/secry-cli", target: "secry"
end
CASK
