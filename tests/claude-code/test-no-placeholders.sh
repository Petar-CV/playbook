#!/usr/bin/env bash
# A TODO-PARTNER marker asks the human partner to write a line. One left in a
# skill ships verbatim to every agent that loads it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing skills carry no unfilled placeholders..."

hits=$(grep -rn "TODO-PARTNER" "$REPO_ROOT/skills" || true)
if [ -z "$hits" ]; then
    echo "  [PASS] no TODO-PARTNER markers in skills"
    echo ""
    echo "All placeholder checks passed."
    exit 0
fi

echo "  [FAIL] TODO-PARTNER markers in skills"
echo "$hits" | sed 's/^/    /'
exit 1
