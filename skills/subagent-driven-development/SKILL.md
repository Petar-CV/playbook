---
name: subagent-driven-development
description: Use when executing implementation plans with independent tasks in the current session
---

# Subagent-Driven Development

Execute plan by dispatching a fresh implementer subagent per task, a task review (spec compliance + code quality) after each, and a broad whole-branch review at the end.

**Why subagents:** You delegate tasks to specialized agents with isolated context. By precisely crafting their instructions and context, you ensure they stay focused and succeed at their task. They should never inherit your session's context or history — you construct exactly what they need. This also preserves your own context for coordination work.

**Core principle:** Fresh subagent per task + task review (spec + quality) + broad final review = high quality, fast iteration

**Narration:** between tool calls, narrate at most one short line — the
ledger and the tool results carry the record.

**Continuous execution:** Do not pause to check in with your human partner between tasks. Execute all tasks from the plan without stopping. The only reasons to stop are the four named below, the commit gate, or all tasks complete. "Should I continue?" prompts and progress summaries waste their time — they asked you to execute the plan, so execute it.

The commit gate is an expected stop, and it halts only the commit pipeline: while a stage waits for your partner's review, keep dispatching, keep reviewing, keep parking. An idle pipeline during a review is wasted time they did not ask you to spend.

If your partner chose the express lane at the plan handoff, that stop does not exist at all — see [The express lane](#the-express-lane). Completion and the four hard stops are then the only things that stop you.

**Rulings, not stalls.** A running plan does not wait on a human. Conflicts,
ambiguities, plan defects, a cap you would have asked to exceed — decide
them. The spec is the binding authority, the plan is its argument, and your
judgment settles what neither answers. Record every decision in the ledger as
`Ruling: <what you decided> — <why> — <what it costs if wrong>`, and keep
going. A wrong ruling costs rework your human partner can see and undo; a
session parked on a question costs their whole day and buys nothing.

Four things stop you, and only these: an irreversible or destructive
operation; a security-sensitive action; a side effect outside this worktree
that norms say you ask about first (a merge, a push to a shared branch, a
publish); and a plan so broken that every path forward is a guess. For those,
stop and ask.

## When to Use

```dot
digraph when_to_use {
    "Have implementation plan?" [shape=diamond];
    "Tasks mostly independent?" [shape=diamond];
    "Stay in this session?" [shape=diamond];
    "subagent-driven-development" [shape=box];
    "executing-plans" [shape=box];
    "Manual execution or brainstorm first" [shape=box];

    "Have implementation plan?" -> "Tasks mostly independent?" [label="yes"];
    "Have implementation plan?" -> "Manual execution or brainstorm first" [label="no"];
    "Tasks mostly independent?" -> "Stay in this session?" [label="yes"];
    "Tasks mostly independent?" -> "Manual execution or brainstorm first" [label="no - tightly coupled"];
    "Stay in this session?" -> "subagent-driven-development" [label="yes"];
    "Stay in this session?" -> "executing-plans" [label="no - parallel session"];
}
```

**vs. Executing Plans (parallel session):**

- Same session (no context switch)
- Fresh subagent per task (no context pollution)
- Review after each task (spec compliance + code quality), broad review at the end
- Independent tasks run concurrently; your partner reviews and commits one stage at a time

## The Process

```dot
digraph process {
    rankdir=TB;

    subgraph cluster_per_task {
        label="Per Task";
        "Dispatch implementer subagent (./implementer-prompt.md)" [shape=box];
        "Implementer asks questions?" [shape=diamond];
        "Answer questions, provide context" [shape=box];
        "Implementer implements, tests, self-reviews, reports" [shape=box];
        "Generate review package, dispatch task reviewer (./task-reviewer-prompt.md)" [shape=box];
        "Spec ✅ and quality approved?" [shape=diamond];
        "Finding conflicts with plan text?" [shape=diamond];
        "Rule on the conflict, ledger the ruling" [shape=box];
        "Fix round R of 5: R≤3 resume implementer; R≥4 fresh implementer, more capable model" [shape=box];
        "Dispatch scoped re-review (./re-review-prompt.md)" [shape=box];
        "All findings addressed?" [shape=diamond];
        "R = 5?" [shape=diamond];
        "Adjudicate each open finding" [shape=box];
        "Any load-bearing finding?" [shape=diamond];
        "Rule and continue; stop only if every path forward is a guess" [shape=box];
        "Park findings in ledger with rulings" [shape=box];
        "Append completion to ledger, mark todo complete" [shape=box];
        "Dispatch READY set (./scripts/ready-set) in one message" [shape=box];
        "Park (./scripts/park-task); baton?" [shape=diamond];
        "Wait: keep scheduling other tasks" [shape=box];
        "Stage (./scripts/stage-task), present to partner" [shape=box];
        "Partner commits or requests changes" [shape=diamond];
        "Uncapped partner fix round; ./scripts/impact for fan-out" [shape=box];
    }

    "Setup: worktree, ledger check, read plan, pre-flight review" [shape=box];
    "More tasks remain?" [shape=diamond];
    "Dispatch final code reviewer (../requesting-code-review/code-reviewer.md)" [shape=box];
    "Final findings? ONE fix dispatch, one scoped re-review, adjudicate residuals" [shape=box];
    "Express lane: stage all (./scripts/stage-task --all), partner commits once" [shape=box];
    "Final review clean: delete this plan's workspace" [shape=box];
    "Use superpowers:finishing-a-development-branch" [shape=box style=filled fillcolor=lightgreen];

    "Setup: worktree, ledger check, read plan, pre-flight review" -> "Dispatch READY set (./scripts/ready-set) in one message";
    "Dispatch READY set (./scripts/ready-set) in one message" -> "Dispatch implementer subagent (./implementer-prompt.md)";
    "Dispatch implementer subagent (./implementer-prompt.md)" -> "Implementer asks questions?";
    "Implementer asks questions?" -> "Answer questions, provide context" [label="yes"];
    "Answer questions, provide context" -> "Implementer implements, tests, self-reviews, reports";
    "Implementer asks questions?" -> "Implementer implements, tests, self-reviews, reports" [label="no"];
    "Implementer implements, tests, self-reviews, reports" -> "Generate review package, dispatch task reviewer (./task-reviewer-prompt.md)";
    "Generate review package, dispatch task reviewer (./task-reviewer-prompt.md)" -> "Spec ✅ and quality approved?";
    "Spec ✅ and quality approved?" -> "Append completion to ledger, mark todo complete" [label="yes"];
    "Spec ✅ and quality approved?" -> "Finding conflicts with plan text?" [label="no"];
    "Finding conflicts with plan text?" -> "Rule on the conflict, ledger the ruling" [label="yes"];
    "Rule on the conflict, ledger the ruling" -> "Fix round R of 5: R≤3 resume implementer; R≥4 fresh implementer, more capable model";
    "Finding conflicts with plan text?" -> "Fix round R of 5: R≤3 resume implementer; R≥4 fresh implementer, more capable model" [label="no"];
    "Fix round R of 5: R≤3 resume implementer; R≥4 fresh implementer, more capable model" -> "Dispatch scoped re-review (./re-review-prompt.md)";
    "Dispatch scoped re-review (./re-review-prompt.md)" -> "All findings addressed?";
    "All findings addressed?" -> "Append completion to ledger, mark todo complete" [label="yes"];
    "All findings addressed?" -> "R = 5?" [label="no"];
    "R = 5?" -> "Fix round R of 5: R≤3 resume implementer; R≥4 fresh implementer, more capable model" [label="no - next round"];
    "R = 5?" -> "Adjudicate each open finding" [label="yes - breaker trips"];
    "Adjudicate each open finding" -> "Any load-bearing finding?";
    "Any load-bearing finding?" -> "Rule and continue; stop only if every path forward is a guess" [label="yes"];
    "Any load-bearing finding?" -> "Park findings in ledger with rulings" [label="no"];
    "Park findings in ledger with rulings" -> "Append completion to ledger, mark todo complete";
    "Append completion to ledger, mark todo complete" -> "Park (./scripts/park-task); baton?";
    "Park (./scripts/park-task); baton?" -> "Wait: keep scheduling other tasks" [label="no"];
    "Park (./scripts/park-task); baton?" -> "Stage (./scripts/stage-task), present to partner" [label="yes"];
    "Stage (./scripts/stage-task), present to partner" -> "Partner commits or requests changes";
    "Partner commits or requests changes" -> "Uncapped partner fix round; ./scripts/impact for fan-out" [label="changes"];
    "Uncapped partner fix round; ./scripts/impact for fan-out" -> "Stage (./scripts/stage-task), present to partner";
    "Partner commits or requests changes" -> "More tasks remain?" [label="commits"];
    "Wait: keep scheduling other tasks" -> "More tasks remain?";
    "More tasks remain?" -> "Dispatch READY set (./scripts/ready-set) in one message" [label="yes"];
    "More tasks remain?" -> "Dispatch final code reviewer (../requesting-code-review/code-reviewer.md)" [label="no"];
    "Dispatch final code reviewer (../requesting-code-review/code-reviewer.md)" -> "Final findings? ONE fix dispatch, one scoped re-review, adjudicate residuals";
    "Final findings? ONE fix dispatch, one scoped re-review, adjudicate residuals" -> "Express lane: stage all (./scripts/stage-task --all), partner commits once" [label="express lane"];
    "Express lane: stage all (./scripts/stage-task --all), partner commits once" -> "Final review clean: delete this plan's workspace";
    "Final findings? ONE fix dispatch, one scoped re-review, adjudicate residuals" -> "Final review clean: delete this plan's workspace";
    "Final review clean: delete this plan's workspace" -> "Use superpowers:finishing-a-development-branch";
}
```

## Setup

Ensure the work happens in an isolated workspace: use
superpowers:using-git-worktrees to create one or verify the existing one.
Never start implementation on a main/master branch without your human
partner's explicit consent.

Conversation memory does not survive compaction. In real sessions,
controllers that lost their place have re-dispatched entire completed task
sequences — the single most expensive failure observed. Track progress in
a ledger file, not only in todos.

- Each plan owns a workspace: at skill start, run this skill's
  `scripts/sdd-workspace PLAN_FILE` — it prints the plan's git-ignored
  directory (`<repo-root>/.superpowers/sdd/<plan-basename>/`), home to
  every artifact for THIS plan: ledger, briefs, reports, review packages.
  Another plan's directory is never yours to read or write.
- Check for this plan's ledger at `<workspace>/progress.md`. If its first
  line names your plan file, tasks with a `Task <N>: complete` line are DONE
  — do not re-dispatch them; resume at the first task without one. A task
  whose last line is a fix round is mid-loop: resume the loop at the next
  round. A ledger whose first line names a different plan file — or a stray
  ledger at the old flat path `.superpowers/sdd/progress.md` — is another
  plan's progress: leave it in place and start your own, fresh.
- Create the ledger with its identity as the first line:
  `# SDD ledger — plan: <plan file path>`.
- After the pre-flight scan, write the graph block, then append one event line
  per event as it happens — never in a later batch. Parked work has no other
  identity, and a controller that batches these loses the file-to-stage
  mapping on compaction.

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

- The ledger is your recovery map, and under the commit gate it is the ONLY
  map: `git log` shows committed stages only, so parked work appears there not
  at all. After compaction, trust the ledger over your own recollection.
  Tasks with `committed` are done. Tasks with `parked` but no `committed` live
  in the working tree and at their snapshot ref — verify with
  `git status --porcelain` that the files the ledger attributes to them are
  still modified, and `scripts/restore-task` any the tree lost. Tasks with
  `dispatched` and no `returned` were lost mid-flight; re-dispatch them.
- `git clean -fdx` will destroy the workspace (it's git-ignored scratch) and
  every parked stage's working-tree content with it. Snapshot refs live in
  `.git` and survive: `git for-each-ref refs/superpowers/sdd/<plan-basename>`
  enumerates what was parked, and `scripts/restore-task` brings each back.

Read the plan once, note its context and Global Constraints, and create a
todo per task. If the plan names a Spec, read that too: the spec is the
authority the plan argues from, and conflicts inside the plan resolve
against it. A plan with no reachable spec gets a ledger note saying so —
rulings made without one are provisional.

Before dispatching Task 1, scan the plan once for conflicts, writing down
what you checked as you check it:

- tasks that contradict each other or the plan's Global Constraints
- anything the plan explicitly mandates that the review rubric treats as a
  defect (a test that asserts nothing, verbatim duplication of a logic block)

The scan's output is a table, not a verdict. One row for every pair of tasks
that share a file or an interface: the two tasks, what one produces against
what the other consumes, and what you found. One row for every task: whether
its own text agrees with itself — the tests it specifies against the code it
specifies, the files it creates against the files it later touches. "The scan
is clean" without those rows is not a scan you ran.

The scan also validates the graph. Run `scripts/ready-set PLAN_FILE` once
before dispatching anything: it exits 3 if any task lacks `Depends on:`,
`Files:`, or `Exclusive:`. Add one row per pair of tasks sharing a file —
those serialize on your partner's commits rather than running concurrently —
and one row per task whose `Consumes` names a symbol no declared dependency
`Produces`, which would otherwise be scheduled concurrently with the task
that defines it.

Write the table to the ledger. Rule on everything you find before execution
begins — each finding against the plan text that mandates it — and record
each ruling in the ledger. If the scan is clean, proceed without comment.
Rule on each conflict it surfaces — the spec is the binding authority, the
plan is its argument — record the ruling beside its row, and dispatch
Task 1. The review loop remains the net for conflicts that only emerge from
implementation.

## Model Selection

Use the least powerful model that can handle each role to conserve cost and increase speed.

**Mechanical implementation tasks** (isolated functions, clear specs, 1-2 files): use a fast, cheap model. Most implementation tasks are mechanical when the plan is well-specified.

**Integration and judgment tasks** (multi-file coordination, pattern matching, debugging): use a standard model.

**Architecture and design tasks**: use the most capable available model.
The final whole-branch review is one of these — dispatch it on the most
capable available model, not the session default.

**Review tasks**: choose the model with the same judgment, scaled to the
diff's size, complexity, and risk. A small mechanical diff does not need the
most capable model; a subtle concurrency change does. Scoped re-reviews of
small fix diffs take a cheap-to-mid tier.

**Fix-loop escalation (rounds 4-5)**: use a model at least one tier above
the implementer that got stuck.

**Always specify the model explicitly when dispatching a subagent.** An
omitted model inherits your session's model — often the most capable and
most expensive — which silently defeats this section.

**Turn count beats token price.** Wall-clock and context cost scale with how
many turns a subagent takes, and the cheapest models routinely take 2-3× the
turns on multi-step work — costing more overall. Use a mid-tier model as the
floor for reviewers and for implementers working from prose descriptions.
When the task's plan text contains the complete code to write, the
implementation is transcription plus testing: use the cheapest tier for
that implementer. Single-file mechanical fixes also take the cheapest tier.

**Task complexity signals (implementation tasks):**

- Touches 1-2 files with a complete spec → cheap model
- Touches multiple files with integration concerns → standard model
- Requires design judgment or broad codebase understanding → most capable model

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

| Edge                                | The successor waits until the predecessor is                                             |
| ----------------------------------- | ---------------------------------------------------------------------------------------- |
| Semantic (`Depends on:`)            | **review-clean** — NOT committed. It reads the predecessor's code from the working tree. |
| File collision (a shared path)      | **committed**                                                                            |
| Mutex (`kind:name` in `Exclusive:`) | **not running**                                                                          |

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

## The Commit Gate

You stage. Your human partner commits. **You never run `git commit`.**

The plan and the spec it came from are never staged and never committed. A
stage carrying either is the wrong stage — restage without them before you
present it.

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

### The express lane

Your partner may have chosen the express lane at superpowers:writing-plans'
handoff. It changes exactly one thing: **steps 3 and 4 above do not run.** There
is no baton, nothing is ever staged mid-run, and the commit pipeline never
stalls because there is no commit until the end.

Everything else is untouched. `ready-set` still schedules, implementers still
implement, task reviewers still review, the five-round breaker still trips and
still ends in an adjudicated ruling, the ledger still records every line, and
the four hard stops still stop you. Do not invent new reasons to interrupt: a
cap adjudication is a ledger entry here, not a check-in. Removing the baton also
removes the only thing that was throttling width — the graph now runs as wide as
`ready-set` allows for the whole run.

Step 2 stops being merely prudent and becomes the run's only memory. With no
intermediate commits, the park refs and the ledger are the entire history of
what happened; park on every agent return without exception.

The final review changes shape, because `MERGE_BASE..HEAD` is empty when nothing
has been committed. Use the whole-plan working-tree package instead:

```bash
scripts/review-package PLAN_FILE --plan "$(git merge-base main HEAD)"
```

When every task is review-clean and the final review is clean, stage the run
once and present it:

```bash
scripts/stage-task PLAN_FILE --all
```

`--all` refuses a dirty index for the same reason the single-task path does, and
it validates every task before staging any of it — a partial combined stage
reads to your partner as a finished plan and gets committed as one.

```text
Express lane complete: 5 tasks staged as one review.
Proposed:  feat(api): add user CRUD endpoints with validation

Task 1: Schema
  src/models/user.py   |  34 ++++
Task 2: API endpoints
  src/api/users.py     |  81 ++++++++
Task 3: Validation
  src/api/validate.py  |  47 +++++
...

Tests:    38/38 passing, output pristine
Review:   all tasks clean; final whole-branch review clean
Rulings:  2 — Task 3 interface widened; Task 5 test split. Ledger has both.

Review with `git diff --staged`. Commit when ready, or tell me what to change.
```

Surface every `Ruling:` from the ledger in that summary. In the normal gate your
partner meets each ruling as it lands and can overrule it while it is cheap;
here this is their first and only sight of them, so a ruling you leave out is a
ruling they never got to overrule. That is the trade they accepted, and it only
stays fair if you report it.

If they ask for changes, the fix loop below is unchanged and still uncapped:
restore the index, run their words through as findings, and re-stage with
`--all`.

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

## The Task Loop

**Batch small same-shape work.** When the plan lists several tasks that are
each a small, independent edit of the same kind — the same one-line fix,
constant change, or field addition repeated across files — do not dispatch
one subagent per task. Compose ONE dispatch brief listing every file and
its change, send the whole batch to a single subagent, and review its diff
as one unit. Reserve one-dispatch-per-task for work that needs its own
judgment, its own tests, or its own review surface.

Everything you paste into a dispatch prompt — and everything a subagent
prints back — stays resident in your context for the rest of the session
and is re-read on every later turn. Hand artifacts over as files.

**Waiting on dispatched subagents:** never poll a wait interface with
short timeouts, and never sit in one silent, open-ended wait either.
While you have local work — ledger updates, packaging the next review,
reading reports — keep working; child results arrive on their own.
When you are genuinely idle, wait in bounded stretches (five to ten
minutes, where your platform allows), and between stretches post one
line of status and reconcile your live children: list them, and chase
any that finished without reporting. A bounded stretch keeps nearly
all of a long wait's efficiency while guaranteeing a stuck or lost
child is noticed within minutes, not at the end of the session.

### 1. Dispatch the implementer

Record nothing before dispatching: per-task diffs come from the declared file
list, not from a commit range. `scripts/review-package --task N` derives them.

- **Task brief:** before dispatching an implementer, run this skill's
  `scripts/task-brief PLAN_FILE N` — it extracts the task's full text to a
  uniquely named file and prints the path. Compose the dispatch so the
  brief stays the single source of
  requirements. Your dispatch should contain: (1) one line on where this
  task fits in the project; (2) the brief path, introduced as "read this
  first — it is your requirements, with the exact values to use verbatim";
  (3) interfaces and decisions from earlier tasks that the brief cannot
  know; (4) your resolution of any ambiguity you noticed in the brief;
  (5) the report-file path and report contract. Exact values (numbers,
  magic strings, signatures, test cases) appear only in the brief. Never
  make a subagent read the whole plan file.
- **Report file:** name the implementer's report file after the brief
  (brief `…/task-N-brief.md` → report `…/task-N-report.md`) and put it in
  the dispatch prompt. The implementer writes the full report there and
  returns only status, commits, a one-line test summary, and concerns.
- A dispatch prompt describes one task, not the session's history. Do not
  paste accumulated prior-task summaries ("state after Tasks 1-3") into
  later dispatches — a real session's dispatch hit 42k chars of which 99%
  was pasted history. A fresh subagent needs its task, the interfaces it
  touches, and the global constraints. Nothing else.
- The dispatch carries the no-subagents contract (it is in the
  implementer template): the implementer never dispatches subagents —
  not helpers, and never a reviewer. Review arrives from you, after the
  report. In real sessions, every reviewer a worker spawned duplicated
  the task review the controller dispatched anyway — a full extra
  review seat per task.
- If an earlier task parked a finding in the area this task touches, carry
  a pointer to that ledger entry in the dispatch.
- Record the implementer's agent identity from the dispatch result —
  fix-loop rounds 1-3 resume this agent.
- Dispatch the whole READY set from `scripts/ready-set` in ONE message so they
  run concurrently. Never dispatch a task `ready-set` did not name.

Template: [implementer-prompt.md](implementer-prompt.md)

### 2. Handle the report

Implementer subagents report one of four statuses. Handle each appropriately:

**DONE:** Park the work (`scripts/park-task PLAN_FILE N`), then generate the review package (`scripts/review-package PLAN_FILE --task N`, from this skill's directory — it prints the unique file path it wrote), then dispatch the task reviewer with the printed path. The package is scoped to the task's declared files, so a concurrently running implementer's edits never enter this review.

**DONE_WITH_CONCERNS:** The implementer completed the work but flagged doubts. Read the concerns before proceeding. If the concerns are about correctness or scope, address them before review. If they're observations (e.g., "this file is getting large"), note them and proceed to review.

**NEEDS_CONTEXT:** The implementer needs information that wasn't provided. Provide the missing context and re-dispatch.

**BLOCKED:** The implementer cannot complete the task. Assess the blocker:

1. If it's a context problem, provide more context and re-dispatch with the same model
2. If the task requires more reasoning, re-dispatch with a more capable model
3. If the task is too large, break it into smaller pieces
4. If the plan itself is wrong, rule on the correction, ledger it, and re-dispatch with the ruling carried in the dispatch

**Never** ignore an escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.

If the implementer asks questions — before starting or mid-task — answer
clearly and completely, provide additional context if needed, and don't
rush it into implementation.

### 3. Review the task

Per-task reviews are task-scoped gates. The broad review happens once, at the
final whole-branch review. Never skip the task review, and never accept a
report missing either verdict — spec compliance AND task quality are both
required. Implementer self-review never replaces the task review; both are
needed.

- Hand the reviewer its diff as a file: run this skill's
  `scripts/review-package PLAN_FILE BASE HEAD` and pass the reviewer the file path
  it prints (or, without bash: `git log --oneline`, `git diff --stat`,
  and `git diff -U10` for the range, redirected to one uniquely named
  file). The output never enters your own context, and the reviewer sees
  the commit list, stat summary, and full diff with context in one Read
  call. Use the BASE you recorded before dispatching the implementer —
  never `HEAD~1`, which silently truncates multi-commit tasks. Never
  dispatch a task reviewer without a diff file.
- **Reviewer inputs:** the task reviewer gets three paths — the same brief
  file, the report file, and the review package — plus the global
  constraints that bind the task.
- The global-constraints block you hand the reviewer is its attention
  lens. Copy the binding requirements verbatim from the plan's Global
  Constraints section or the spec: exact values, exact formats, and the
  stated relationships between components ("same layout as X", "matches
  Y"). The reviewer's template already carries the process rules (YAGNI,
  test hygiene, review method) — the constraints block is for what THIS
  project's spec demands.
- Do not add open-ended directives like "check all uses" or "run race tests
  if useful" without a concrete, task-specific reason
- Do not ask a reviewer to re-run tests the implementer already ran on the
  same code — the implementer's report carries the test evidence
- Do not pre-judge findings for the reviewer — never instruct a reviewer to
  ignore or not flag a specific issue. If you believe a finding would be a
  false positive, let the reviewer raise it and adjudicate it in the review
  loop. If the prompt you are writing contains "do not flag," "don't treat X
  as a defect," "at most Minor," or "the plan chose" — stop: you are
  pre-judging, usually to spare yourself a review loop.
  The task reviewer may report "⚠️ Cannot verify from diff" items — requirements
  that live in unchanged code or span tasks. These do not block the rest of the
  review, but you must resolve each one yourself before marking the task
  complete: you hold the plan and cross-task context the reviewer
  lacks. If you confirm an item is a real gap, treat it as a failed spec
  review — it enters the fix loop with the other findings.

Template: [task-reviewer-prompt.md](task-reviewer-prompt.md)

### 4. The fix loop

The loop triggers when the review reports spec ❌, any Critical or Important
finding, or a ⚠️ item you confirmed as a real gap.

Before the loop starts, two routes leave it immediately:

- Record Minor findings in the progress ledger as you go
  (`Task <N>: minor (deferred): <one-liner>`), and point the final
  whole-branch review at that list so it can triage which must be fixed
  before merge. A roll-up nobody reads is a silent discard. Minor findings
  never enter the loop.
- A finding labeled plan-mandated — or any finding that conflicts with
  what the plan's text requires — is yours to rule on: weigh the finding
  against the plan text, decide with the spec as the binding authority, and
  ledger the ruling before you act on it. Do not dismiss the finding because
  the plan mandates it, and do not dispatch a fix that contradicts the plan
  without a recorded ruling.
  Everything else enters the loop. A fix round is one fix dispatch plus one
  scoped re-review. Five rounds maximum per task:

**Rounds 1-3 — resume the original implementer.** Send it the open findings
verbatim. Its context is intact: it knows the task, the code, and its own
choices. If your harness cannot send another message to a live subagent,
dispatch a fresh implementer carrying the brief path, the report-file path,
and the findings — the report file is the persistent memory either way.

**Rounds 4-5 — dispatch a fresh implementer on a more capable model** (per
Model Selection), with the brief path, the report-file path, the open
findings, and this framing: "A prior implementer attempted this task
[N] times; you own it now. Read the report file for what was tried." A loop
that survives three resumes usually means the implementer cannot see its
own problem — fresh eyes and a capability bump in one move.

**Every round, either way:** the implementer fixes, re-runs the tests
covering the amended code, appends its fix report to the same report file,
and returns the short contract. Before re-dispatching the reviewer, confirm
the fix report contains the covering tests, the command run, and the
output; dispatch the re-review once all three are present. Name the
covering test files in the fix message — a one-line fix does not need the
whole suite.

**The re-review is scoped.** Park the fix (`scripts/park-task PLAN_FILE N`),
run `scripts/review-package PLAN_FILE --task N --since-park` — which diffs
against the state the previous review saw — and dispatch
[re-review-prompt.md](re-review-prompt.md) with the findings list, the
brief, the report file, and the printed diff path. The re-reviewer verdicts
each finding ADDRESSED or NOT ADDRESSED and flags new breakage in the fix
diff only. New Critical/Important breakage in the fix diff joins the open
findings list. Out-of-scope observations go to the ledger as deferred
minors — they never extend the loop.

**After each round,** append to the ledger:
`Task <N>: fix round <R>/5 (<X> addressed, <Y> open — <finding one-liners>; commits <a7>..<b7>)`

Never fix findings yourself in the controller session — your context stays
clean for coordination, and controller fixes skip review.

**The breaker.** When round 5's re-review still leaves findings open, stop
dispatching. Adjudicate each open finding yourself — you hold the plan and
the cross-task context the reviewer lacks:

- **The reviewer is wrong, or the point is contestable:** park it —
  `Task <N>: parked — <finding> — Ruling: <why the code stands>`. The final
  review sees both sides.
- **Real, but nothing downstream builds on it:** park it the same way, with
  a ruling that says it's real and deferred.
- **Real and load-bearing** — a later task builds on it, or it reveals a
  plan defect: rule on the smallest change that unblocks the dependent work,
  ledger it as `Task <N>: Ruling: <finding> — <what you decided and why>`,
  and carry it into the next task's dispatch. Parking a structural failure
  silently lets every dependent task build on it. Stop only when the defect
  leaves every path forward a guess.

Adjudicate only at the cap. Adjudicating earlier to end a loop is
pre-judging with a different name. Every adjudication is a ledger entry —
a silent discard is forbidden.

### 5. Complete the task

When the review comes back clean — or every open finding is parked with a
ruling at the cap — append the completion line to the ledger in the same
message as your other bookkeeping:

- `Task <N>: complete (commits <base7>..<head7>, review clean)`
- `Task <N>: complete (commits <base7>..<head7>, <K> parked)` after a
  tripped breaker

Then mark the todo complete and move on. Never move to the next task while
the review has open Critical/Important issues that are neither fixed nor
parked-with-ruling at the cap.

## Final Review

The final whole-branch review gets a package too: run
`scripts/review-package PLAN_FILE MERGE_BASE HEAD` (MERGE_BASE = the commit the
branch started from, e.g. `git merge-base main HEAD`) — or, in the express lane,
`scripts/review-package PLAN_FILE --plan MERGE_BASE`, because a run that has
committed nothing has an empty commit range — and include the
printed path in the final review dispatch, so the final reviewer reads
one file instead of re-deriving the branch diff with git commands. Dispatch
on the most capable available model (see Model Selection), using
superpowers:requesting-code-review's
[code-reviewer.md](../requesting-code-review/code-reviewer.md). Point it at
the ledger's deferred-minor and parked lines so it can triage which must be
fixed before merge.

If the final whole-branch review returns findings, dispatch ONE fix subagent
with the complete findings list — not one fixer per finding.
Per-finding fixers each rebuild context and re-run suites; a real
session's final-review fix wave cost more than all its tasks combined.
The fix wave is uncommitted work like any stage: stage it
(`git add -A -- . ":(exclude)$PLAN_FILE" ":(exclude)docs/superpowers/specs"` —
a bare `git add -A` sweeps the plan and spec into your partner's commit),
present it to your human partner as the final stage, and once
they commit it run exactly one scoped re-review of that commit range
(`scripts/review-package PLAN_FILE FIX_BASE HEAD`, where FIX_BASE is the
commit before theirs — by this point every stage is committed, so the
commit-range mode is the right one, [re-review-prompt.md](re-review-prompt.md)).
Adjudicate any residual findings as in the task loop's breaker: park with
rulings, or rule on the load-bearing ones and ledger what you decided. Only
the four classes above stop you here. There is no second fix wave —
residual load-bearing findings surface to your human partner when
finishing-a-development-branch presents the options.

## Finish

Before you delete anything, collect every ledger line containing `Ruling:` —
preflight rulings, parked findings, breaker adjudications, all of them — into
your final message under "Rulings I made", in the order you made them, each
with what it costs if wrong. The list is exhaustive: if the ledger holds a
ruling, the list holds it. That list is the only place the decisions you
took on your human partner's behalf reach them — they read it and rework
whatever you got wrong. A ruling that dies with the workspace was a decision
made in secret.

When the final whole-branch review is clean and its fixes are merged, delete
this plan's workspace (`rm -rf <workspace>`) and its snapshot refs
(`git for-each-ref --format='%(refname)' refs/superpowers/sdd/<plan-basename> |
xargs -r -n1 git update-ref -d`) — the git history is the record now. Sibling
directories and other plans' refs are not yours; leave them alone.

Use superpowers:finishing-a-development-branch.

## Common Rationalizations

| Excuse                                                            | Reality                                                                                                                                      |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| "Express lane means I can commit it myself"                        | It collapses how many gates your partner holds, never who holds them. You stage; they commit. Always.                                        |
| "Nothing stalls in the express lane, so parking is busywork"       | With no intermediate commits, the park refs and the ledger are the run's entire history. Park on every return.                               |
| "I'll summarize the rulings rather than list them"                 | The express lane is their only sight of every ruling. A ruling you compress out is one they never got to overrule.                            |
| "Close enough on spec compliance"                                 | Reviewer found spec gaps = not done. Fix or hit the cap and adjudicate — those are the only exits.                                           |
| "I'll fix it myself, dispatching is overhead"                     | Controller fixes pollute your context and skip review. Resume the implementer.                                                               |
| "One more round will converge"                                    | Past the cap, rounds don't converge — the failure is structural. Adjudicate and route.                                                       |
| "The reviewer will just find something new anyway"                | Scoped re-reviews verify fixes; they cannot wander. New findings on untouched code go to the ledger, not the loop.                           |
| "This finding is obviously wrong, I'll drop it"                   | You adjudicate only at the cap, and every ruling is a ledger entry. Silent discards are forbidden.                                           |
| "The fix was small, skip the re-review"                           | Unreviewed fixes are how regressions land. Every round ends with a scoped re-review.                                                         |
| "Reviews slow the loop down"                                      | The loop without reviews is just unverified churn. Reviews are the loop's brakes and steering.                                               |
| "Ledger bookkeeping is overhead"                                  | The ledger is what survives compaction. Controllers without one have re-dispatched entire completed task sequences.                          |
| "The implementer spawned its own reviewer — free extra assurance" | It's a duplicate seat reviewing the same diff; the task review is the gate. A worker-spawned reviewer is a defect to flag, not rigor.        |
| "I'll commit this stage myself to keep moving"                    | Commits belong to your human partner. You stage; they commit.                                                                                |
| "These two stages look independent, I'll run them together"       | `ready-set` decides that, not your reading of the plan. An undeclared shared file is a silent lost write, not a merge conflict you'd notice. |
| "The partner is slow, I'll stage the next stage too"              | Two stages in the index destroys the review surface. One stage holds the index until it is committed.                                        |
| "Parking is bookkeeping — the files are right there in the tree"  | Dirty files have no identity. After a compaction, the ledger and the snapshot ref are the only things that know which files are whose.       |
| "The fix was tiny, downstream is obviously fine"                  | Run `scripts/impact`. If it touches the `Produces` surface, downstream is affected whether it looks obvious or not.                          |
| "An unrelated test broke, I'll have someone fix it"               | Another agent is mid-edit in this tree. Unrelated breakage is an observation for the ledger, not a fix dispatch.                             |
| <<TODO-PARTNER: the rationalization for staging the plan>>        | <<TODO-PARTNER: the reality>>                                                                                                               |

## Example Workflow

```
You: I'm using Subagent-Driven Development to execute this plan.

[Setup: worktree verified]
[Read plan file once: docs/superpowers/plans/feature-plan.md]
[Resolve workspace: scripts/sdd-workspace docs/superpowers/plans/feature-plan.md — no ledger inside, fresh start]
[Pre-flight scan clean; scripts/ready-set validates the graph; graph block written to ledger]
[Create todos for all tasks]

[scripts/ready-set → BATON: 1 | READY: 1 5 6]
[Run task-brief for 1, 5 and 6; dispatch all three implementers in ONE message]

Implementer 1: "Before I begin - should the hook be installed at user or system level?"
You: "User level (~/.config/superpowers/hooks/)"

Implementer 5: [returns first]
  Status: DONE
  Files touched: web/settings.tsx, web/settings.test.tsx
  Proposed commit message: feat(web): add settings page
  4/4 passing, output pristine

[scripts/park-task PLAN 5]
[Ledger: Task 5: returned DONE files=web/settings.tsx,web/settings.test.tsx msg="feat(web): add settings page"]
[Ledger: Task 5: parked ref=refs/superpowers/sdd/feature-plan/task-5]
[Run review-package PLAN --task 5; dispatch task reviewer]
Task reviewer: Spec ✅. Produces verified ✅. Task quality: Approved.
[Ledger: Task 5: review clean (Produces verified ✅)]
[Ledger: Task 5: waiting (baton at 1)]   ← clean, but NOT staged: task 1 holds the baton

Implementer 1: [Later]
  Status: DONE
  Files touched: src/install-hook.js, test/install-hook.test.js
  Proposed commit message: feat: add install-hook command
  5/5 passing, output pristine

[park-task 1; review-package --task 1; task reviewer → Spec ✅, Produces ✅, Approved]
[Ledger: Task 1: review clean (Produces verified ✅)]
[scripts/stage-task PLAN 1]

  Stage 1 of 8 staged: Hook installation script
  Proposed:  feat: add install-hook command

    1 ▸ STAGED — your review    5 ● parked   (settings page)
    2 ○ blocked (dep: 1)        6 ◐ running  (profile page)

  Downstream if you reject:  2 · stages 5, 6 unaffected
  Review with `git diff --staged`. Commit when ready, or tell me what to change.

[While waiting: implementer 6 returns, is parked, reviewed clean, and waits.
 The index is untouched — it belongs to stage 1.]

Partner: "Rename installHook to installUserHook, then it's good."

[git restore --staged -- src/install-hook.js test/install-hook.test.js]
[Partner fix round 1: resume implementer 1 with the finding verbatim]
Implementer 1: Renamed. Re-ran test/install-hook.test.js — 5/5 passing.
[park-task 1; review-package PLAN --task 1 --since-park; scoped re-review → ADDRESSED]
[scripts/impact PLAN 1 <fix diff> → AFFECTED: 2   (installHook is in task 1's Produces)]
[Ledger: Task 1: partner fix round 1 (1 addressed, 0 open)]
[Task 2 not yet dispatched, so nothing to re-verify — it will be briefed with the new name]
[stage-task 1; re-present]

Partner: [commits 4f3a91c]

[Ledger: Task 1: committed 4f3a91c]
[scripts/ready-set → BATON: 2 | READY: 2 | PARKED: 5 6]
[Stages 5 and 6 stay parked: the baton is 2, and plan order is commit order]
[Dispatch implementer 2 with the amended interface in its brief]

...

[After every stage is committed]
[Run review-package PLAN MERGE_BASE HEAD; dispatch final code-reviewer, most capable model]
Final reviewer: All requirements met. Deferred minors triaged: none block merge.

[Delete this plan's workspace and its snapshot refs — the record now lives in git]

Done! Using superpowers:finishing-a-development-branch.
```
