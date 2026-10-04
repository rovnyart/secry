# Development and visual verification

## Develop

```sh
./scripts/build.sh
open .build/Build/Products/Debug/secry.app
```

Open `secry.xcodeproj` in Xcode, or build from the terminal. No dependencies.
The app lives behind the key icon in the menu bar. Left-click opens the panel.
Right-click or Control-click opens the native menu: Open secry, Close All Agent
Access, and Quit secry. The shell uses NSStatusItem + NSPopover; content is SwiftUI.

## Verification

```sh
./scripts/test.sh
./scripts/preview.sh
```

The test runner covers parsing and the actual Keychain → bridge → subprocess flow
using an isolated test Keychain item and socket. Never put real secrets in fixtures.

Visual Preview uses the **same ContentView** as the menu panel, with memory-only
fixtures. It never reads or writes your real Keychain or opens the agent bridge.
Switch between empty, one-set, and 30-set states and light/dark appearances.
The first sample has 24 variables to exercise scrolling in the detail and editor.
The preview also installs a **filled key icon in the menu bar** with two independent,
memory-only records (`delete-test` and `keep-test`). Use that icon for popup lifecycle
checks. The ordinary preview window does not reproduce transient menu-panel focus behavior.

Before delivering UI changes, inspect actual screenshots and click through:
- Empty → add → save → back to the first record.
- Long library → scroll to the final record → search and clear.
- Long secret set → scroll to final variable → reveal/hide and edit.
- Editor → multiline input, parse error, save/cancel.
- From the **menu-bar icon**, open `delete-test` → ellipsis → Delete → confirm.
  Close and reopen the popup: only `keep-test` should remain. Repeat with Cancel;
  the record must remain. A pass in the ordinary preview window is insufficient.
- Keep deletion confirmation inline. A system `.alert` can steal focus from the
  transient menu panel, causing clicks to close it instead of invoking actions.
- Both system appearances.

The menu panel has an explicit, screen-bounded height. Do not replace this with
`maxHeight` alone: a content-sized popover can measure a ScrollView at zero ideal height.

## Release signing

Local `scripts/build.sh` uses ad-hoc signing. Its designated requirement is tied to
the build hash, so macOS may ask again for access to an existing Keychain item after
rebuilding. Release builds need a stable Developer ID identity and bundle identifier;
ordinary updates should retain Keychain trust. Locked keychains, signature/channel
changes, or a development-to-release migration can still require authorization.
Notarization is part of distribution, not a way to bypass Keychain consent.
