# Parallel SDD Scheduling and Manual Commit Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let subagent-driven-development dispatch independent plan stages concurrently, and replace agent self-commits with a human commit gate where exactly one stage at a time is staged for review.

**Architecture:** A shared parser (`plan-tasks`) turns the plan into a task graph; `ready-set` computes the dispatchable set from that graph plus the ledger; `park-task`/`restore-task` snapshot uncommitted stages to `refs/superpowers/sdd/…` via a private git index; `stage-task` puts exactly one stage in the index for the human. Skill prose and prompt templates carry the discipline rules that scripts cannot enforce.

**Tech Stack:** Bash 3.2+ (macOS-compatible), POSIX awk, git ≥ 2.23, existing `tests/claude-code/` bash test harness.

**Spec:** `docs/superpowers/specs/2026-08-30-parallel-sdd-commit-gate-design.md`

## Global Constraints

- Minimum git version is **2.23** (`git restore --source=<tree-ish> --worktree`). `--no-optional-locks` requires git ≥ 2.15.
- All new scripts live in `skills/subagent-driven-development/scripts/`, start with `#!/usr/bin/env bash` and `set -euo pipefail`, print usage to stderr, and exit **2** on usage error. They must be `chmod +x`.
- Bash must be macOS-compatible: **no `mapfile`, no `declare -A`, no `${var,,}`.** Use `IFS=',' read -r -a arr <<< "$s"` for splitting.
- Snapshot refs are named exactly `refs/superpowers/sdd/<plan-basename-without-.md>/task-<N>`.
- `plan-tasks` output is TSV with five fields: `N`, `deps`, `files`, `exclusive`, `produces`. Absent fields emit the literal `MISSING`; present-but-empty fields emit the literal `none`. Lists are comma-separated with no spaces.
- No script ever runs `git commit`. No script ever writes to `.git/index` except `stage-task`.
- Every diff taken against a snapshot ref MUST be path-scoped with `-- <files>`; snapshot trees are seeded from `HEAD` and an unscoped diff leaks other stages' committed work.
- Existing eval-tuned sentences in skill files **move; they do not get reworded.** New machinery is additive.
- New tests follow `tests/claude-code/test-sdd-workspace.sh` house style: `pass()`/`fail()` helpers, `FAILURES` counter, `mktemp -d` sandbox with a `trap cleanup EXIT`, and `git init -q -b main`.
- **Bootstrap note:** this plan is executed under the *current* SDD workflow, which still instructs implementers to commit. Self-commits during this plan's execution are expected and fine; the new gate only governs plans executed after Task 9 lands.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `skills/subagent-driven-development/scripts/plan-tasks` | **NEW.** Single plan parser. Emits one TSV record per task. Every other script consumes it, so the parse lives in exactly one place. |
| `skills/subagent-driven-development/scripts/ready-set` | **NEW.** The scheduler. Reads the graph and the ledger, prints baton/ready/blocked/parked/committed. |
| `skills/subagent-driven-development/scripts/park-task` | **NEW.** Snapshots a task's files to its ref via a private index. |
| `skills/subagent-driven-development/scripts/restore-task` | **NEW.** Restores a task's parked content to the worktree only. |
| `skills/subagent-driven-development/scripts/stage-task` | **NEW.** Stages exactly one task's files; refuses a dirty index. |
| `skills/subagent-driven-development/scripts/impact` | **NEW.** Computes rejection fan-out from the `Produces` surface. |
| `skills/subagent-driven-development/scripts/review-package` | **MODIFY.** Add `--task N [--since-park]` working-tree mode. |
| `skills/subagent-driven-development/implementer-prompt.md` | **MODIFY.** No-git contract, shared-tree rules, report contract. |
| `skills/subagent-driven-development/task-reviewer-prompt.md` | **MODIFY.** Task-scoped worktree diff, `Produces verified:` verdict. |
| `skills/subagent-driven-development/re-review-prompt.md` | **MODIFY.** Snapshot-ref fix base, shared-tree scoping note. |
| `skills/subagent-driven-development/SKILL.md` | **MODIFY.** Scheduler section, commit-gate section, recovery, rationalizations. |
| `skills/writing-plans/SKILL.md` | **MODIFY.** New task schema fields; remove the per-task commit step. |
| `skills/executing-plans/SKILL.md` | **MODIFY.** Sequential commit gate. |
| `skills/dispatching-parallel-agents/SKILL.md` | **MODIFY.** Cross-reference the scheduler and no-git contract. |
| `skills/finishing-a-development-branch/SKILL.md` | **MODIFY.** Refuse on parked work; delete snapshot refs. |
| `tests/claude-code/fixtures/sample-plan.md` | **NEW.** Shared fixture plan exercising every schema field. |
| `tests/claude-code/test-*.sh` | **NEW.** One test file per script. |

---

## Task 1: Plan schema and shared test fixture

**Depends on:** none
**Exclusive:** none

**Files:**
- Modify: `skills/writing-plans/SKILL.md`
- Create: `tests/claude-code/fixtures/sample-plan.md`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `sample-plan.md` — fixture plan with tasks 1–5 exercising `Depends on:`, exhaustive `Files:`, `Exclusive:` paths and mutexes, and backticked `Produces:` symbols
  - The task schema every script in Tasks 2–7 parses

- [ ] **Step 1: Create the shared test fixture**

Create `tests/claude-code/fixtures/sample-plan.md`:

````markdown
# Sample Plan

## Global Constraints

- Nothing.

---

### Task 1: Database layer

**Depends on:** none
**Files:**
- Create: `src/db.py`
- Test: `tests/test_db.py`
**Exclusive:** none
**Interfaces:**
- Consumes: nothing
- Produces:
  - `connect(url: str) -> Conn`

- [ ] **Step 1: Do it**

### Task 2: API layer

**Depends on:** Task 1
**Files:**
- Create: `src/api.py`
- Test: `tests/test_api.py`
**Exclusive:** test-port:5432
**Interfaces:**
- Consumes:
  - `connect(url: str) -> Conn`
- Produces:
  - `getUser(id: str) -> User`
  - `UserSchema`

- [ ] **Step 1: Do it**

### Task 3: Settings page

**Depends on:** none
**Files:**
- Create: `web/settings.tsx`
**Exclusive:** none
**Interfaces:**
- Consumes: nothing
- Produces:
  - `SettingsPage`

- [ ] **Step 1: Do it**

Run: `npm test` — a backticked token below a step heading, which must NOT be
captured as a produced symbol.

### Task 4: Migrations

**Depends on:** Task 1
**Files:**
- Modify: `src/db.py:10-40`
**Exclusive:** test-port:5432, package-lock.json
**Interfaces:**
- Consumes:
  - `connect(url: str) -> Conn`
- Produces:
  - `migrate() -> None`

- [ ] **Step 1: Do it**

### Task 5: Profile page

**Depends on:** Task 2
**Files:**
- Create: `web/profile.tsx`
**Exclusive:** none
**Interfaces:**
- Consumes:
  - `getUser(id: str) -> User`
- Produces:
  - `ProfilePage`

- [ ] **Step 1: Do it**
````

Note the deliberate properties: Task 4 shares `src/db.py` with Task 1 (a **file-collision edge**), Tasks 2 and 4 share `test-port:5432` (a **mutex edge**), Task 4's `package-lock.json` is a path-shaped `Exclusive:` entry (a **collision** entry, not a mutex), and Tasks 1 and 3 are both root tasks.

- [ ] **Step 2: Verify the fixture parses as intended by hand**

Run: `grep -c 'Depends on:' tests/claude-code/fixtures/sample-plan.md`
Expected: `5`

- [ ] **Step 3: Add the two new fields to the writing-plans task template**

In `skills/writing-plans/SKILL.md`, in the `## Task Structure` section, replace:

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on — exact function names, parameter
  and return types. A task's implementer sees only their own task; this
  block is how they learn the names and types neighboring tasks use.]
````

with:

````markdown
### Task N: [Component Name]

**Depends on:** [comma-separated task numbers whose Produces this task
Consumes, or the literal `none`. Mandatory — silence is a plan defect, not an
implied `none`. Semantic dependency only; shared files are derived from the
Files block.]

**Exclusive:** [shared resources this task contends for that are not in its own
edit set — regenerated lockfiles, migration sequence numbers, fixed ports,
shared test databases, codegen outputs — or the literal `none`. Syntax decides
the edge: an entry containing `/` or a file extension is a path and serializes
on a commit; an entry of the form `<kind>:<name>` (e.g. `test-port:5432`) is a
mutex and merely excludes concurrent runs.]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

This list must be **exhaustive** — every file the task creates, modifies, or
deletes. The executor schedules concurrency, derives per-task diffs, and stages
your work for review from this list alone. A missing path is a silent lost
write.

**Interfaces:**
- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on. A bullet list, each entry leading with
  the symbol name in backticks, so the executor can match the surface
  mechanically. Prose may follow the backticked symbol.]
  - `functionName(arg: Type) -> Return`
  - `ExportedClass`
````

- [ ] **Step 4: Replace the per-task commit step with a report step**

In the same `## Task Structure` section, replace:

````markdown
- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

with:

````markdown
- [ ] **Step 5: Report**

List the files you touched and propose a commit message of one or two lines.
Do not stage and do not commit — your human partner reviews each stage and
commits it themselves.

```text
Files touched: tests/path/test.py, src/path/file.py
Proposed commit message:
  feat: add specific feature
```
````

- [ ] **Step 5: Add the two new self-review checks**

