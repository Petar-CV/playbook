#!/usr/bin/env bash
# Tests for scripts/plan-tasks: the single plan parser every other SDD script
# consumes. Five drifting copies of this parse is the failure it prevents.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SDD_SCRIPTS="$REPO_ROOT/skills/subagent-driven-development/scripts"
FIXTURE="$SCRIPT_DIR/fixtures/sample-plan.md"

FAILURES=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

field() { # field N COL  -> column COL of the record for task N
    awk -F'\t' -v n="$1" -v c="$2" '$1==n{print $c}' "$OUT"
}

main() {
    echo "=== Test: plan-tasks ==="
    OUT="$(mktemp)"
    trap 'rm -f "$OUT"' EXIT

    local rc=0
    "$SDD_SCRIPTS/plan-tasks" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 2 ]] && pass "no args exits 2" || fail "no args exits 2"

    rc=0
    "$SDD_SCRIPTS/plan-tasks" /nope.md >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 2 ]] && pass "missing plan exits 2" || fail "missing plan exits 2"

    "$SDD_SCRIPTS/plan-tasks" "$FIXTURE" > "$OUT"

    [[ "$(wc -l < "$OUT" | tr -d ' ')" == "5" ]] \
        && pass "emits one record per task" || fail "emits one record per task"

    [[ "$(field 1 2)" == "none" ]] && pass "task 1 deps=none" || fail "task 1 deps=none"
    [[ "$(field 2 2)" == "1" ]] && pass "task 2 deps=1" || fail "task 2 deps=1"
    [[ "$(field 5 2)" == "2" ]] && pass "task 5 deps=2" || fail "task 5 deps=2"

    [[ "$(field 1 3)" == "src/db.py,tests/test_db.py" ]] \
        && pass "task 1 files parsed in order" || fail "task 1 files parsed in order"

    # Modify: entries carry a :LINE-RANGE suffix that must be stripped.
    [[ "$(field 4 3)" == "src/db.py" ]] \
        && pass "line-range suffix stripped from Modify paths" \
        || fail "line-range suffix stripped from Modify paths"

    [[ "$(field 2 4)" == "test-port:5432" ]] \
        && pass "task 2 exclusive parsed" || fail "task 2 exclusive parsed"
    [[ "$(field 4 4)" == "test-port:5432,package-lock.json" ]] \
        && pass "task 4 exclusive list parsed" || fail "task 4 exclusive list parsed"

    # Produces must yield bare symbols, not full signatures.
    [[ "$(field 2 5)" == "getUser,UserSchema" ]] \
        && pass "produces reduced to symbols" || fail "produces reduced to symbols"
    # Consumes must never leak into produces.
    [[ "$(field 5 5)" == "ProfilePage" ]] \
        && pass "consumes excluded from produces" || fail "consumes excluded from produces"
    # Step content sits below the Interfaces block; its backticked commands
    # must not be mistaken for interface symbols.
    [[ "$(field 3 5)" == "SettingsPage" ]] \
        && pass "step content excluded from produces" || fail "step content excluded from produces"

    # A task missing the new fields must be reported as MISSING, not none.
    local bad; bad="$(mktemp)"
    cat > "$bad" <<'FIXPLAN'
### Task 1: Incomplete

**Files:**
- Create: `a.py`
FIXPLAN
    "$SDD_SCRIPTS/plan-tasks" "$bad" > "$OUT"
    [[ "$(field 1 2)" == "MISSING" && "$(field 1 4)" == "MISSING" ]] \
        && pass "absent fields emit MISSING" || fail "absent fields emit MISSING"
    rm -f "$bad"

    echo ""
    if [[ "$FAILURES" -eq 0 ]]; then echo "All plan-tasks tests passed"; else
        echo "$FAILURES failure(s)"; exit 1; fi
}
main "$@"
