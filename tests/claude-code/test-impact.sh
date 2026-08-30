#!/usr/bin/env bash
# Tests for scripts/impact. Downstream tasks consume only the declared Produces
# surface, so a fix that never touches it has provably zero fan-out -- this turns
# the common stylistic rejection into a no-op instead of a re-verification wave.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SDD_SCRIPTS="$REPO_ROOT/skills/subagent-driven-development/scripts"
FIXTURE="$SCRIPT_DIR/fixtures/sample-plan.md"

FAILURES=0
TEST_ROOT=""
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }
cleanup() { [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]] && rm -rf "$TEST_ROOT"; }

main() {
    echo "=== Test: impact ==="
    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT

    # Task 2 produces getUser and UserSchema. Task 5 depends on task 2.
    local internal="$TEST_ROOT/internal.diff"
    cat > "$internal" <<'DIFF'
@@ -10,7 +10,7 @@ def _format_error(msg):
-    return "err: " + msg
+    return "error: " + msg
DIFF

    local surface="$TEST_ROOT/surface.diff"
    cat > "$surface" <<'DIFF'
@@ -20,7 +20,7 @@ def getUser(id):
-def getUser(id: str) -> User:
+def getUser(id: str) -> User | None:
DIFF

    [[ "$("$SDD_SCRIPTS/impact" "$FIXTURE" 2 "$internal")" == "AFFECTED: none" ]] \
        && pass "internal-only fix has zero fan-out" || fail "internal-only fix has zero fan-out"

    local out; out="$("$SDD_SCRIPTS/impact" "$FIXTURE" 2 "$surface")"
    [[ "$out" == "AFFECTED: 5" ]] \
        && pass "surface change reaches its consumer" || fail "surface change reaches its consumer (got '$out')"

    # Task 1 produces connect(); tasks 2 and 4 depend on it, and task 5 depends
    # on task 2 -- the reach must be transitive.
    local conn="$TEST_ROOT/conn.diff"
    cat > "$conn" <<'DIFF'
@@ -1,4 +1,4 @@
-def connect(url: str) -> Conn:
+def connect(url: str, timeout: int) -> Conn:
DIFF
    out="$("$SDD_SCRIPTS/impact" "$FIXTURE" 1 "$conn")"
    [[ "$out" == "AFFECTED: 2 4 5" ]] \
        && pass "fan-out is transitive" || fail "fan-out is transitive (got '$out')"

    # A symbol name must match as a whole word, not as a substring.
    local substr="$TEST_ROOT/substr.diff"
    cat > "$substr" <<'DIFF'
@@ -1,3 +1,3 @@
-x = reconnected_flag
+x = reconnected_flag2
DIFF
    [[ "$("$SDD_SCRIPTS/impact" "$FIXTURE" 1 "$substr")" == "AFFECTED: none" ]] \
        && pass "substring match does not count as a hit" || fail "substring match does not count as a hit"

    local rc=0
    "$SDD_SCRIPTS/impact" "$FIXTURE" 1 >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 2 ]] && pass "wrong arg count exits 2" || fail "wrong arg count exits 2"

    echo ""
    if [[ "$FAILURES" -eq 0 ]]; then echo "All impact tests passed"; else
        echo "$FAILURES failure(s)"; exit 1; fi
}
main "$@"
