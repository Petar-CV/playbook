# Parallel SDD Scheduling and the Manual Commit Gate — Design Spec

**Status:** Approved design (brainstormed 2026-08-30); implementation plan to
follow. Fork-local change — not intended for upstream.
**Objective:** make subagent-driven-development dispatch independent plan
stages concurrently, and replace agent self-commits with a human commit gate
where exactly one stage at a time is staged for review.
**Hard invariant:** eval-tuned sentences in the existing skills move; they do
not get reworded. New machinery is additive.

## Problems

Three, all from real execution sessions:

1. **Serialized execution of independent work.** SDD's SKILL.md carries a flat
   prohibition — "Never dispatch multiple implementation subagents in parallel
   (conflicts)." A plan whose last two stages are frontend work and whose first
   four are backend runs all six in sequence. The prohibition is correct about
   the hazard (two agents editing one file) but resolves it by giving up all
   concurrency rather than by establishing when concurrency is safe.
2. **Commits happen without human review.** `implementer-prompt.md` step 4 says
   "Commit your work," and `writing-plans` ends every task template with
   `git add` + `git commit -m`. The human partner sees the work only at the
   final whole-branch review, by which point every stage is already history.
3. **No protocol for shared-tree work.** Nothing tells an implementer that
   another implementer may be editing the same working tree. An agent that runs
   the full suite in a shared tree sees another agent's half-finished work as
   failures and "fixes" them — fighting concurrent work and polluting its own
   diff.

## Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | The controller is the only actor that touches the git index. Agents run no index-touching git command; the human is the only actor that commits. | `.git/index.lock` is exclusive, and even `git status` takes it to refresh cached stat data. Two concurrent agents running any index-touching command collide. A flat prohibition removes the whole race class and needs no per-agent baton state. |
| 2 | The plan declares the dependency graph; the executor verifies it. `writing-plans` gains mandatory `Depends on:` and `Exclusive:` per task, and `Files:` becomes mandatorily exhaustive. | The plan author holds spec context the executor lacks. Inference from prose is guesswork, and a wrong guess here is a silent lost write, not a visible error. Verification at pre-flight reuses SDD's existing conflict-scan step. |
| 3 | Scheduling is a ready queue over a DAG, not lock-step waves. | Waves turn independence into a dependency: with `1→2→3→4` plus independent `5,6`, a wave scheduler makes stage 2 wait for the frontend to finish. A ready queue starts 1, 5, and 6 at t=0 and starts 2 the moment 1 is clean. |
| 4 | Run-ahead is unbounded. No concurrency cap, no parked-work cap, no dependency-depth cap. | Human partner's call. At this repo's typical plan size (under 8 stages, 2–4 independent) the dominant saving is overlapping human review latency with agent work, which every cap gives back. Layers 1–4 of the rejection protocol make the resulting blast radius recoverable rather than merely bounded. |
| 5 | A stage is staged for the human only after its automated task review is clean. | The human never reviews work a reviewer already knows is broken. Preserves the existing two-verdict gate unchanged. |
| 6 | Human change requests at the gate re-enter the existing fix loop as findings, and are uncapped. | The five-round breaker exists to stop agent-on-agent non-convergence. Rationing responses to the human partner is not its purpose. |
| 7 | Parked work is snapshotted to a `refs/superpowers/sdd/…` ref via a private index. | Parked work otherwise has no durable identity — it is dirty files in a shared tree, named only by a ledger line. Snapshots make redo reversible and make crash/compaction recovery real, without putting anything on the branch. |
| 8 | Rejection fan-out is computed from the `Produces` surface, not assumed. | Downstream tasks consume only the declared interface. A fix that does not touch that surface provably cannot affect them. Most rejections are stylistic and become zero-cost. |
| 9 | The task reviewer reports a `Produces verified:` verdict; divergence blocks the stage's dependents. | Interface drift is the failure that invalidates a whole chain. Catching it costs one line on a report already being written, with no new agent and no added latency. |
| 10 | Extend subagent-driven-development in place; push deterministic computation into scripts. | Per `writing-skills`: heavy reference and mechanical computation belong outside SKILL.md, discipline rules belong inline. Ready-set math is mechanical and testable; the no-git contract is a rationalization-resistant rule that must be inline. |

