#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcodebuild -project secry.xcodeproj -scheme secry -configuration Debug -destination 'platform=macOS' -derivedDataPath .build build CODE_SIGN_IDENTITY=-
mkdir -p .build/bin
cat > .build/bin/secry <<SCRIPT
#!/bin/sh
exec '$(pwd)/.build/Build/Products/Debug/secry.app/Contents/MacOS/secry' --cli "\$@"
SCRIPT
chmod +x .build/bin/secry
