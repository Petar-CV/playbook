#!/usr/bin/env bash
# Tests for scripts/stage-task. Exactly one stage in the index at a time is what
# makes `git diff --staged` a clean review surface for the human partner.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SDD_SCRIPTS="$REPO_ROOT/skills/subagent-driven-development/scripts"

FAILURES=0
TEST_ROOT=""
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }
cleanup() { [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]] && rm -rf "$TEST_ROOT"; }

main() {
    echo "=== Test: stage-task ==="
    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT

    git init -q -b main "$TEST_ROOT/repo"
    local repo; repo="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"
    cd "$repo"
    git config user.email t@t.t; git config user.name t

    echo "a" > mine.txt
    echo "b" > theirs.txt
    cat > plan.md <<'FIXPLAN'
### Task 1: Mine

**Depends on:** none
**Files:**
- Modify: `mine.txt`
**Exclusive:** none
**Interfaces:**
- Consumes: nothing
- Produces:
  - `mine`

### Task 2: Ghost

**Depends on:** none
**Files:**
- Create: `never-written.txt`
**Exclusive:** none
**Interfaces:**
- Consumes: nothing
- Produces:
  - `ghost`
FIXPLAN
    git add -A && git commit -q -m init

    # Two agents have edited the shared tree; only task 1's file may be staged.
    echo "mine changed" > mine.txt
    echo "theirs changed" > theirs.txt

    "$SDD_SCRIPTS/stage-task" plan.md 1 > /dev/null
    [[ "$(git diff --cached --name-only)" == "mine.txt" ]] \
        && pass "stages exactly the declared file list" \
        || fail "stages exactly the declared file list (got '$(git diff --cached --name-only | tr '\n' ' ')')"

    # A second stage must not join the first in the index.
    local rc=0
    "$SDD_SCRIPTS/stage-task" plan.md 2 >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 4 ]] && pass "refuses a dirty index (exit 4)" || fail "refuses a dirty index (exit 4)"

    git restore --staged mine.txt

    # A declared path the implementer never wrote is a plan/implementation
    # mismatch and must be loud, not silently skipped.
    rc=0
    "$SDD_SCRIPTS/stage-task" plan.md 2 >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 5 ]] && pass "missing declared path exits 5" || fail "missing declared path exits 5 (got $rc)"

    rc=0
    "$SDD_SCRIPTS/stage-task" plan.md >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 2 ]] && pass "wrong arg count exits 2" || fail "wrong arg count exits 2"

    echo ""
    if [[ "$FAILURES" -eq 0 ]]; then echo "All stage-task tests passed"; else
        echo "$FAILURES failure(s)"; exit 1; fi
}
main "$@"