## Non-Goals

- Per-agent git worktrees with cherry-pick integration. Rejected: dependent
  stages could not read predecessors' uncommitted work, and the human would
  review in a tree other than their own.
- Changing the branch history shape. The human still produces exactly one
  commit per stage, in plan order, with a message they control.
- Upstreaming. This diverges from obra/superpowers by design.
- Automatic conflict resolution between agents. Concurrency is permitted only
  where it is provably safe; overlapping work is serialized, never merged.

## Architecture

### 1. Actors and privileges

| Actor | May do | May never do |
|-------|--------|--------------|
| Implementer / reviewer subagents | Read-only git, always as `git --no-optional-locks …`. Edit only files in their task's `Files:` block. | `add`, `commit`, `stash`, `checkout`, `restore`, `reset`, `rebase`, `merge`, `clean`, `switch` |
| Controller | Stage (`git add`), snapshot refs, restore worktree files, unstage | `git commit` |
| Human partner | Commit | — |

`--no-optional-locks` (git ≥ 2.15) prevents read-only agent commands from
taking `.git/index.lock` and colliding with the controller or each other.

**Minimum git version: 2.23** (for `git restore --source=<tree-ish>
--worktree`).

### 2. Plan schema (`writing-plans`)

Each task block gains two fields and tightens two others:

```markdown
### Task 5: Settings page

**Depends on:** none
**Files:**
- Create: `web/settings/page.tsx`
- Test:   `web/settings/page.test.tsx`
**Exclusive:** none
**Interfaces:**
- Consumes:
  - `getUser(id: str) -> User`
- Produces:
  - `SettingsPage`
```

- **`Depends on:`** — mandatory. A comma-separated list of task numbers whose
  `Produces` this task `Consumes`, or the literal `none`. Silence is a plan
  defect, not an implied `none`.
- **`Files:`** — mandatory and **exhaustive**. Every file the task creates,
  modifies, or deletes. This is the load-bearing invariant of the entire
  design: parallel safety, per-task diffs, and precise staging all rest on it.
- **`Exclusive:`** — mandatory. Shared resources the task contends for that are
  not in its own edit set: regenerated lockfiles, migration sequence numbers,
  fixed ports, shared test databases, codegen outputs. Or the literal `none`.
  Syntax decides the edge type, so it never depends on what exists on disk at
  pre-flight: an entry containing `/` or a file extension is a **path** and
  yields a file-collision edge; an entry of the form `<kind>:<name>` (e.g.
  `test-port:5432`, `db:integration`) is a **mutex**.
- **`Produces:`** — tightened to a bullet list, each entry leading with the
  symbol name in backticks. This makes the surface mechanically extractable for
  the fan-out computation in §9. Prose descriptions after the backticked symbol
  are permitted.
- **`Step 5: Commit` is deleted** from the task template, replaced by
  *"Step 5: Report — list the files you touched and propose a 1–2 line commit
  message."* Plans no longer instruct commits.

Two additions to `writing-plans`' Self-Review checklist:

4. **Dependency check.** Every `Consumes` entry resolves to a `Produces` entry
   in a task named in this task's `Depends on:`. Every task has both new fields.
5. **Disjointness check.** List every pair of tasks sharing a file. Those pairs
   will serialize on the human's commits — confirm each is intentional.

### 3. Dependency graph

Three edge types, with deliberately different strengths:

| Edge | Condition | Successor may start when predecessor is… |
|------|-----------|------------------------------------------|
| **Semantic** | B names A in `Depends on:` | **review-clean** — not committed. B reads A's code from the working tree. |
| **File collision** | `Files(A) ∩ Files(B) ≠ ∅`, A earlier in plan order | **committed** |
| **Mutex** | `Exclusive(A) ∩ Exclusive(B) ≠ ∅`, non-path resource | **not running** — mutual exclusion, no ordering |

