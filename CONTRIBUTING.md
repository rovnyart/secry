# Contributing

secry is a small native macOS app. Keep changes focused and dependencies minimal.

1. Open `secry.xcodeproj` with Xcode 26 or newer.
2. Run `scripts/build.sh` and `scripts/test.sh` on macOS 14 or newer.
3. For UI changes, run `scripts/preview.sh` and check light/dark, empty and long
   lists, editing, scrolling, and deletion in the actual menu-bar popup.
4. Describe the behavior change and how you verified it in your pull request.

Use disposable fixtures only. Never include real secrets, Keychain exports,
signing certificates, or personal Xcode state. Integration tests use a separate
Keychain item and socket. A Keychain permission dialog may require interaction.

Do not add cloud sync, telemetry, or new secret-export paths without discussing
the security implications first. See [SECURITY.md](SECURITY.md).
