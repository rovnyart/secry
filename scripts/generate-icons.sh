#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

master=docs/branding/secry-icon-master.png
assets=secry/Assets.xcassets/AppIcon.appiconset
iconset=$(mktemp -d)/secry.iconset
trap 'rm -rf "${iconset:h}"' EXIT
mkdir -p "$assets" "$iconset"

for size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((size * scale))
    suffix=""
    if (( scale == 2 )); then suffix="@2x"; fi
    filename="icon_${size}x${size}${suffix}.png"
    sips -z "$pixels" "$pixels" "$master" --out "$assets/$filename" >/dev/null
    cp "$assets/$filename" "$iconset/$filename"
  done
done
iconutil -c icns "$iconset" -o docs/branding/secry.icns
