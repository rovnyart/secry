# Security

## Report a vulnerability

Use GitHub's **Security → Report a vulnerability** on this repository. Do not put
secret values or a working exploit against a real user's vault in a public issue.
Please include affected version, prerequisites, impact, and a minimal reproduction
using disposable credentials.

## Trust model

- Secret sets are persisted together in one local macOS Keychain item. There is
  no application server, account, telemetry, or cloud synchronization.
- The running app holds the loaded vault in memory. This is not protection against
  a compromised macOS account, debugger, administrator, or malicious local process.
- Access grants last 15 minutes. They are checked on each request and removed on
  edit, sleep, screen lock, session resignation, or manual revocation.
- The bridge uses an owner-only Unix socket and checks the connecting user's UID.
  A grant authorizes **any process running as that user**, not one verified agent.
- `secry list` exposes set names and variable names to the same user even while
  secret access is closed. Treat those names as metadata, not secret storage.
- `secry run` sends values through the local socket and injects them into the child
  environment. The command and its descendants can retain, print, or transmit them.
  Closing access cannot erase values already delivered to a running process.
- Explicit secret copies are cleared from the clipboard after 30 seconds only if
  it has not changed. Clipboard history tools can retain a copy.
- Deleting a set does not revoke the credential at its provider.

Signing and notarization establish distribution identity and Apple's checks;
they do not constitute an independent security audit. Development builds use
ad-hoc signatures and may prompt again for Keychain access after rebuilding.