In `skills/writing-plans/SKILL.md`, in the `## Self-Review` section, after the
existing item **3. Type consistency**, insert:

```markdown
**4. Dependency check:** Does every task carry both `Depends on:` and
`Exclusive:`? Does every `Consumes` entry resolve to a `Produces` entry in a
task named in that task's `Depends on:`? A consumed symbol with no declared
dependency will be scheduled concurrently with the task that defines it.

**5. Disjointness check:** List every pair of tasks that share a file. Those
pairs serialize on your human partner's commits rather than running
concurrently. Confirm each pair is intentional — if two tasks share a file
only incidentally, splitting the file is usually better than serializing.
```

- [ ] **Step 6: Verify no commit instruction remains in the task template**

Run: `grep -n 'git commit' skills/writing-plans/SKILL.md`
Expected: no output (exit 1).

- [ ] **Step 7: Report**

```text
Files touched: skills/writing-plans/SKILL.md, tests/claude-code/fixtures/sample-plan.md
Proposed commit message:
  feat(writing-plans): declare task dependencies and drop per-task commits
  Adds Depends on:/Exclusive: fields and a shared parser fixture.
```

---

## Task 2: `plan-tasks` — the shared plan parser

**Depends on:** Task 1
**Exclusive:** none

**Files:**
- Create: `skills/subagent-driven-development/scripts/plan-tasks`
- Test: `tests/claude-code/test-plan-tasks.sh`

**Interfaces:**
- Consumes:
  - `tests/claude-code/fixtures/sample-plan.md`
- Produces:
  - `plan-tasks` — CLI `plan-tasks PLAN_FILE`, prints TSV `N<TAB>deps<TAB>files<TAB>exclusive<TAB>produces`, one line per task in plan order. `MISSING` for an absent field, `none` for a present-but-empty one.

- [ ] **Step 1: Write the failing test**

Create `tests/claude-code/test-plan-tasks.sh`:

```bash
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
```

Then: `chmod +x tests/claude-code/test-plan-tasks.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/claude-code/test-plan-tasks.sh`
Expected: FAIL — every assertion fails because `plan-tasks` does not exist.

- [ ] **Step 3: Write `plan-tasks`**

Create `skills/subagent-driven-development/scripts/plan-tasks`:

```bash
#!/usr/bin/env bash
# Parse an implementation plan into one TSV record per task, so every other SDD
# script shares one parser instead of five copies that drift apart.
#
# Output: N <TAB> deps <TAB> files <TAB> exclusive <TAB> produces
#   MISSING = the field never appeared; none = it appeared and was empty.
#   Lists are comma-separated, no spaces. Records are in plan order.
#
# Usage: plan-tasks PLAN_FILE
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: plan-tasks PLAN_FILE" >&2
  exit 2
fi

plan=$1
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }

awk '
  function emit() {
    if (n == "") return
    printf "%s\t%s\t%s\t%s\t%s\n", n,
      (seen_deps ? (deps == "" ? "none" : deps) : "MISSING"),
      (files == "" ? "MISSING" : files),
      (seen_excl ? (excl == "" ? "none" : excl) : "MISSING"),
      (prod  == "" ? "none" : prod)
    n=""; deps=""; files=""; excl=""; prod=""
    sect=""; inprod=0; seen_deps=0; seen_excl=0
  }
  # Fenced code inside a task must never be parsed as structure.
  /^```/ { infence = !infence; next }
  infence { next }

  /^#+[ \t]+Task[ \t]+[0-9]+/ {
    emit()
    match($0, /Task[ \t]+[0-9]+/)
    t = substr($0, RSTART, RLENGTH); sub(/^Task[ \t]+/, "", t)
    n = t
    next
  }
  n == "" { next }

  /^\*\*Depends on:\*\*/ {
    seen_deps = 1
    v = $0; sub(/^\*\*Depends on:\*\*[ \t]*/, "", v)
    gsub(/[Tt]ask[ \t]*/, "", v); gsub(/[ \t]/, "", v)
    if (v == "none") v = ""
    deps = v; sect=""; inprod=0; next
  }
  /^\*\*Exclusive:\*\*/ {
    seen_excl = 1
    v = $0; sub(/^\*\*Exclusive:\*\*[ \t]*/, "", v)
    gsub(/[ \t]/, "", v)
    if (v == "none") v = ""
    excl = v; sect=""; inprod=0; next
  }
  /^\*\*Files:\*\*/      { sect="files"; inprod=0; next }
  /^\*\*Interfaces:\*\*/ { sect="iface"; inprod=0; next }
  /^\*\*/                { sect=""; inprod=0; next }
  # A step heading closes the metadata region: everything below it is prose and
  # commands, and its backticked tokens are not interface symbols.
  /^-[ \t]*\[[ xX]\]/    { sect=""; inprod=0; next }

  sect == "files" {
    line = $0
    while (match(line, /`[^`]+`/)) {
      p = substr(line, RSTART+1, RLENGTH-2)
      sub(/:[0-9].*$/, "", p)          # strip a :123-145 line-range suffix
      files = (files == "" ? p : files "," p)
      line = substr(line, RSTART+RLENGTH)
    }
    next
  }

  sect == "iface" && /[Pp]roduces:/ { inprod=1; next }
  sect == "iface" && /[Cc]onsumes:/ { inprod=0; next }
  sect == "iface" && inprod {
    line = $0
    if (match(line, /`[^`]+`/)) {
      s = substr(line, RSTART+1, RLENGTH-2)
      if (match(s, /[A-Za-z_][A-Za-z0-9_]*/)) s = substr(s, RSTART, RLENGTH)
      prod = (prod == "" ? s : prod "," s)
    }
    next
  }

  END { emit() }
' "$plan"
```

Then: `chmod +x skills/subagent-driven-development/scripts/plan-tasks`

- [ ] **Step 4: Run the test to verify it passes**

Run: `./tests/claude-code/test-plan-tasks.sh`
Expected: `All plan-tasks tests passed`

- [ ] **Step 5: Run shellcheck**

Run: `shellcheck skills/subagent-driven-development/scripts/plan-tasks tests/claude-code/test-plan-tasks.sh`
Expected: no warnings. If `shellcheck` is not installed, skip and note it in your report.

- [ ] **Step 6: Report**

```text
Files touched: skills/subagent-driven-development/scripts/plan-tasks, tests/claude-code/test-plan-tasks.sh
Proposed commit message:
  feat(sdd): add plan-tasks, the shared plan-graph parser
  One parser for every SDD script, emitting TSV task records.
```

---

## Task 3: `ready-set` — the scheduler

**Depends on:** Task 2
**Exclusive:** none

**Files:**
- Create: `skills/subagent-driven-development/scripts/ready-set`
- Test: `tests/claude-code/test-ready-set.sh`

**Interfaces:**
- Consumes:
  - `plan-tasks PLAN_FILE` → TSV `N<TAB>deps<TAB>files<TAB>exclusive<TAB>produces`
- Produces:
  - `ready-set` — CLI `ready-set PLAN_FILE`, prints five lines: `BATON:`, `READY:`, `BLOCKED:`, `RUNNING:`, `PARKED:`, `COMMITTED:`. Exit 3 if any task has a `MISSING` field.

- [ ] **Step 1: Write the failing test**

Create `tests/claude-code/test-ready-set.sh`:

```bash
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
        || fail "collision edge blocks until predecessor is committed"
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
    [[ "$(line BLOCKED)" == *"4 (mutex 2)"* ]] && pass "mutex reason reported" || fail "mutex reason reported"

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
```

Then: `chmod +x tests/claude-code/test-ready-set.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/claude-code/test-ready-set.sh`
Expected: FAIL — `ready-set` does not exist.

- [ ] **Step 3: Write `ready-set`**

Create `skills/subagent-driven-development/scripts/ready-set`:

```bash
#!/usr/bin/env bash
# Compute the dispatchable task set from the plan's DAG and the ledger's state.
#
# Three edge types, deliberately different strengths:
#   semantic  (Depends on:)      -> predecessor must be review-clean
#   collision (shared file path) -> predecessor must be COMMITTED, because
#                                   `git add <shared file>` would otherwise
#                                   stage two tasks' work indistinguishably
#   mutex     (kind:name)        -> predecessor must merely not be running
#
# Usage: ready-set PLAN_FILE
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: ready-set PLAN_FILE" >&2
  exit 2
fi

plan=$1
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)
ws=$("$here/sdd-workspace" "$plan")
ledger="$ws/progress.md"
[ -f "$ledger" ] || : > "$ledger"

graph="$ws/.graph.tsv"
"$here/plan-tasks" "$plan" > "$graph"

if awk -F'\t' '$2=="MISSING"||$3=="MISSING"||$4=="MISSING"{bad=1} END{exit(bad?0:1)}' "$graph"; then
  echo "plan is missing required task fields (Depends on:/Files:/Exclusive:)" >&2
  awk -F'\t' '$2=="MISSING"||$3=="MISSING"||$4=="MISSING"{print "  Task "$1}' "$graph" >&2
  echo "Rule: execute sequentially and record the ruling, or add the fields." >&2
  exit 3
fi