The collision edge is the strong one **because of staging**: if A and B both
hold uncommitted edits to `api.py`, `git add api.py` stages both
indistinguishably, destroying the review surface and making per-task diffs
underivable. This is why file collision demands a commit while semantic
dependency does not.

### 4. Scheduler

```
READY = { T : T not dispatched
              ∧ ∀ S ∈ Depends(T)         : S is review-clean
              ∧ ∀ S : collision(S,T), S<T : S is committed
              ∧ ∀ S : mutex(S,T)          : S is not running }
```

The controller dispatches the entire `READY` set in a single message so the
harness runs them concurrently, and recomputes `READY` on every agent return
and every human commit. No concurrency cap; mutex edges are the only limiter.

`scripts/ready-set` computes this from the plan and the ledger. The controller
never derives it by inspection — anything an agent improvises here fails
silently as concurrent edits to one file.

### 5. Parking and snapshot refs

When a stage's work lands (on every agent return, before review dispatch, and
again after every fix round), the controller snapshots it:

```bash
IDX="$WS/task-$N.index"
GIT_INDEX_FILE=$IDX git read-tree HEAD
GIT_INDEX_FILE=$IDX git add -- $FILES
TREE=$(GIT_INDEX_FILE=$IDX git write-tree)
SNAP=$(git commit-tree "$TREE" -p "$PARENT" -m "park: task $N v$SEQ")
git update-ref "refs/superpowers/sdd/$SLUG/task-$N" "$SNAP"
```

`PARENT` is `HEAD` for the first park of a task, and the previous snapshot
commit for each subsequent park — so the ref carries a chain and
`<ref>^` is the previously reviewed state.

Properties this buys:

- **`GIT_INDEX_FILE` keeps `.git/index` untouched.** Parking is safe even while
  another stage is staged for the human's review.
- **The ref lives outside `refs/heads`.** Invisible to `git branch`, absent
  from `git status`, not pushed by default, and anchored against `gc`.
- **Redo is reversible.** `restore-task` uses `git restore --source=<ref>
  --worktree -- $FILES`, which touches the worktree only, never the index.
- **The fix-round re-review anchor comes free.** The previous snapshot is
  exactly the state the last review saw, so the scoped re-review diff is
  `git diff <ref>^ -- $FILES`. No separate snapshot machinery is needed.
- **Crash and compaction recovery become real.** Parked work survives a lost
  session, a stray `git checkout`, and `git clean -fdx`.

Because the tree is seeded from `HEAD`, every diff against a snapshot **must**
be path-scoped, or it will show other stages' committed work. All scripts apply
`-- $FILES` unconditionally; the scoping is mechanized, not remembered.

Refs are deleted alongside the workspace when the plan completes.

### 6. Review packaging without commits

`review-package` gains a task-scoped working-tree mode:

- **First review of task N:** diff the working tree against `HEAD`, scoped to
  task N's files, plus a synthetic new-file diff for each untracked file in the
  list (`git diff --no-index /dev/null <f>`, which does not touch the index).
- **Fix-round re-review:** diff against `<ref>^`, scoped identically. This is
  precisely the fix delta, preserving the existing skill's insistence that
  re-reviews cannot wander.

Correctness rests entirely on no other uncommitted task sharing those paths,
which the collision edge guarantees.

The existing commit-range mode is retained unchanged for the final
whole-branch review, where every stage is already committed.

### 7. The commit gate

When task N's task review comes back clean:

1. **Ledger immediately** — file list, proposed commit message, verdict,
   `Produces verified` result. Before anything else, because parked work has no
   other identity.
2. **Not the baton?** Mark waiting. Stage nothing. Continue scheduling. The
   stage was already parked on the agent's return (§5); no second snapshot is
   taken, because no code changed between the return and the verdict.
3. **Is the baton** (every task numbered below N is committed)?
   `scripts/stage-task PLAN_FILE N` runs `git add -- $FILES` and prints
   `git diff --cached --stat`. The controller then presents:

