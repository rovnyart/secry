# Releasing secry

## One-time Apple setup

Create a **Developer ID Application** certificate in Xcode → Settings → Accounts
→ your team → Manage Certificates. Keep the private key in your login Keychain.
Verify with `security find-identity -v -p codesigning`.

Store notarization credentials interactively (do not paste credentials into chat):

```sh
xcrun notarytool store-credentials secry-notary
```

Use your Apple ID, 10-character Team ID, and an app-specific password generated at
https://account.apple.com. The tool validates and stores them in Keychain.

## Build, sign, notarize

```sh
scripts/test.sh
SECRY_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
SECRY_NOTARY_PROFILE=secry-notary scripts/release.sh signed
```

The script builds arm64 + x86_64 with Hardened Runtime, installs the relocatable
CLI wrapper before signing, verifies the signature, submits to Apple, requires
`Accepted`, staples and validates the ticket, checks Gatekeeper, then creates the
final ZIP and SHA-256 in `.build/release/`.

For local build verification without credentials: `scripts/release.sh build`.
This produces an ad-hoc app, **not a distributable notarized release**.

Before publishing, test the final downloaded archive on macOS, including the menu
bar, Keychain, grant/revoke flow and CLI. Check the minimum macOS version and both
architectures; compilation alone is not runtime verification on Intel or macOS 14.

## GitHub and Homebrew

Publish the source revision as tag `v0.1.0` and attach
`secry-0.1.0-macos-universal.zip` and its checksum to the matching GitHub Release.
Generate the tap cask using `scripts/make-cask.sh ARCHIVE` only after notarization.
The tap is `rovnyart/homebrew-secry`; its cask installs both the app and CLI.
Never publish an install command as ready before the release asset and cask exist.

For future automated releases, a macOS runner needs a temporary signing Keychain,
a Developer ID certificate/private key, and notarization credentials held in
GitHub Actions secrets. Never commit these files or credentials. Local signing
remains available without uploading a private key to CI.

## Publish a subsequent release with one command

Update `MARKETING_VERSION` in both Xcode configurations, write release notes,
commit and push the source to `main`, and wait for CI. Then:

```sh
SECRY_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
SECRY_NOTARY_PROFILE=secry-notary \
  scripts/publish.sh /path/to/release-notes.md /path/to/homebrew-secry
```

This runs local tests, builds/signs/notarizes, publishes a versioned GitHub Release,
and updates the tap checksum and version. Both repositories must start clean on
`main`. The signing key and notarization credentials remain in your Mac's Keychain.
If an external publication step fails after the release exists, complete that step
manually; the script refuses to overwrite an existing release.
