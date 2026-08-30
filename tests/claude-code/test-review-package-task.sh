#!/usr/bin/env bash
# Tests for review-package's task-scoped working-tree mode. Nothing is committed
# under the new workflow, so per-task diffs come from the working tree scoped to
# the task's declared files -- correct only because collision edges guarantee no
# other uncommitted task shares those paths.
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
    echo "=== Test: review-package --task ==="
    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT

    git init -q -b main "$TEST_ROOT/repo"
    local repo; repo="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"
    cd "$repo"
    git config user.email t@t.t; git config user.name t

    echo "base" > mine.txt
    echo "base" > theirs.txt
    cat > plan.md <<'FIXPLAN'
### Task 1: Mine

**Depends on:** none
**Files:**
- Modify: `mine.txt`
- Create: `brand-new.txt`
**Exclusive:** none
**Interfaces:**
- Consumes: nothing
- Produces:
  - `mine`
FIXPLAN
    git add -A && git commit -q -m init

    echo "my change" > mine.txt
    echo "created by me" > brand-new.txt
    echo "another agent mid-edit" > theirs.txt

    local out; out="$("$SDD_SCRIPTS/review-package" plan.md --task 1)"
    local pkg; pkg="$(echo "$out" | sed -n 's/^wrote \([^:]*\):.*/\1/p')"
    [[ -f "$pkg" ]] && pass "package file written" || fail "package file written"

    grep -q "my change" "$pkg" && pass "includes tracked modifications" || fail "includes tracked modifications"
    grep -q "created by me" "$pkg" && pass "includes untracked new files" || fail "includes untracked new files"
    if grep -q "another agent mid-edit" "$pkg"; then
        fail "must exclude a concurrent agent's files"
    else
        pass "excludes a concurrent agent's files"
    fi

    # --since-park must yield only the fix delta, not the whole task.
    "$SDD_SCRIPTS/park-task" plan.md 1 >/dev/null
    echo "my change plus the fix" > mine.txt
    "$SDD_SCRIPTS/park-task" plan.md 1 >/dev/null
    out="$("$SDD_SCRIPTS/review-package" plan.md --task 1 --since-park)"
    pkg="$(echo "$out" | sed -n 's/^wrote \([^:]*\):.*/\1/p')"
    grep -q "my change plus the fix" "$pkg" && pass "fix delta includes the fix" || fail "fix delta includes the fix"
    if grep -q "created by me" "$pkg"; then
        fail "fix delta must exclude already-reviewed content"
    else
        pass "fix delta excludes already-reviewed content"
    fi

    # The legacy commit-range mode must still work.
    git add -A && git commit -q -m second
    out="$("$SDD_SCRIPTS/review-package" plan.md HEAD~1 HEAD)"
    echo "$out" | grep -q "1 commit(s)" && pass "commit-range mode still works" || fail "commit-range mode still works"

    echo ""
    if [[ "$FAILURES" -eq 0 ]]; then echo "All review-package --task tests passed"; else
        echo "$FAILURES failure(s)"; exit 1; fi
}
main "$@"