```
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

4. **The commit pipeline stops; the work pipeline does not.** Agent completions
   still wake the controller, which processes reports, parks stages, and
   dispatches newly-ready tasks. It does not touch the index — that belongs to
   stage N until the human commits.
5. On the human's next message the controller reads `git status --porcelain`
   and `git log` as ground truth (never its own recollection), ledgers
   `Task N: committed <sha7>`, advances the baton, unblocks collision
   successors, and stages the next parked stage whose review is clean.

If the human commits only part of the staged set, or amends, or commits
unrelated work, the ledger's file list reconciles against `git status` and the
stage is not complete until its files are clean.

### 8. Rejection protocol

The human requests changes at the gate:

1. **Unstage** — `git restore --staged -- $FILES`, leaving the index clean
   while the fix runs. Otherwise `git diff --staged` would show stale content.
2. **Fix loop** — the human's words enter the existing fix loop verbatim as
   findings. Partner-originated rounds are **uncapped** and ledgered separately
   as `Task N: partner fix round <R>`.
3. **Scoped re-review** against `<ref>^`, then re-park, re-stage, re-present.

### 9. Fan-out containment (Layers 2–4)

**Layer 2 — compute the blast radius.** After a partner-fix, `scripts/impact`
greps the fix diff for every symbol in task N's `Produces` list.

- No hit → fan-out is **provably zero**. The fix was internal: a private rename,
  an added test, a better message. Nothing downstream reaches inside the
  declared surface, so nothing downstream can be affected. No flags, no
  re-verification, no dispatches.
- Hit → only the transitive semantic consumers of the changed symbols are
  affected.

`git diff -U10` hunk headers carry enclosing function names, so behavioral
changes inside a produced function still register. The check is conservative
by construction: ambiguity resolves to "affected".

**Layer 3 — freeze the affected subtree only.** New dispatch of transitive
semantic dependents of the rejected stage stops. Already-running dependents are
allowed to finish (killing them discards real work) and are marked provisional.
Independent branches keep running untouched.

**Affected-stage handling, cheapest first:** re-run the affected stage's own
scoped tests. Green plus no interface change → ledger a ruling and continue.
Red, or an interface change → restore from the snapshot ref and re-dispatch
against the amended interface.

**Layer 4 — prevent interface drift.** The task reviewer's report contract
gains one line:

```
Produces verified: ✅  |  ⚠️ diverged — declared getUser(id)->User, actual getUser(id)->User|None
```

A `⚠️` **blocks that stage's dependents from being dispatched** until the
controller rules on it. The reviewer already reads both the brief (which
carries `Produces`) and the diff, so this adds no agent, no gate, and no
latency — it guards the single condition under which downstream work gets built
on sand.

### 10. Ledger schema

A pre-flight graph block plus append-on-receipt event lines. The identity first
line is unchanged.

```
# SDD ledger — plan: docs/superpowers/plans/2026-08-30-example.md

## Graph
Task 1: deps=none files=src/db.py,tests/test_db.py excl=none
Task 2: deps=1 files=src/api.py,tests/test_api.py excl=none
Task 5: deps=none files=web/settings/page.tsx,web/settings/page.test.tsx excl=none
Collision edges: (3,7) share src/api.py
Mutex edges: (2,4) share test-port:5432
Baton: 1