awk -F'\t' -v ledger="$ledger" '
  # A path-shaped Exclusive entry serializes on a commit; a kind:name entry is
  # only a mutex. Deciding by syntax means it never depends on what exists on
  # disk at pre-flight — a lockfile a task regenerates may not exist yet.
  function ispath(s) { return (s ~ /\//) || (s ~ /\.[A-Za-z0-9]+$/) }
  function pathset(f, e,   x, i, k, r) {
    r = (f == "none" ? "" : f)
    if (e != "none") { k = split(e, x, ",")
      for (i = 1; i <= k; i++) if (ispath(x[i])) r = (r == "" ? x[i] : r "," x[i]) }
    return r
  }
  function mutexset(e,   x, i, k, r) {
    r = ""
    if (e != "none") { k = split(e, x, ",")
      for (i = 1; i <= k; i++) if (!ispath(x[i])) r = (r == "" ? x[i] : r "," x[i]) }
    return r
  }
  function shares(a, b,   x, y, i, j, na, nb) {
    if (a == "" || b == "") return 0
    na = split(a, x, ","); nb = split(b, y, ",")
    for (i = 1; i <= na; i++) for (j = 1; j <= nb; j++) if (x[i] == y[j]) return 1
    return 0
  }
  function add(s, v) { return (s == "" ? v : s " " v) }

  BEGIN {
    while ((getline l < ledger) > 0) {
      if (l !~ /^Task[ ]+[0-9]+:/) continue
      t = l; sub(/^Task[ ]+/, "", t); sub(/:.*$/, "", t)
      if (l ~ /: committed/)    committed[t] = 1
      if (l ~ /: review clean/) clean[t]     = 1
      if (l ~ /: dispatched/)   dispatched[t]= 1
      if (l ~ /: returned/)     returned[t]  = 1
    }
    close(ledger)
  }

  { n = $1; order[++c] = n; deps[n] = $2; paths[n] = pathset($3, $4); mutex[n] = mutexset($4) }

  END {
    baton = "none"
    for (i = 1; i <= c; i++) if (!committed[order[i]]) { baton = order[i]; break }

    ready = ""; blocked = ""; running = ""; parked = ""; done_ = ""
    for (i = 1; i <= c; i++) {
      n = order[i]
      if (committed[n])                     { done_ = add(done_, n); continue }
      if (dispatched[n] && !returned[n])    { running = add(running, n); continue }
      if (clean[n])                         { parked = add(parked, n); continue }
      if (returned[n])                      { continue }   # awaiting review

      reason = ""
      if (deps[n] != "none") {
        m = split(deps[n], d, ",")
        for (j = 1; j <= m; j++)
          if (!clean[d[j]] && !committed[d[j]])
            reason = reason (reason ? ", " : "") "dep " d[j]
      }
      for (k = 1; k < i; k++) {
        p = order[k]
        if (committed[p]) continue
        if (shares(paths[n], paths[p]))
          reason = reason (reason ? ", " : "") "collision " p
      }
      for (k = 1; k <= c; k++) {
        p = order[k]
        if (p == n || !(dispatched[p] && !returned[p])) continue
        if (shares(mutex[n], mutex[p]))
          reason = reason (reason ? ", " : "") "mutex " p
      }

      if (reason == "") ready = add(ready, n)
      else blocked = blocked (blocked ? " | " : "") n " (" reason ")"
    }

    printf "BATON: %s\n",     baton
    printf "READY: %s\n",     (ready   == "" ? "none" : ready)
    printf "BLOCKED: %s\n",   (blocked == "" ? "none" : blocked)
    printf "RUNNING: %s\n",   (running == "" ? "none" : running)
    printf "PARKED: %s\n",    (parked  == "" ? "none" : parked)
    printf "COMMITTED: %s\n", (done_   == "" ? "none" : done_)
  }
' "$graph"
```

Then: `chmod +x skills/subagent-driven-development/scripts/ready-set`

- [ ] **Step 4: Run the test to verify it passes**

Run: `./tests/claude-code/test-ready-set.sh`
Expected: `All ready-set tests passed`

- [ ] **Step 5: Report**

```text
Files touched: skills/subagent-driven-development/scripts/ready-set, tests/claude-code/test-ready-set.sh
Proposed commit message:
  feat(sdd): add ready-set, the parallel dispatch scheduler
  Semantic, file-collision, and mutex edges over the plan DAG.
```

---

## Task 4: `park-task` and `restore-task` — durable snapshots

**Depends on:** Task 2
**Exclusive:** none

**Files:**
- Create: `skills/subagent-driven-development/scripts/park-task`
- Create: `skills/subagent-driven-development/scripts/restore-task`
- Test: `tests/claude-code/test-park-restore.sh`

**Interfaces:**
- Consumes:
  - `plan-tasks PLAN_FILE` → TSV `N<TAB>deps<TAB>files<TAB>exclusive<TAB>produces`
- Produces:
  - `park-task` — CLI `park-task PLAN_FILE N`. Prints `<ref> <short-sha>`.
  - `restore-task` — CLI `restore-task PLAN_FILE N`. Exit 4 if any declared path has staged changes.
  - Ref naming: `refs/superpowers/sdd/<plan-basename>/task-<N>`

- [ ] **Step 1: Write the failing test**

Create `tests/claude-code/test-park-restore.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/park-task and scripts/restore-task. Parked work otherwise
# has no durable identity — it is dirty files in a shared tree — so these
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

    git branch -a | grep -q "task-1" \
        && fail "snapshot ref must not appear as a branch" \
        || pass "snapshot ref does not appear as a branch"

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
```

Then: `chmod +x tests/claude-code/test-park-restore.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/claude-code/test-park-restore.sh`
Expected: FAIL — neither script exists.

- [ ] **Step 3: Write `park-task`**

Create `skills/subagent-driven-development/scripts/park-task`:

```bash
#!/usr/bin/env bash
# Snapshot one task's declared files to a git ref, giving parked (finished but
# uncommitted) work a durable identity.
#
# GIT_INDEX_FILE gives us a private index, so this never touches .git/index —
# parking is safe while another stage is staged for the human's review. The ref
# lives outside refs/heads, so it is invisible to `git branch`, absent from
# `git status`, not pushed by default, and anchored against gc.
#
# Usage: park-task PLAN_FILE N
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: park-task PLAN_FILE N" >&2
  exit 2
fi

plan=$1
n=$2
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)
ws=$("$here/sdd-workspace" "$plan")
slug=$(basename "$plan" .md)
ref="refs/superpowers/sdd/$slug/task-$n"

files=$("$here/plan-tasks" "$plan" | awk -F'\t' -v n="$n" '$1==n{print $3}')
if [ -z "$files" ] || [ "$files" = "none" ] || [ "$files" = "MISSING" ]; then
  echo "task $n has no declared files in $plan" >&2
  exit 3
fi
IFS=',' read -r -a paths <<< "$files"

# Chain onto the previous snapshot so <ref>^ is always the state the last
# review saw — that is what makes a fix-round re-review scopeable.
parent=$(git rev-parse --verify --quiet "$ref" || git rev-parse HEAD)

idx="$ws/task-$n.index"
rm -f "$idx"
GIT_INDEX_FILE="$idx" git read-tree HEAD

present=()
for p in "${paths[@]}"; do
  if [ -e "$p" ]; then
    present+=("$p")
  else
    # A task may declare a file it deletes; record the deletion.
    GIT_INDEX_FILE="$idx" git rm --cached --quiet --ignore-unmatch -- "$p"
  fi
done
if [ ${#present[@]} -gt 0 ]; then
  GIT_INDEX_FILE="$idx" git add -- "${present[@]}"
fi

tree=$(GIT_INDEX_FILE="$idx" git write-tree)
snap=$(git commit-tree "$tree" -p "$parent" -m "park: task $n")
git update-ref "$ref" "$snap"
rm -f "$idx"

printf '%s %s\n' "$ref" "$(git rev-parse --short "$snap")"
```

Then: `chmod +x skills/subagent-driven-development/scripts/park-task`

- [ ] **Step 4: Write `restore-task`**

Create `skills/subagent-driven-development/scripts/restore-task`:

```bash
#!/usr/bin/env bash
# Restore one task's parked content into the working tree.
#
# --worktree without --staged means the index is never touched, so this is safe
# while a different stage is staged for the human's review. It refuses outright
# if any of THIS task's paths are staged, because overwriting the worktree copy
# of a path under review would make `git diff --staged` describe content that no
# longer exists.
#
# Usage: restore-task PLAN_FILE N
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: restore-task PLAN_FILE N" >&2
  exit 2
fi

plan=$1
n=$2
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)
slug=$(basename "$plan" .md)
ref="refs/superpowers/sdd/$slug/task-$n"

git rev-parse --verify --quiet "$ref" >/dev/null \
  || { echo "no snapshot for task $n at $ref" >&2; exit 3; }

files=$("$here/plan-tasks" "$plan" | awk -F'\t' -v n="$n" '$1==n{print $3}')
if [ -z "$files" ] || [ "$files" = "none" ] || [ "$files" = "MISSING" ]; then
  echo "task $n has no declared files in $plan" >&2
  exit 3
fi
IFS=',' read -r -a paths <<< "$files"

staged=$(git diff --cached --name-only -- "${paths[@]}")
if [ -n "$staged" ]; then
  echo "refusing: these paths have staged changes under review:" >&2
  echo "$staged" >&2
  exit 4
fi

git restore --source="$ref" --worktree -- "${paths[@]}"
printf 'restored task %s from %s\n' "$n" "$ref"
```

Then: `chmod +x skills/subagent-driven-development/scripts/restore-task`

- [ ] **Step 5: Run the test to verify it passes**

Run: `./tests/claude-code/test-park-restore.sh`
Expected: `All park/restore tests passed`

- [ ] **Step 6: Report**

```text
Files touched: skills/subagent-driven-development/scripts/park-task, skills/subagent-driven-development/scripts/restore-task, tests/claude-code/test-park-restore.sh
Proposed commit message:
  feat(sdd): snapshot parked stages to private refs
  Private-index parking plus worktree-only restore; index never touched.
```

---

## Task 5: `stage-task` — one stage in the index

**Depends on:** Task 2
**Exclusive:** none

**Files:**
- Create: `skills/subagent-driven-development/scripts/stage-task`
- Test: `tests/claude-code/test-stage-task.sh`

**Interfaces:**
- Consumes:
  - `plan-tasks PLAN_FILE` → TSV `N<TAB>deps<TAB>files<TAB>exclusive<TAB>produces`
- Produces:
  - `stage-task` — CLI `stage-task PLAN_FILE N`. Exit 4 if the index already holds staged changes; exit 5 if a declared path is missing from the worktree.

- [ ] **Step 1: Write the failing test**

Create `tests/claude-code/test-stage-task.sh`:

```bash
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
```

Then: `chmod +x tests/claude-code/test-stage-task.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/claude-code/test-stage-task.sh`
Expected: FAIL — `stage-task` does not exist.

- [ ] **Step 3: Write `stage-task`**

Create `skills/subagent-driven-development/scripts/stage-task`:

```bash
#!/usr/bin/env bash
# Stage exactly one task's declared files for the human partner's review.
#
# Refuses a non-empty index: two stages in the index at once destroys the review
# surface, because `git diff --staged` can no longer tell one stage's work from
# another's. The controller is the only actor that runs this; agents never touch
# the index at all.
#
# Usage: stage-task PLAN_FILE N
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: stage-task PLAN_FILE N" >&2
  exit 2
fi

plan=$1
n=$2
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }

if ! git diff --cached --quiet; then
  echo "index already holds staged changes; commit or unstage before staging task $n" >&2
  git diff --cached --name-only >&2
  exit 4
fi

here=$(cd "$(dirname "$0")" && pwd)
files=$("$here/plan-tasks" "$plan" | awk -F'\t' -v n="$n" '$1==n{print $3}')
if [ -z "$files" ] || [ "$files" = "none" ] || [ "$files" = "MISSING" ]; then
  echo "task $n has no declared files in $plan" >&2
  exit 3
fi
IFS=',' read -r -a paths <<< "$files"

missing=""
for p in "${paths[@]}"; do
  # Tracked-but-deleted is legitimate; never-existed is a mismatch.
  if [ ! -e "$p" ] && ! git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
    missing="$missing $p"
  fi
done
if [ -n "$missing" ]; then
  echo "task $n declares files that do not exist and are not tracked:$missing" >&2
  echo "the implementer did not produce what the plan declared" >&2
  exit 5
fi

git add -A -- "${paths[@]}"
git diff --cached --stat
```

Then: `chmod +x skills/subagent-driven-development/scripts/stage-task`

- [ ] **Step 4: Run the test to verify it passes**

Run: `./tests/claude-code/test-stage-task.sh`
Expected: `All stage-task tests passed`

- [ ] **Step 5: Report**

```text
Files touched: skills/subagent-driven-development/scripts/stage-task, tests/claude-code/test-stage-task.sh
Proposed commit message:
  feat(sdd): add stage-task, one stage in the index at a time
  Refuses a dirty index so `git diff --staged` stays a clean review surface.
```

---

## Task 6: `impact` — compute rejection fan-out

**Depends on:** Task 2
**Exclusive:** none

**Files:**
- Create: `skills/subagent-driven-development/scripts/impact`
- Test: `tests/claude-code/test-impact.sh`

**Interfaces:**
- Consumes:
  - `plan-tasks PLAN_FILE` → TSV `N<TAB>deps<TAB>files<TAB>exclusive<TAB>produces`
- Produces:
  - `impact` — CLI `impact PLAN_FILE N DIFF_FILE`. Prints `AFFECTED: none` or `AFFECTED: <task numbers>`.

- [ ] **Step 1: Write the failing test**

Create `tests/claude-code/test-impact.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/impact. Downstream tasks consume only the declared Produces
# surface, so a fix that never touches it has provably zero fan-out — this turns
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
    # on task 2 — the reach must be transitive.
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
```

Then: `chmod +x tests/claude-code/test-impact.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/claude-code/test-impact.sh`
Expected: FAIL — `impact` does not exist.

- [ ] **Step 3: Write `impact`**

Create `skills/subagent-driven-development/scripts/impact`:

```bash
#!/usr/bin/env bash
# Compute which tasks a fix to task N can actually affect.
#
# Downstream tasks consume only task N's declared Produces surface. If the fix
# diff never touches that surface, nothing downstream can be affected and the
# fan-out is provably zero. Conservative by construction: `git diff -U10` hunk
# headers carry enclosing function names, so a behavioral change inside a
# produced function still registers as a hit.
#
# Usage: impact PLAN_FILE N DIFF_FILE
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: impact PLAN_FILE N DIFF_FILE" >&2
  exit 2
fi

plan=$1
n=$2
diff_file=$3
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
[ -f "$diff_file" ] || { echo "no such diff file: $diff_file" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)
graph=$("$here/plan-tasks" "$plan")

produces=$(printf '%s\n' "$graph" | awk -F'\t' -v n="$n" '$1==n{print $5}')

hit=no
if [ -n "$produces" ] && [ "$produces" != "none" ] && [ "$produces" != "MISSING" ]; then
  IFS=',' read -r -a syms <<< "$produces"
  for s in "${syms[@]}"; do
    # Whole-word match only: `reconnected` must not count as a hit on `connect`.
    if grep -qE "(^|[^A-Za-z0-9_])${s}([^A-Za-z0-9_]|$)" "$diff_file"; then
      hit=yes
      break
    fi
  done
fi

if [ "$hit" = no ]; then
  echo "AFFECTED: none"
  exit 0
fi

printf '%s\n' "$graph" | awk -F'\t' -v n="$n" '
  { order[++c] = $1; deps[$1] = $2 }
  END {
    aff[n] = 1
    changed = 1
    while (changed) {
      changed = 0
      for (i = 1; i <= c; i++) {
        t = order[i]
        if (aff[t] || deps[t] == "none" || deps[t] == "MISSING") continue
        m = split(deps[t], d, ",")
        for (j = 1; j <= m; j++) if (aff[d[j]]) { aff[t] = 1; changed = 1 }
      }
    }
    out = ""
    for (i = 1; i <= c; i++) if (aff[order[i]] && order[i] != n) out = out " " order[i]
    print "AFFECTED:" (out == "" ? " none" : out)
  }
'
```

Then: `chmod +x skills/subagent-driven-development/scripts/impact`

- [ ] **Step 4: Run the test to verify it passes**

Run: `./tests/claude-code/test-impact.sh`
Expected: `All impact tests passed`

- [ ] **Step 5: Report**

```text
Files touched: skills/subagent-driven-development/scripts/impact, tests/claude-code/test-impact.sh
Proposed commit message:
  feat(sdd): add impact, computing rejection fan-out from Produces
  Fixes that miss the declared surface get a provable zero-fan-out verdict.
```

---

## Task 7: `review-package --task` working-tree mode

**Depends on:** Task 2
**Exclusive:** none

**Files:**
- Modify: `skills/subagent-driven-development/scripts/review-package`
- Test: `tests/claude-code/test-review-package-task.sh`

**Interfaces:**
- Consumes:
  - `plan-tasks PLAN_FILE` → TSV `N<TAB>deps<TAB>files<TAB>exclusive<TAB>produces`
  - Snapshot ref naming `refs/superpowers/sdd/<plan-basename>/task-<N>`
- Produces:
  - `review-package PLAN_FILE --task N [--since-park]` — writes a task-scoped working-tree review package and prints its path. Existing `PLAN_FILE BASE HEAD [OUTFILE]` mode unchanged.

- [ ] **Step 1: Write the failing test**

Create `tests/claude-code/test-review-package-task.sh`:

```bash
#!/usr/bin/env bash
# Tests for review-package's task-scoped working-tree mode. Nothing is committed
# under the new workflow, so per-task diffs come from the working tree scoped to
# the task's declared files — correct only because collision edges guarantee no
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
    grep -q "another agent mid-edit" "$pkg" \
        && fail "must exclude a concurrent agent's files" \
        || pass "excludes a concurrent agent's files"

    # --since-park must yield only the fix delta, not the whole task.
    "$SDD_SCRIPTS/park-task" plan.md 1 >/dev/null
    echo "my change plus the fix" > mine.txt
    "$SDD_SCRIPTS/park-task" plan.md 1 >/dev/null
    out="$("$SDD_SCRIPTS/review-package" plan.md --task 1 --since-park)"
    pkg="$(echo "$out" | sed -n 's/^wrote \([^:]*\):.*/\1/p')"
    grep -q "my change plus the fix" "$pkg" && pass "fix delta includes the fix" || fail "fix delta includes the fix"
    grep -q "created by me" "$pkg" \
        && fail "fix delta must exclude already-reviewed content" \
        || pass "fix delta excludes already-reviewed content"

    # The legacy commit-range mode must still work.
    git add -A && git commit -q -m second
    out="$("$SDD_SCRIPTS/review-package" plan.md HEAD~1 HEAD)"
    echo "$out" | grep -q "1 commit(s)" && pass "commit-range mode still works" || fail "commit-range mode still works"

    echo ""
    if [[ "$FAILURES" -eq 0 ]]; then echo "All review-package --task tests passed"; else
        echo "$FAILURES failure(s)"; exit 1; fi
}
main "$@"
```

Then: `chmod +x tests/claude-code/test-review-package-task.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/claude-code/test-review-package-task.sh`
Expected: FAIL — `--task` is parsed as a BASE and rejected.

- [ ] **Step 3: Replace the argument-handling head of `review-package`**

In `skills/subagent-driven-development/scripts/review-package`, replace:

```bash
if [ $# -lt 3 ] || [ $# -gt 4 ]; then
  echo "usage: review-package PLAN_FILE BASE HEAD [OUTFILE]" >&2
  exit 2
fi

plan=$1
base=$2
head=$3
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }

git rev-parse --verify --quiet "$base" >/dev/null || { echo "bad BASE: $base" >&2; exit 2; }
git rev-parse --verify --quiet "$head" >/dev/null || { echo "bad HEAD: $head" >&2; exit 2; }
```

with:

```bash
usage() {
  echo "usage: review-package PLAN_FILE BASE HEAD [OUTFILE]" >&2
  echo "       review-package PLAN_FILE --task N [--since-park]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
plan=$1
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)

# Task-scoped working-tree mode. Nothing is committed until the human partner
# commits it, so a task's diff comes from the working tree scoped to its
# declared files. This is correct only because collision edges guarantee no
# other uncommitted task shares those paths.
if [ "$2" = "--task" ]; then
  n=${3:-}
  [ -n "$n" ] || usage
  case "${4:-}" in ""|--since-park) ;; *) usage ;; esac

  ws=$("$here/sdd-workspace" "$plan")
  slug=$(basename "$plan" .md)
  files=$("$here/plan-tasks" "$plan" | awk -F'\t' -v n="$n" '$1==n{print $3}')
  if [ -z "$files" ] || [ "$files" = "none" ] || [ "$files" = "MISSING" ]; then
    echo "task $n has no declared files in $plan" >&2
    exit 3
  fi
  IFS=',' read -r -a paths <<< "$files"

  # Tree-to-worktree by default. In --since-park mode both sides are snapshots
  # and the diff is tree-to-tree, because `git diff <tree> -- <path>` resolves
  # the right-hand side through the index: an UNTRACKED file captured in the
  # snapshot would otherwise read as a deletion.
  if [ "${4:-}" = "--since-park" ]; then
    ref="refs/superpowers/sdd/$slug/task-$n"
    git rev-parse --verify --quiet "$ref^" >/dev/null \
      || { echo "no previous snapshot at ${ref}^ to scope the re-review against" >&2; exit 3; }
    range=("$ref^" "$ref")
    base_desc="${ref}^ (the state the previous review saw)"
  else
    range=("HEAD")
    base_desc="HEAD (working tree)"
  fi

  out="$ws/review-task-$n-$(date +%s).diff"
  {
    echo "# Review package: task $n vs $base_desc"
    echo
    echo "## Scope"
    echo "Scoped to task ${n}'s declared files. Other files in this working tree"
    echo "may be mid-edit by concurrently running implementers; they are out of"
    echo "scope and must not be reviewed or flagged."
    printf '  %s\n' "${paths[@]}"
    echo
    echo "## Files changed"
    git --no-optional-locks diff --stat "${range[@]}" -- "${paths[@]}"
    echo
    echo "## Diff"
    git --no-optional-locks diff -U10 "${range[@]}" -- "${paths[@]}"
    if [ ${#range[@]} -eq 1 ]; then
      # Tree-to-worktree only: untracked files are invisible to `git diff`, so
      # they need a synthetic new-file diff. The tree-to-tree range already
      # carries additions.
      echo
      echo "## New files"
      for p in "${paths[@]}"; do
        if [ -e "$p" ] && ! git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
          # --no-index exits 1 when files differ, which is the normal case here.
          git --no-optional-locks diff --no-index -U10 /dev/null "$p" || true
        fi
      done
    fi
  } > "$out"

  echo "wrote ${out}: task ${n}, $(wc -c < "$out" | tr -d ' ') bytes"
  exit 0
fi

[ $# -ge 3 ] && [ $# -le 4 ] || usage
base=$2
head=$3

git rev-parse --verify --quiet "$base" >/dev/null || { echo "bad BASE: $base" >&2; exit 2; }
git rev-parse --verify --quiet "$head" >/dev/null || { echo "bad HEAD: $head" >&2; exit 2; }
```

- [ ] **Step 4: Update the script's header comment**

Replace the `# Usage: review-package PLAN_FILE BASE HEAD [OUTFILE]` line with:

```bash
# Usage: review-package PLAN_FILE BASE HEAD [OUTFILE]      (commit-range mode)
#        review-package PLAN_FILE --task N [--since-park]  (working-tree mode)
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `./tests/claude-code/test-review-package-task.sh`
Expected: `All review-package --task tests passed`

- [ ] **Step 6: Verify the existing workspace test still passes**

Run: `./tests/claude-code/test-sdd-workspace.sh`
Expected: all pass — the commit-range mode must be unchanged.

- [ ] **Step 7: Report**

```text
Files touched: skills/subagent-driven-development/scripts/review-package, tests/claude-code/test-review-package-task.sh
Proposed commit message:
  feat(sdd): add task-scoped working-tree mode to review-package
  Diffs an uncommitted stage against HEAD or its previous snapshot.
```

---

## Task 8: Subagent prompt templates — no-git and shared-tree contracts

**Depends on:** none
**Exclusive:** none

**Files:**
- Modify: `skills/subagent-driven-development/implementer-prompt.md`
- Modify: `skills/subagent-driven-development/task-reviewer-prompt.md`
- Modify: `skills/subagent-driven-development/re-review-prompt.md`

**Interfaces:**
- Consumes: nothing
- Produces:
  - Implementer report contract fields `Files touched:` and `Proposed commit message:`
  - Task reviewer report field `Produces verified:`

This task has no dependency on the scripts and can run concurrently with Tasks 2–7.

- [ ] **Step 1: Replace the implementer's commit step**

In `skills/subagent-driven-development/implementer-prompt.md`, in the `## Your Job` section, replace:

```text
    4. Commit your work
    5. Self-review (see below)
    6. Report back
```

with:

```text
    4. Self-review (see below)
    5. Report back with your file list and a proposed commit message
```

- [ ] **Step 2: Replace the full-suite instruction**

In the same file, replace:

```text
    While iterating, run the focused test for what you're changing; run the
    full suite once before committing, not after every edit.
```

with:

```text
    Run only the tests that cover the files you own. Never run the full
    suite: other implementers may be mid-edit in this same working tree, and
    a full-suite run measures their half-finished work, not yours.
```

- [ ] **Step 3: Add the no-git and shared-tree sections**

In the same file, immediately after the `## You Do Not Dispatch Subagents` section and before `## Code Organization`, insert:

````text
    ## You Do Not Touch Git

    Never run any of these: `git add`, `git commit`, `git stash`,
    `git checkout`, `git restore`, `git reset`, `git rebase`, `git merge`,
    `git clean`, `git switch`. The controller stages; your human partner
    commits. You do neither.

    Read-only git is fine, but always as `git --no-optional-locks ...` (for
    example `git --no-optional-locks diff -- <your files>`). Plain `git status`
    takes `.git/index.lock` to refresh cached stat data and will collide with
    other agents working in this tree.

    Edit ONLY the files listed in your task brief's Files block. If your work
    genuinely requires touching a file that is not listed, that is a
    scheduling collision nobody knows about yet — stop and report
    NEEDS_CONTEXT. Do not edit it.

    ## You Are Not Alone

    Other implementers may be editing this working tree RIGHT NOW, in files
    outside your list. Their work-in-progress will look like breakage. It is
    not yours to fix.

    | Thought | Reality |
    |---------|---------|
    | "This unrelated test is failing, I'll just fix it" | Another agent is mid-edit in that file. Your "fix" fights their work and pollutes your diff. Report it as an observation. |
    | "Let me run the full suite before reporting" | A full suite in a shared tree measures other agents' half-finished work. Run only tests covering your own files. |
    | "This file looks broken, I'll revert it" | It is mid-edit, not broken. Never revert, stash, or check out anything. |
    | "I need to touch one file outside my list" | That is a collision the scheduler does not know about. Escalate NEEDS_CONTEXT. |
    | "I'll commit so my work is safe" | Your work is snapshotted by the controller the moment you report. Commits belong to your human partner. |
    | "The build is broken, so I can't verify my change" | Re-run once. If the failure is in files outside your list, say so in your report and move on. |
````

- [ ] **Step 4: Update the implementer report contract**

In the same file, in the `## Report Format` section, replace:

```text
    - **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
    - Commits created (short SHA + subject)
    - One-line test summary (e.g. "14/14 passing, output pristine")
    - Your concerns, if any
    - The report file path
```

with:

```text
    - **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
    - **Files touched:** comma-separated paths, exactly what you changed
    - **Proposed commit message:** one or two lines, imperative mood. Your
      human partner reviews this stage and commits it themselves; this is the
      message they will see suggested.
    - One-line test summary (e.g. "14/14 passing, output pristine")
    - Any unrelated breakage you observed in files you do not own
    - Your concerns, if any
    - The report file path
```

- [ ] **Step 5: Update the "After Review Findings" section**

In the same file, replace:

```text
    Fix them, re-run the tests that cover the amended code, and append a fix
    report to your report file: what you changed, the covering tests you
    ran, the command, and the output.
```

with:

```text
    Findings may come from the task reviewer or directly from your human
    partner at the commit gate; treat both the same way. Fix them, re-run the
    tests that cover the amended code, and append a fix report to your report
    file: what you changed, the covering tests you ran, the command, and the
    output.
```

- [ ] **Step 6: Scope the task reviewer to the working-tree package**

In `skills/subagent-driven-development/task-reviewer-prompt.md`, replace:

```text
    **Base:** [BASE_SHA]
    **Head:** [HEAD_SHA]
    **Diff file:** [DIFF_FILE]
```

with:

```text
    **Diff file:** [DIFF_FILE]

    The diff is scoped to this task's declared files, taken from the working
    tree — nothing is committed until the human partner commits it. Other files
    in this checkout may be mid-edit by implementers working concurrently on
    other tasks. They are out of scope: do not read them, review them, or flag
    them.
```

- [ ] **Step 7: Remove the reviewer's git-command fallback**

In the same file, replace:

```text
    If the diff file is missing, fetch the diff yourself:
    `git diff --stat [BASE_SHA]..[HEAD_SHA]` and `git diff [BASE_SHA]..[HEAD_SHA]`.
```

with:

```text
    If the diff file is missing, say so and report NEEDS_CONTEXT. Do not
    reconstruct it with git commands: this task's work is uncommitted and
    interleaved in the working tree with other tasks' uncommitted work, so any
    range you invent will show you other people's changes as if they were this
    task's.
```

- [ ] **Step 8: Add the `Produces verified` verdict to the reviewer**

In `skills/subagent-driven-development/task-reviewer-prompt.md`, in the section that lists the reviewer's required report output, add this required field:

````text
    ## Produces Verification (required)

    The task brief declares an `Interfaces: Produces` list — the exact symbols
    later tasks are permitted to rely on. Check each declared symbol against
    the diff and report:

    ```
    Produces verified: ✅
    Produces verified: ⚠️ diverged — declared `getUser(id) -> User`, actual `getUser(id) -> User | None`
    ```

    Report ⚠️ whenever an implemented symbol's name, parameters, or return type
    differs from the declaration, or when a declared symbol is absent. Tasks
    that depend on this one are dispatched against the DECLARED surface, so a
    silent divergence means downstream work is being built on something that
    does not exist.
````

- [ ] **Step 9: Point the re-reviewer at the snapshot ref**

In `skills/subagent-driven-development/re-review-prompt.md`, replace:

```text
    **Fix base:** [FIX_BASE_SHA] (the head the previous review saw)
    **Head:** [HEAD_SHA]
    **Diff file:** [DIFF_FILE]
```

with:

```text
    **Diff file:** [DIFF_FILE]

    The diff contains only the fix delta — the change since the state the
    previous review saw — scoped to this task's declared files. Other files in
    this checkout may be mid-edit by implementers working concurrently on other
    tasks and are out of scope.
```

- [ ] **Step 10: Remove the re-reviewer's git fallback**

In the same file, replace:

```text
    If the diff file is missing, fetch the diff yourself:
    `git diff --stat [FIX_BASE_SHA]..[HEAD_SHA]` and
    `git diff [FIX_BASE_SHA]..[HEAD_SHA]`.
```

with:

```text
    If the diff file is missing, say so and report NEEDS_CONTEXT. Do not
    reconstruct it with git commands — the fix is uncommitted and shares this
    working tree with other tasks' uncommitted work.
```

- [ ] **Step 11: Verify no stale commit instructions remain**

Run: `grep -n 'Commit your work\|BASE_SHA\|FIX_BASE_SHA' skills/subagent-driven-development/*.md`
Expected: no output (exit 1).

- [ ] **Step 12: Report**

```text
Files touched: skills/subagent-driven-development/implementer-prompt.md, skills/subagent-driven-development/task-reviewer-prompt.md, skills/subagent-driven-development/re-review-prompt.md
Proposed commit message:
  feat(sdd): give subagents no-git and shared-tree contracts
  Implementers stop committing; reviewers get task-scoped worktree diffs.
```

---

## Task 9: SDD SKILL.md — scheduler, commit gate, recovery

**Depends on:** Task 3, Task 4, Task 5, Task 6, Task 7
**Exclusive:** none

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

**Interfaces:**
- Consumes:
  - `ready-set PLAN_FILE` → `BATON:`/`READY:`/`BLOCKED:`/`RUNNING:`/`PARKED:`/`COMMITTED:` lines, exit 3 on a legacy plan
  - `park-task PLAN_FILE N`, `restore-task PLAN_FILE N`, `stage-task PLAN_FILE N`
  - `impact PLAN_FILE N DIFF_FILE` → `AFFECTED: none` or `AFFECTED: <numbers>`
  - `review-package PLAN_FILE --task N [--since-park]`
- Produces:
  - The controller behaviour contract every other change in this plan serves

- [ ] **Step 1: Replace the no-parallelism prohibition**

In `skills/subagent-driven-development/SKILL.md`, in the `### 1. Dispatch the implementer` section, replace:

```text
- Never dispatch multiple implementation subagents in parallel (conflicts).
```

with:

```text
- Dispatch the whole READY set from `scripts/ready-set` in ONE message so they
  run concurrently. Never dispatch a task `ready-set` did not name.
```

- [ ] **Step 2: Add the Scheduling section**

Insert a new `## Scheduling` section immediately before the existing `## The Task Loop` heading:

````markdown
## Scheduling

Independent tasks run concurrently. Do not decide which ones by reading the
plan — run this skill's `scripts/ready-set PLAN_FILE` and dispatch exactly
what it names:

```text
BATON: 2
READY: 5 6 7
BLOCKED: 3 (dep 2) | 8 (collision 5)
RUNNING: 4
PARKED: 6
COMMITTED: 1
```

Three edge types decide that answer, and their strengths differ:

| Edge | The successor waits until the predecessor is |
|------|----------------------------------------------|
| Semantic (`Depends on:`) | **review-clean** — NOT committed. It reads the predecessor's code from the working tree. |
| File collision (a shared path) | **committed** |
| Mutex (`kind:name` in `Exclusive:`) | **not running** |

The collision edge is the strong one because of staging: two uncommitted tasks
holding edits to one file cannot be staged apart, and your human partner's
review surface is `git diff --staged`.

Dispatch the whole READY set in one message. Recompute after every agent
return and after every commit — a commit unblocks collision successors, and a
return unblocks semantic ones. There is no concurrency cap; mutex edges are
the only limiter.

A plan whose tasks lack `Depends on:`/`Exclusive:` makes `ready-set` exit 3.
Rule on it rather than guessing the graph: execute sequentially, ledger
`Ruling: legacy plan without dependency declarations — executing sequentially`,
and proceed.
````

- [ ] **Step 3: Add the Commit Gate section**

Insert a new `## The Commit Gate` section immediately after the new `## Scheduling` section:

````markdown
## The Commit Gate

You stage. Your human partner commits. **You never run `git commit`.**

When a task's review comes back clean:

1. **Ledger it immediately** — file list, proposed commit message, verdict,
   `Produces verified` result. Parked work has no other identity: after a
   compaction this line is the only thing that knows which of forty modified
   files belong to this stage, and staging the wrong set silently commits
   another stage's half-finished work under your partner's review.
2. **Park it** — `scripts/park-task PLAN_FILE N`, on every agent return. This
   is what makes a redo reversible and gives the next fix round's re-review
   something to scope against.
3. **Not the baton?** Mark it waiting and keep scheduling. Stage nothing.
4. **The baton** (every lower-numbered task is committed)? Run
   `scripts/stage-task PLAN_FILE N` and present:

```text
Stage 2 of 8 staged: API endpoints
Proposed:  feat(api): add /users and /users/:id endpoints
           Adds request validation and 404 handling.

  1 ✔ committed 4f3a91c      5 ● parked   (settings page)
  2 ▸ STAGED — your review    6 ● parked   (profile page)
  3 ○ blocked (dep: 2)        7 ○ blocked (dep: 4, 6)
  4 ◐ running                 8 ○ blocked (dep: 7)

Tests:    12/12 passing, output pristine
Review:   clean (spec ✅, quality approved, Produces verified ✅)
Report:   .superpowers/sdd/<plan>/task-2-report.md

Downstream if you reject:  3, 4 · stages 5, 6 unaffected
Review with `git diff --staged`. Commit when ready, or tell me what to change.
```

5. **The commit pipeline stops. The work pipeline does not.** Agent
   completions still wake you: process reports, park stages, dispatch the new
   READY set. Just do not touch the index — it belongs to this stage until
   your partner commits.
6. **On their next message**, read `git status --porcelain` and `git log` as
   ground truth rather than your own recollection. Ledger
   `Task <N>: committed <sha7>`, advance the baton, recompute READY, and stage
   the next parked stage whose review is clean. If they committed only part of
   the staged set or amended it, the stage is not complete until its declared
   files are clean.

### When your partner asks for changes

1. `git restore --staged -- <the task's files>` — the index must be clean
   while the fix runs, or `git diff --staged` will describe content that no
   longer exists.
2. Their words enter the fix loop verbatim as findings. **Partner-originated
   rounds are uncapped** — the five-round breaker exists to stop agent-on-agent
   non-convergence, not to ration responses to your human partner. Ledger them
   as `Task <N>: partner fix round <R>`.
3. Re-review scoped with `scripts/review-package PLAN_FILE --task N --since-park`,
   then re-park, re-stage, re-present.
4. **Compute the fan-out; do not assume it.** Run
   `scripts/impact PLAN_FILE N <fix diff>`. `AFFECTED: none` means the fix
   never touched this task's declared `Produces` surface, so nothing
   downstream can be affected — no flags, no re-verification, no dispatches.
   Otherwise, for each affected task: stop dispatching new transitive
   dependents (already-running ones finish and are marked provisional), re-run
   the affected task's own scoped tests, and only if those fail or the
   interface changed, `scripts/restore-task` it and re-dispatch against the
   amended interface.

A task whose review reports `Produces verified: ⚠️` blocks its dependents from
being dispatched until you rule on the divergence. Downstream tasks are
dispatched against the DECLARED surface; a silent divergence means they are
being built on something that does not exist.
````

- [ ] **Step 4: Amend the continuous-execution rule**

Replace:

```text
**Continuous execution:** Do not pause to check in with your human partner between tasks. Execute all tasks from the plan without stopping. The only reasons to stop are the four named below, or all tasks complete. "Should I continue?" prompts and progress summaries waste their time — they asked you to execute the plan, so execute it.
```

with:

```text
**Continuous execution:** Do not pause to check in with your human partner between tasks. Execute all tasks from the plan without stopping. The only reasons to stop are the four named below, the commit gate, or all tasks complete. "Should I continue?" prompts and progress summaries waste their time — they asked you to execute the plan, so execute it.

The commit gate is an expected stop, and it halts only the commit pipeline: while a stage waits for your partner's review, keep dispatching, keep reviewing, keep parking. An idle pipeline during a review is wasted time they did not ask you to spend.
```

- [ ] **Step 5: Rewrite the recovery guidance**

Replace:

```text
- The ledger is your recovery map: the commits it names exist in git even
  when your context no longer remembers creating them. After compaction,
  trust the ledger and `git log` over your own recollection.
```

with:

```text
- The ledger is your recovery map, and under the commit gate it is the ONLY
  map: `git log` shows committed stages only, so parked work appears there not
  at all. After compaction, trust the ledger over your own recollection.
  Tasks with `committed` are done. Tasks with `parked` but no `committed` live
  in the working tree and at their snapshot ref — verify with
  `git status --porcelain` that the files the ledger attributes to them are
  still modified, and `scripts/restore-task` any the tree lost. Tasks with
  `dispatched` and no `returned` were lost mid-flight; re-dispatch them.
```

- [ ] **Step 6: Note that snapshot refs survive a workspace wipe**

Replace:

```text
- `git clean -fdx` will destroy the workspace (it's git-ignored scratch); if
  that happens, recover from `git log`.
```

with:

```text
- `git clean -fdx` will destroy the workspace (it's git-ignored scratch) and
  every parked stage's working-tree content with it. Snapshot refs live in
  `.git` and survive: `git for-each-ref refs/superpowers/sdd/<plan-basename>`
  enumerates what was parked, and `scripts/restore-task` brings each back.
```

- [ ] **Step 7: Point the DONE handler at the task-scoped package**

Replace:

```text
**DONE:** Generate the review package (`scripts/review-package PLAN_FILE BASE HEAD`, from this skill's directory — it prints the unique file path it wrote; BASE is the commit you recorded before dispatching the implementer — never `HEAD~1`, which silently drops all but the last commit of a multi-commit task), then dispatch the task reviewer with the printed path.
```

with:

```text
**DONE:** Park the work (`scripts/park-task PLAN_FILE N`), then generate the review package (`scripts/review-package PLAN_FILE --task N`, from this skill's directory — it prints the unique file path it wrote), then dispatch the task reviewer with the printed path. The package is scoped to the task's declared files, so a concurrently running implementer's edits never enter this review.
```

- [ ] **Step 8: Point the fix loop's re-review at the snapshot**

Replace:

```text
**The re-review is scoped.** Run `scripts/review-package PLAN_FILE FIX_BASE HEAD`
where FIX_BASE is the head the previous review saw, and dispatch
```

with:

```text
**The re-review is scoped.** Park the fix (`scripts/park-task PLAN_FILE N`),
run `scripts/review-package PLAN_FILE --task N --since-park` — which diffs
against the state the previous review saw — and dispatch
```

- [ ] **Step 9: Drop the recorded-BASE instruction**

Replace:

```text
Record BASE (`git rev-parse HEAD`) before dispatching — the review package
and fix-round diffs need it.
```

with:

```text
Record nothing before dispatching: per-task diffs come from the declared file
list, not from a commit range. `scripts/review-package --task N` derives them.
```

- [ ] **Step 10: Update the process diagram**

In the `## The Process` digraph, add these node declarations inside `cluster_per_task`, after the `"Append completion to ledger, mark todo complete" [shape=box];` line:

```dot
        "Park (./scripts/park-task); baton?" [shape=diamond];
        "Wait: keep scheduling other tasks" [shape=box];
        "Stage (./scripts/stage-task), present to partner" [shape=box];
        "Partner commits or requests changes" [shape=diamond];
        "Uncapped partner fix round; ./scripts/impact for fan-out" [shape=box];
```

Then replace these two edges:

```dot
    "Append completion to ledger, mark todo complete" -> "More tasks remain?";
    "More tasks remain?" -> "Dispatch implementer subagent (./implementer-prompt.md)" [label="yes"];
```

with:

```dot
    "Append completion to ledger, mark todo complete" -> "Park (./scripts/park-task); baton?";
    "Park (./scripts/park-task); baton?" -> "Wait: keep scheduling other tasks" [label="no"];
    "Park (./scripts/park-task); baton?" -> "Stage (./scripts/stage-task), present to partner" [label="yes"];
    "Stage (./scripts/stage-task), present to partner" -> "Partner commits or requests changes";
    "Partner commits or requests changes" -> "Uncapped partner fix round; ./scripts/impact for fan-out" [label="changes"];
    "Uncapped partner fix round; ./scripts/impact for fan-out" -> "Stage (./scripts/stage-task), present to partner";
    "Partner commits or requests changes" -> "More tasks remain?" [label="commits"];
    "Wait: keep scheduling other tasks" -> "More tasks remain?";
    "More tasks remain?" -> "Dispatch READY set (./scripts/ready-set) in one message" [label="yes"];
```

And replace this edge:

```dot
    "Setup: worktree, ledger check, read plan, pre-flight review" -> "Dispatch implementer subagent (./implementer-prompt.md)";
```

with:

```dot
    "Setup: worktree, ledger check, read plan, pre-flight review" -> "Dispatch READY set (./scripts/ready-set) in one message";
    "Dispatch READY set (./scripts/ready-set) in one message" -> "Dispatch implementer subagent (./implementer-prompt.md)";
```

Add the node declaration inside `cluster_per_task`:

```dot
        "Dispatch READY set (./scripts/ready-set) in one message" [shape=box];
```

- [ ] **Step 11: Extend the pre-flight conflict scan**

In the `## Setup` section, after the paragraph beginning "The scan's output is a table, not a verdict.", append:

```markdown
The scan also validates the graph. Run `scripts/ready-set PLAN_FILE` once
before dispatching anything: it exits 3 if any task lacks `Depends on:`,
`Files:`, or `Exclusive:`. Add one row per pair of tasks sharing a file —
those serialize on your partner's commits rather than running concurrently —
and one row per task whose `Consumes` names a symbol no declared dependency
`Produces`, which would otherwise be scheduled concurrently with the task
that defines it.
```

- [ ] **Step 12: Specify the ledger schema**

In the `## Setup` section, after the bullet beginning "Create the ledger with
its identity as the first line", insert:

````markdown
- After the pre-flight scan, write the graph block, then append one event line
  per event as it happens — never in a later batch. Parked work has no other
  identity, and a controller that batches these loses the file-to-stage mapping
  on compaction.

```text
## Graph
Task 1: deps=none files=src/db.py,tests/test_db.py excl=none
Task 2: deps=1 files=src/api.py,tests/test_api.py excl=none
Collision edges: (3,7) share src/api.py
Mutex edges: (2,4) share test-port:5432
Baton: 1

Task 5: dispatched (agent=<id>, model=<m>)
Task 5: returned DONE files=web/settings.tsx msg="feat: add settings page"
Task 5: parked ref=refs/superpowers/sdd/<slug>/task-5
Task 5: review clean (Produces verified ✅)
Task 5: waiting (baton at 2)
Task 2: staged
Task 2: committed 4f3a91c
```

The `files=` field on the `returned` line is the recovery key: it is the only
record of which of forty modified files belong to which stage.
````

- [ ] **Step 13: Add the new rationalizations**

In the `## Common Rationalizations` table, append these rows:

```markdown
| "I'll commit this stage myself to keep moving" | Commits belong to your human partner. You stage; they commit. |
| "These two stages look independent, I'll run them together" | `ready-set` decides that, not your reading of the plan. An undeclared shared file is a silent lost write, not a merge conflict you'd notice. |
| "The partner is slow, I'll stage the next stage too" | Two stages in the index destroys the review surface. One stage holds the index until it is committed. |
| "Parking is bookkeeping — the files are right there in the tree" | Dirty files have no identity. After a compaction, the ledger and the snapshot ref are the only things that know which files are whose. |
| "The fix was tiny, downstream is obviously fine" | Run `scripts/impact`. If it touches the `Produces` surface, downstream is affected whether it looks obvious or not. |
| "An unrelated test broke, I'll have someone fix it" | Another agent is mid-edit in this tree. Unrelated breakage is an observation for the ledger, not a fix dispatch. |
```

- [ ] **Step 14: Delete snapshot refs in the Finish section**

In the `## Finish` section, replace:

```text
When the final whole-branch review is clean and its fixes are merged,
delete this plan's workspace (`rm -rf <workspace>`) — the git history is
the record now. Sibling directories belong to other plans; leave them
alone.
```

with:

```text
When the final whole-branch review is clean and its fixes are merged, delete
this plan's workspace (`rm -rf <workspace>`) and its snapshot refs
(`git for-each-ref --format='%(refname)' refs/superpowers/sdd/<plan-basename> |
xargs -r -n1 git update-ref -d`) — the git history is the record now. Sibling
directories and other plans' refs are not yours; leave them alone.
```

- [ ] **Step 15: Verify no stale references remain**

Run: `grep -n 'FIX_BASE\|never `HEAD~1`\|multiple implementation subagents in parallel' skills/subagent-driven-development/SKILL.md`
Expected: no output (exit 1).

- [ ] **Step 16: Verify the digraph still parses**

Run: `command -v dot >/dev/null && sed -n '/^digraph process/,/^}/p' skills/subagent-driven-development/SKILL.md | dot -Tsvg -o /dev/null && echo OK || echo "graphviz not installed - skipped"`
Expected: `OK`, or the skip message.

- [ ] **Step 17: Report**

```text
Files touched: skills/subagent-driven-development/SKILL.md
Proposed commit message:
  feat(sdd): parallel scheduling and a human commit gate
  Controller dispatches the ready set, stages one stage, never commits.
```

---

## Task 10: Ripples in sibling skills

**Depends on:** Task 4, Task 9
**Exclusive:** none

**Files:**
- Modify: `skills/executing-plans/SKILL.md`
- Modify: `skills/dispatching-parallel-agents/SKILL.md`
- Modify: `skills/finishing-a-development-branch/SKILL.md`

**Interfaces:**
- Consumes:
  - Snapshot ref naming `refs/superpowers/sdd/<plan-basename>/task-<N>`
  - The commit-gate contract from `subagent-driven-development/SKILL.md`
- Produces: nothing later tasks rely on

- [ ] **Step 1: Add the commit gate to executing-plans**

In `skills/executing-plans/SKILL.md`, in `### Step 2: Execute Tasks`, replace:

```text
For each task:
1. Mark as in_progress
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Mark as completed
```

with:

```text
For each task:
1. Mark as in_progress
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Stage the task's declared files (`git add -- <the task's Files list>`) and
   stop. Present the file list, a one-or-two-line proposed commit message, and
   the test results. Your human partner reviews `git diff --staged` and commits.
   **Never run `git commit` yourself.**
5. Once they have committed, mark as completed and move to the next task

This skill executes sequentially, so exactly one task is ever staged. If you
have subagents available, superpowers:subagent-driven-development runs
independent tasks concurrently behind the same gate.
```

- [ ] **Step 2: Point dispatching-parallel-agents at the scheduler**

In `skills/dispatching-parallel-agents/SKILL.md`, immediately after the `**Core principle:** Dispatch one agent per independent problem domain. Let them work concurrently.` line, insert:

```markdown
**Executing a plan?** Use superpowers:subagent-driven-development instead. It
derives the safe concurrency from the plan's declared file sets and dependency
graph rather than from your judgement, and it holds the commit gate. This skill
is for ad-hoc independent problems — unrelated test failures, separate
subsystems — that no plan describes.

**Whenever agents share a working tree,** every dispatch must carry two rules:
agents run no index-touching git command (`add`, `commit`, `stash`, `checkout`,
`restore`, `reset`, `clean`), using `git --no-optional-locks ...` for read-only
git so they do not collide on `.git/index.lock`; and agents edit only the files
in their own scope, reporting anything else as an observation rather than
fixing it. Without the second rule, an agent that runs the full suite will see
another agent's work-in-progress as breakage and "fix" it.
```

- [ ] **Step 3: Guard finishing-a-development-branch against parked work**

In `skills/finishing-a-development-branch/SKILL.md`, in `## Step 1: Verify Tests`, insert before the `Run the project's full test suite` line:

```markdown
First, confirm nothing is uncommitted:

```bash
git status --porcelain
```

If anything is staged or modified, a stage is still awaiting your human
partner's review. Stop and say which stage — finishing a branch with parked
work would leave that work out of the history entirely.
```

- [ ] **Step 4: Delete snapshot refs during cleanup**

In the same file, in the cleanup step (Step 6), append:

```markdown
Also delete the plan's SDD snapshot refs, which are scratch state rather than
history:

```bash
git for-each-ref --format='%(refname)' refs/superpowers/sdd/ \
  | xargs -r -n1 git update-ref -d
```
```

- [ ] **Step 5: Verify the three files changed and nothing else**

Run: `git status --porcelain skills/`
Expected: exactly three modified paths — `executing-plans/SKILL.md`, `dispatching-parallel-agents/SKILL.md`, `finishing-a-development-branch/SKILL.md`.

- [ ] **Step 6: Report**

```text
Files touched: skills/executing-plans/SKILL.md, skills/dispatching-parallel-agents/SKILL.md, skills/finishing-a-development-branch/SKILL.md
Proposed commit message:
  feat(skills): propagate the commit gate to sibling skills
  Sequential gate, shared-tree rules, and parked-work guard.
```

---

## Task 11: Test registration and integration-test inversion

**Depends on:** Task 3, Task 4, Task 5, Task 6, Task 7
**Exclusive:** none

**Files:**
- Modify: `tests/claude-code/run-skill-tests.sh`
- Modify: `tests/claude-code/test-subagent-driven-development-integration.sh`

**Interfaces:**
- Consumes:
  - `tests/claude-code/test-plan-tasks.sh`, `test-ready-set.sh`, `test-park-restore.sh`, `test-stage-task.sh`, `test-impact.sh`, `test-review-package-task.sh`
- Produces: nothing later tasks rely on

- [ ] **Step 1: Register the new fast tests**

In `tests/claude-code/run-skill-tests.sh`, replace:

```bash
tests=(
    "test-worktree-path-policy.sh"
    "test-sdd-workspace.sh"
    "test-subagent-driven-development.sh"
)
```

with:

```bash
tests=(
    "test-worktree-path-policy.sh"
    "test-sdd-workspace.sh"
    "test-plan-tasks.sh"
    "test-ready-set.sh"
    "test-park-restore.sh"
    "test-stage-task.sh"
    "test-impact.sh"
    "test-review-package-task.sh"
    "test-subagent-driven-development.sh"
)
```

- [ ] **Step 2: Add the new tests to the --help listing**

In the same file, in the `--help` output block that lists test files (near the existing `test-subagent-driven-development.sh  Test skill loading and requirements` line), add:

```bash
            echo "  test-plan-tasks.sh  Plan graph parser"
            echo "  test-ready-set.sh  Parallel dispatch scheduler"
            echo "  test-park-restore.sh  Snapshot refs for parked stages"
            echo "  test-stage-task.sh  One-stage-at-a-time staging"
            echo "  test-impact.sh  Rejection fan-out from Produces"
            echo "  test-review-package-task.sh  Task-scoped working-tree diffs"
```

- [ ] **Step 3: Invert the integration test's commit assertion**

In `tests/claude-code/test-subagent-driven-development-integration.sh`, replace the whole Test 7 block — from the line `# Test 7: Git commits show proper workflow` through the `fi` that closes its `if [ "$commit_count" -gt 2 ]` conditional — with:

```bash
# Test 7: The controller must NOT commit. Under the commit gate the human
# partner is the only actor that commits, and an unattended test run has no
# human — so a clean run leaves work staged or parked, never committed.
echo "Test 7: Commit gate respected..."
commit_count=$(git -C "$TEST_PROJECT" log --oneline | wc -l)
if [ "$commit_count" -eq 1 ]; then
    echo "  [PASS] Controller created no commits (only the initial commit)"
else
    echo "  [FAIL] Controller created $((commit_count - 1)) commit(s); the gate forbids all of them"
    git -C "$TEST_PROJECT" log --oneline
    FAILURES=$((FAILURES + 1))
fi

ledger_file=$(find "$TEST_PROJECT/.superpowers/sdd" -name progress.md 2>/dev/null | head -1)
if [ -n "$ledger_file" ] && grep -qE ': (parked|staged)' "$ledger_file"; then
    echo "  [PASS] Ledger records parked or staged work"
else
    echo "  [FAIL] Ledger has no parked/staged line; the gate never ran"
    [ -n "$ledger_file" ] && cat "$ledger_file"
    FAILURES=$((FAILURES + 1))
fi
```

Read the surrounding code first: if the file tracks failures under a different
variable name than `FAILURES`, use that name instead.

- [ ] **Step 4: Update the integration test's header comment**

Replace:

```bash
#   - >=3 git commits (initial + per-task commits, exercising SDD's
#     commit-per-task workflow shape)
```

with:

```bash
#   - exactly 1 git commit (the initial one) — the controller stages but never
#     commits, and an unattended run has no human partner to commit for it
```

- [ ] **Step 5: Run the full fast test suite**

Run: `./tests/claude-code/run-skill-tests.sh`
Expected: every registered test passes.

- [ ] **Step 6: Verify all new scripts are executable**

Run: `ls -l skills/subagent-driven-development/scripts/ | awk '{print $1, $NF}'`
Expected: every script shows an executable bit (`-rwxr-xr-x`).

- [ ] **Step 7: Report**

```text
Files touched: tests/claude-code/run-skill-tests.sh, tests/claude-code/test-subagent-driven-development-integration.sh
Proposed commit message:
  test(sdd): register scheduler tests and invert the commit assertion
  The controller must create no commits; the gate leaves work staged.
```
