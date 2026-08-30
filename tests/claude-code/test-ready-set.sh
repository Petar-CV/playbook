#!/usr/bin/env bash
# Tests for scripts/ready-set: the DAG scheduler. A wrong answer here means two
# agents editing one file, which is silent data loss rather than a visible
# error, so every edge type gets an explicit case.
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

line() { # line KEY  -> the value after "KEY:" in the last run's output
    awk -v k="$1:" '$1==k{$1=""; sub(/^ /,""); print}' "$OUT"
}
run() { (cd "$REPO" && "$SDD_SCRIPTS/ready-set" plan.md) > "$OUT"; }
ledger() { printf '%s\n' "$@" > "$LEDGER"; }

main() {
    echo "=== Test: ready-set ==="
    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT
    OUT="$TEST_ROOT/out"

    git init -q -b main "$TEST_ROOT/repo"
    REPO="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"
    cp "$FIXTURE" "$REPO/plan.md"
    LEDGER="$( (cd "$REPO" && "$SDD_SCRIPTS/sdd-workspace" plan.md) )/progress.md"

    # --- empty ledger: only the two root tasks are dispatchable ---
    ledger "# SDD ledger — plan: plan.md"
    run
    [[ "$(line BATON)" == "1" ]] && pass "baton starts at task 1" || fail "baton starts at task 1"
    [[ "$(line READY)" == "1 3" ]] && pass "roots 1 and 3 ready" || fail "roots 1 and 3 ready (got '$(line READY)')"
    [[ "$(line BLOCKED)" == *"2 (dep 1)"* ]] && pass "task 2 blocked on dep" || fail "task 2 blocked on dep"

    # --- task 1 review-clean: semantic dependents unblock WITHOUT a commit ---
    ledger "# SDD ledger — plan: plan.md" "Task 1: returned DONE" "Task 1: review clean"
    run
    [[ "$(line READY)" == "2 3" ]] && pass "semantic dependent runs on uncommitted work" \
        || fail "semantic dependent runs on uncommitted work (got '$(line READY)')"
    # Task 4 shares src/db.py with task 1 -> collision edge needs a COMMIT.
    [[ "$(line BLOCKED)" == *"4 (collision 1)"* ]] \
        && pass "collision edge blocks until predecessor is committed" \
        || fail "collision edge blocks until predecessor is committed (got '$(line BLOCKED)')"
    [[ "$(line PARKED)" == "1" ]] && pass "clean-but-uncommitted task is parked" || fail "clean-but-uncommitted task is parked"

    # --- task 1 committed: the collision successor unblocks ---
    ledger "# SDD ledger — plan: plan.md" "Task 1: returned DONE" "Task 1: review clean" \
           "Task 1: committed abc1234"
    run
    [[ "$(line BATON)" == "2" ]] && pass "baton advances past a committed task" || fail "baton advances past a committed task"
    [[ "$(line READY)" == "2 3 4" ]] && pass "collision successor ready after commit" \
        || fail "collision successor ready after commit (got '$(line READY)')"

    # --- mutex: tasks 2 and 4 both hold test-port:5432 ---
    ledger "# SDD ledger — plan: plan.md" "Task 1: returned DONE" "Task 1: review clean" \
           "Task 1: committed abc1234" "Task 2: dispatched (agent=x, model=y)"
    run
    [[ "$(line RUNNING)" == "2" ]] && pass "dispatched-not-returned counts as running" || fail "dispatched-not-returned counts as running"
    [[ "$(line READY)" == "3" ]] && pass "mutex peer excluded while the other runs" \
        || fail "mutex peer excluded while the other runs (got '$(line READY)')"
    [[ "$(line BLOCKED)" == *"4 (mutex 2)"* ]] && pass "mutex reason reported" || fail "mutex reason reported (got '$(line BLOCKED)')"

    # --- legacy plan without the new fields exits 3 ---
    cat > "$REPO/legacy.md" <<'FIXPLAN'
### Task 1: Old style

**Files:**
- Create: `a.py`
FIXPLAN
    local rc=0
    (cd "$REPO" && "$SDD_SCRIPTS/ready-set" legacy.md) >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 3 ]] && pass "legacy plan exits 3" || fail "legacy plan exits 3 (got $rc)"

    rc=0
    "$SDD_SCRIPTS/ready-set" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 2 ]] && pass "no args exits 2" || fail "no args exits 2"

    echo ""
    if [[ "$FAILURES" -eq 0 ]]; then echo "All ready-set tests passed"; else
        echo "$FAILURES failure(s)"; exit 1; fi
}
main "$@"