Task 5: dispatched (agent=<id>, model=<m>)
Task 5: returned DONE files=web/settings/page.tsx,web/settings/page.test.tsx msg="feat: add settings page"
Task 5: parked ref=refs/superpowers/sdd/<slug>/task-5 v1
Task 5: review clean (Produces verified ✅)
Task 5: waiting (baton at 2)
Task 2: staged
Task 2: committed 4f3a91c
Task 5: staged
```

The `files=` field on the return line is the recovery key. After a compaction,
it is the only thing that knows which of forty modified files belong to stage 5,
and staging the wrong set silently commits another stage's half-finished work
under the human's review.

### 11. Recovery

SDD's current advice — *"trust the ledger and `git log`"* — is rewritten.
`git log` now shows only committed stages. The revised procedure:

1. Read the ledger. Tasks with `committed` are done.
2. Tasks with `parked` but no `committed` exist in the working tree **and** at
   their snapshot ref. Verify with `git status --porcelain` that every file the
   ledger attributes to the stage is still modified; if the tree was clobbered,
   `restore-task` recovers it from the ref.
3. Tasks with `dispatched` but no `returned` were lost mid-flight. Re-dispatch.
4. `git clean -fdx` destroys the workspace but **not** the snapshot refs, which
   live in `.git`. The ledger itself is workspace-resident and is the one thing
   that does not survive; if it is gone, `git for-each-ref
   refs/superpowers/sdd/<slug>` enumerates what was parked.

## Script Contracts

All scripts live in `skills/subagent-driven-development/scripts/` and follow
the existing convention: `set -euo pipefail`, usage to stderr, exit 2 on usage
error.

| Script | Usage | Behavior |
|--------|-------|----------|
| `ready-set` | `ready-set PLAN_FILE` | Prints `BATON:`, `READY:`, `BLOCKED:` (with per-task reason), `PARKED:`, `COMMITTED:`. Exit 3 if any task lacks `Depends on:`, `Files:`, or `Exclusive:`. |
| `park-task` | `park-task PLAN_FILE N` | Snapshots task N's files to its ref via a private index. Prints the ref name and snapshot SHA. |
| `restore-task` | `restore-task PLAN_FILE N` | `git restore --source=<ref> --worktree -- $FILES`. Exit 4 if any of those paths has staged changes. |
| `stage-task` | `stage-task PLAN_FILE N` | Exit 4 if the index already holds staged changes. Otherwise `git add -- $FILES`, print `git diff --cached --stat`. |
| `impact` | `impact PLAN_FILE N DIFF_FILE` | Prints `AFFECTED: <task numbers>` or `AFFECTED: none`, by matching task N's `Produces` symbols against the diff and following semantic edges. |
| `review-package` | `review-package PLAN_FILE --task N [--since-park]` | Task-scoped working-tree package. `--since-park` diffs against `<ref>^`. Existing `PLAN_FILE BASE HEAD` mode retained. |

`sdd-workspace` and `task-brief` are unchanged.

## Prompt Template Changes

**`implementer-prompt.md`** — step 4 "Commit your work" becomes "Report your
file list and propose a 1–2 line commit message." Two new sections:

*You Do Not Touch Git* — the forbidden command list, the `--no-optional-locks`
requirement for read-only git, and the rule that files outside `Files:` are a
`NEEDS_CONTEXT` escalation, never a free edit.

*You Are Not Alone* — other implementers may be editing this tree right now.
Followed by a rationalization table, per `writing-skills`' guidance that
discipline failures need explicit counters:

| Thought | Reality |
|---------|---------|
| "This unrelated test is failing, I'll just fix it" | Another agent is mid-edit in that file. Your "fix" fights their work. Report it. |
| "Let me run the full suite before reporting" | A full suite in a shared tree measures other agents' half-finished work. Run only tests covering your own files. |
| "This file looks broken, I'll revert it" | It is mid-edit, not broken. Never revert, stash, or check out anything. |
| "I need to touch one file outside my list" | That is a collision the scheduler does not know about. Escalate NEEDS_CONTEXT. |
| "I'll commit so my work is safe" | Commits belong to your human partner. Leave everything unstaged and report. |

The report contract gains `Files touched:` and `Proposed commit message:`.

**`task-reviewer-prompt.md`** — the diff is a task-scoped working-tree package,
not a commit range; files outside the task's list may be mid-edit by other
agents and are out of scope. Report contract gains `Produces verified:`.

**`re-review-prompt.md`** — `FIX_BASE_SHA` becomes the task's previous snapshot
ref; the same not-alone scoping note applies.

## SKILL.md Changes (subagent-driven-development)

- Replace "Never dispatch multiple implementation subagents in parallel
  (conflicts)" with the scheduler section and its `ready-set` pointer.
- New **Scheduling** section: the three edge types, the ready-set rule, and the
  instruction to dispatch the whole ready set in one message.
- New **Commit Gate** section: baton, staging, presentation format, the
  stop-the-commit-pipeline-not-the-work-pipeline rule, rejection protocol.
- Amend **Continuous execution**: the commit gate is an expected stop, and it
  halts only the commit pipeline. The existing four stop reasons are unchanged.
- Amend **Setup/recovery** per §11.
- Extend the **Common Rationalizations** table:

| Excuse | Reality |
|--------|---------|
| "I'll commit this stage myself to keep moving" | Commits belong to your human partner. You stage; they commit. |
| "Two stages look independent, I'll just run them together" | `ready-set` decides that, not your reading. An undeclared shared file is a silent lost write. |
| "The human is slow, I'll stage the next stage too" | Two stages in the index destroys the review surface. One stage holds the index until it is committed. |
| "Parking is bookkeeping, the files are right there in the tree" | Dirty files have no identity. After a compaction the ledger and the snapshot ref are the only things that know which files are whose. |
| "The fix was tiny, downstream is obviously fine" | Run `impact`. If it touches the `Produces` surface, downstream is affected whether it looks obvious or not. |

## Ripples

- **`executing-plans`** — same commit gate, sequential (no scheduler). Remove
  the implicit commit expectation; add propose-message-and-stop.
- **`dispatching-parallel-agents`** — cross-reference the scheduler and the
  no-git contract. Its "Review and Integrate" step currently assumes the
  controller merges freely.
- **`finishing-a-development-branch`** — refuse to proceed while parked
  uncommitted work exists, and delete the plan's snapshot refs during cleanup.

## Testing

New bash tests under `tests/claude-code/`, registered in `run-skill-tests.sh`'s
fast `tests=()` array:

- `test-ready-set.sh` — fixture plan plus fixture ledgers: baton advance, ready
  set across states, collision blocking until commit, mutex exclusion, exit 3 on
  a task missing the new fields, sequential fallback detection.
- `test-park-restore.sh` — park, mutate the file, restore, assert content;
  assert `.git/index` is byte-identical before and after a park; assert the ref
  does not appear in `git branch -a`; assert survival of `git clean -fdx`.
- `test-stage-task.sh` — stages exactly the declared list and nothing else;
  exit 4 when the index is already dirty.
- `test-review-package-task.sh` — `--task` mode includes untracked files,
  excludes other tasks' files, and `--since-park` yields only the fix delta.
- `test-impact.sh` — `Produces`-symbol hit and miss cases; transitive consumers.

**Existing test to change:**
`test-subagent-driven-development-integration.sh:278-285` asserts
`commit_count > 2`. Under the new model an unattended run has no human to
commit, so this fails by design. It is inverted: assert the controller created
**no** commits, that staged changes exist, and that the ledger contains a
`parked` and a `staged` line.

## Migration

Plans written before this change lack `Depends on:` and `Exclusive:`.
`ready-set` exits 3 on them. The controller then rules — per SDD's existing
"Rulings, not stalls" — to execute fully sequentially, ledgers
`Ruling: legacy plan without dependency declarations — executing sequentially`,
and proceeds. Old plans keep working at old speed; they never run unsafely.

## Risks Accepted

1. **Unbounded run-ahead means a late rejection can fan out.** Mitigated by
   Layers 1–4 — snapshots make it reversible, `impact` usually proves it empty,
   the subtree freeze contains it, and `Produces verified` prevents the
   expensive case. Not eliminated.
2. **An omitted path in `Files:` is a silent clobber.** Mitigated by the
   escalate-don't-edit rule and the pre-flight cross-check. This is the
   design's sharpest edge and rests on plan-authoring discipline.
3. **A dead session with many parked stages depends on the ledger.** Mitigated
   by ledger-on-receipt and by snapshot refs surviving in `.git`. If the
   workspace is destroyed, `git for-each-ref` still enumerates parked stages.
4. **Human latency now sits inside the pipeline.** A collision successor waits
   for a real commit. Accepted deliberately: manual review is the point.
