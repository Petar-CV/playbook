#!/usr/bin/env bash
# Tests for Native execution: scripts/task-done records a task only when its
# tests pass and snapshots it instead of committing, and the skill text keeps
# the no-commit, one-stage-at-the-end contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EP_SCRIPTS="$REPO_ROOT/skills/executing-plans/scripts"
SKILL="$REPO_ROOT/skills/executing-plans/SKILL.md"

FAILURES=0
TEST_ROOT=""
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }
cleanup() { [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]] && rm -rf "$TEST_ROOT"; }

skill_has() {
    if tr -s '[:space:]' ' ' < "$SKILL" | grep -Fq -- "$1"; then pass "skill: $2"; else fail "skill: $2"; fi
}
skill_lacks() {
    if tr -s '[:space:]' ' ' < "$SKILL" | grep -Fq -- "$1"; then fail "skill: $2"; else pass "skill: $2"; fi
}

main() {
    echo "=== Test: executing-plans (Native) ==="
    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT

    git init -q -b main "$TEST_ROOT/repo"
    local repo; repo="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"
    cd "$repo"
    git config user.email t@t.t; git config user.name t

    cat > plan.md <<'FIXPLAN'
### Task 1: First thing

**Depends on:** none
**Files:**
- Create: `work.txt`
**Exclusive:** none

### Task 2: Second thing

**Depends on:** 1
**Files:**
- Create: `more.txt`
**Exclusive:** none

### Task 3: Undeclared

**Depends on:** none
**Exclusive:** none

### Task 4: Silent pass

**Depends on:** none
**Files:**
- Create: `quiet.txt`
**Exclusive:** none
FIXPLAN
    git add plan.md && git commit -q -m fixture
    local head_before; head_before="$(git rev-parse HEAD)"

    local rc=0
    "$EP_SCRIPTS/task-done" plan.md 1 sh -c true >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 2 ]] && pass "task-done without -- errors with exit 2" \
        || fail "task-done without -- errors with exit 2 (got $rc)"

    echo "task one" > work.txt
    local idx_before; idx_before="$(cksum .git/index)"
    local out
    out="$("$EP_SCRIPTS/task-done" plan.md 1 -- sh -c 'echo "Ran 3 tests"; echo OK')"

    local ledger="$repo/.superpowers/sdd/plan/progress.md"
    local ref="refs/superpowers/sdd/plan/task-1"
    local expected="Task 1: complete files=work.txt ref=$ref tests: sh -c 'echo \"Ran 3 tests\"; echo OK' → OK"
    if [[ -f "$ledger" ]] && grep -qF "$expected" "$ledger"; then
        pass "passing task appends the completion line with files, ref, and result"
    else
        fail "passing task appends the completion line with files, ref, and result"
        echo "    expected: $expected"
        sed 's/^/    ledger: /' "$ledger" 2>/dev/null || true
    fi
    [[ "$(head -1 "$ledger")" == "# SDD ledger — plan: plan.md" ]] \
        && pass "ledger starts with the plan identity line" \
        || fail "ledger starts with the plan identity line"
    [[ "$(git show "$ref:work.txt" 2>/dev/null)" == "task one" ]] \
        && pass "passing task is snapshotted to its ref" \
        || fail "passing task is snapshotted to its ref"
    [[ "$(git rev-parse HEAD)" == "$head_before" ]] \
        && pass "task-done commits nothing" || fail "task-done commits nothing"
    [[ "$(cksum .git/index)" == "$idx_before" ]] \
        && pass "task-done leaves the index untouched" \
        || fail "task-done leaves the index untouched"
    [[ "$out" == *"OK"* ]] && pass "task-done prints the test output tail" \
        || fail "task-done prints the test output tail"
    [[ -s "$repo/.superpowers/sdd/plan/task-1-tests.log" ]] \
        && pass "task-done keeps the full test output in the workspace" \
        || fail "task-done keeps the full test output in the workspace"

    echo "task two" > more.txt
    rc=0
    out="$("$EP_SCRIPTS/task-done" plan.md 2 -- sh -c 'echo "FAILED (errors=1)"; exit 1' 2>&1)" || rc=$?
    [[ "$rc" -ne 0 ]] && pass "failing tests exit non-zero" || fail "failing tests exit non-zero"
    grep -q "Task 2: complete" "$ledger" \
        && fail "failing task is not recorded" || pass "failing task is not recorded"
    git rev-parse --verify --quiet refs/superpowers/sdd/plan/task-2 >/dev/null \
        && fail "failing task is not snapshotted" || pass "failing task is not snapshotted"
    [[ "$out" == *"FAILED"* ]] && pass "failing output is shown" || fail "failing output is shown"

    rc=0
    "$EP_SCRIPTS/task-done" plan.md 3 -- sh -c true >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 3 ]] && pass "task with no declared files exits 3" \
        || fail "task with no declared files exits 3 (got $rc)"
    grep -q "Task 3: complete" "$ledger" \
        && fail "task with no declared files is not recorded" \
        || pass "task with no declared files is not recorded"

    echo "quiet" > quiet.txt
    rc=0
    "$EP_SCRIPTS/task-done" plan.md 4 -- true >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 0 ]] && pass "a silent passing test exits 0" \
        || fail "a silent passing test exits 0 (got $rc)"
    grep -qF "Task 4: complete files=quiet.txt ref=refs/superpowers/sdd/plan/task-4 tests: true → (no output)" "$ledger" \
        && pass "a silent passing test is recorded" \
        || fail "a silent passing test is recorded"

    skill_has 'scripts/task-done PLAN_FILE N --' "closes each task with task-done"
    skill_has 'review-package PLAN_FILE --plan' "final review reads the whole-plan working-tree package"
    skill_has 'final-suite.log' "runs the full suite once before the final review"
    skill_has 'stage-task PLAN_FILE --all' "stages the whole plan once at the end"
    skill_lacks 'task-start' "has no task-start step"
    skill_lacks "Commit as the plan's commit steps say" "never commits per task"

    echo ""
    if [[ "$FAILURES" -eq 0 ]]; then echo "All executing-plans tests passed"; else
        echo "$FAILURES failure(s)"; exit 1; fi
}
main "$@"
