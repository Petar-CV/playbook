#!/usr/bin/env bash
# Tests for scripts/park-task and scripts/restore-task. Parked work otherwise
# has no durable identity -- it is dirty files in a shared tree -- so these
# guarantee it survives, and that parking never disturbs the index a stage
# under human review is occupying.
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
    echo "=== Test: park-task / restore-task ==="
    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT

    git init -q -b main "$TEST_ROOT/repo"
    local repo; repo="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"
    cd "$repo"
    git config user.email t@t.t; git config user.name t

    mkdir -p src
    echo "original" > src/a.txt
    echo "untouched" > src/other.txt
    cat > plan.md <<'FIXPLAN'
### Task 1: Thing

**Depends on:** none
**Files:**
- Modify: `src/a.txt`
**Exclusive:** none
**Interfaces:**
- Consumes: nothing
- Produces:
  - `thing`
FIXPLAN
    git add -A && git commit -q -m init

    echo "agent work" > src/a.txt
    echo "other agent" > src/other.txt

    local idx_before idx_after
    idx_before="$(cksum .git/index)"
    "$SDD_SCRIPTS/park-task" plan.md 1 > /dev/null
    idx_after="$(cksum .git/index)"

    [[ "$idx_before" == "$idx_after" ]] \
        && pass "parking leaves .git/index byte-identical" \
        || fail "parking leaves .git/index byte-identical"

    local ref="refs/superpowers/sdd/plan/task-1"
    git rev-parse --verify --quiet "$ref" >/dev/null \
        && pass "snapshot ref created" || fail "snapshot ref created"

    if git branch -a | grep -q "task-1"; then
        fail "snapshot ref must not appear as a branch"
    else
        pass "snapshot ref does not appear as a branch"
    fi

    # The snapshot must hold ONLY the declared file's new content; another
    # agent's concurrent edit to an undeclared file must not be captured.
    [[ "$(git show "$ref:src/a.txt")" == "agent work" ]] \
        && pass "snapshot captures the declared file" || fail "snapshot captures the declared file"
    [[ "$(git show "$ref:src/other.txt")" == "untouched" ]] \
        && pass "snapshot excludes undeclared concurrent edits" \
        || fail "snapshot excludes undeclared concurrent edits"

    # Destroy the work; restore must bring it back without touching the index.
    echo "clobbered" > src/a.txt
    idx_before="$(cksum .git/index)"
    "$SDD_SCRIPTS/restore-task" plan.md 1 > /dev/null
    idx_after="$(cksum .git/index)"
    [[ "$(cat src/a.txt)" == "agent work" ]] \
        && pass "restore recovers parked content" || fail "restore recovers parked content"
    [[ "$idx_before" == "$idx_after" ]] \
        && pass "restore leaves .git/index byte-identical" \
        || fail "restore leaves .git/index byte-identical"

    # A second park must chain onto the first so <ref>^ is the reviewed state.
    echo "fix round" > src/a.txt
    "$SDD_SCRIPTS/park-task" plan.md 1 > /dev/null
    [[ "$(git show "$ref^:src/a.txt")" == "agent work" ]] \
        && pass "second park chains onto the first" || fail "second park chains onto the first"

    # restore must refuse while the path is staged for human review.
    git add src/a.txt
    local rc=0
    "$SDD_SCRIPTS/restore-task" plan.md 1 >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 4 ]] && pass "restore refuses a staged path (exit 4)" || fail "restore refuses a staged path (exit 4)"
    git restore --staged src/a.txt

    # Snapshots live in .git and must survive a working-tree wipe.
    git clean -fdxq
    git rev-parse --verify --quiet "$ref" >/dev/null \
        && pass "snapshot survives git clean -fdx" || fail "snapshot survives git clean -fdx"

    echo ""
    if [[ "$FAILURES" -eq 0 ]]; then echo "All park/restore tests passed"; else
        echo "$FAILURES failure(s)"; exit 1; fi
}
main "$@"
