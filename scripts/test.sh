#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/tests
xcrun swiftc secry/SecretParser.swift Tests/ParserTests.swift -o .build/tests/parser-tests
.build/tests/parser-tests
# Isolate the integration vault and socket from the running app and real secrets.
python3 - <<'PY'
from pathlib import Path
root = Path('.build/tests')
for name in ['Vault.swift', 'LocalBridge.swift']:
    source = (Path('secry') / name).read_text()
    source = source.replace('dev.secry.vault.v1', 'dev.secry.integration-test.v1')
    source = source.replace('/.local/share/secry', '/.local/share/secry-integration-test')
    (root / name).write_text(source)
PY
xcrun swiftc -parse-as-library secry/SecretParser.swift .build/tests/Vault.swift .build/tests/LocalBridge.swift Tests/IntegrationTests.swift -o .build/tests/integration-tests
.build/tests/integration-tests
rm -f "$HOME/.local/share/secry-integration-test/bridge.sock" "$HOME/.local/share/secry-integration-test/bridge.lock"
rmdir "$HOME/.local/share/secry-integration-test"
