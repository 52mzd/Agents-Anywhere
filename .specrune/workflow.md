# Development Workflow

This document defines how a development session runs in this repository. It is
read by the AI at session start and parsed by tooling for the per-turn state
breadcrumb. Change it deliberately — the blocks below are load-bearing.

## Core Principles

1. **Specs before code.** Spec files under `.specrune/spec/` describe how this project
   does things. Read the relevant ones before writing code that touches them.
2. **One active task at a time.** Work is scoped to a task. The per-turn
   breadcrumb reports which one, and its state decides what happens next.
3. **Artifacts are the handoff.** Requirements, design and plan live in the task
   directory as markdown. They are the contract between planning and execution.
4. **Context is curated, not dumped.** Sub-agents receive exactly the spec and
   research files listed in their jsonl manifest. Adding a file to a manifest is
   a deliberate act.

## SpecRune System

### Developer Identity

`.specrune/.developer` holds your name and is gitignored — identity is per person,
not per project. In a linked git worktree the file is read from the main
checkout, so `git worktree add` does not lose it.

Override with the `TRELLIS_DEVELOPER` environment variable. Tasks record both a
`creator` and an `assignee`; assignee defaults to you.

### Spec System

```
.specrune/spec/<package>/<layer>/index.md    spec entry point for one layer
.specrune/spec/guides/index.md               cross-cutting thinking guides
```

Spec files are plain markdown with no frontmatter. A file named `index.md` is an
entry point and may carry a `## Guidelines Index` table linking to sibling files;
those links are followed when the index is injected.

Package is omitted in a single-repo project. Declare `packages:` in
`config.yaml` to scope specs per package in a monorepo.

### Task System

```
.specrune/tasks/<MM-DD-slug>/
  task.json          metadata (status, assignee, parent/children, branch)
  prd.md             requirements and acceptance criteria
  design.md          technical design          (complex tasks)
  implement.md       execution plan            (complex tasks)
  implement.jsonl    context manifest for the implement sub-agent
  check.jsonl        context manifest for the check sub-agent
  research/          research output
.specrune/tasks/archive/<YYYY-MM>/...            archived tasks
```

`implement.jsonl` and `check.jsonl` are seeded empty on sub-agent-capable
platforms and curated during planning: one JSON object per line,
`{"file": "<path>", "reason": "<why>"}`. Spec and research documents only —
never code paths.

### Session Records

```
.specrune/sessions/<id>.md     one authoritative record per session
```

Each finished session writes its own file. The record is the authoritative
memory of what happened, written at the end of a session. It is not a changelog
of code — that is what git history is for. Read it back with
`specrune session log`. Legacy `workspace/<developer>/` journals and indexes
are migrated into these records by `specrune import`; the runtime reads
records only, and no index file is generated.

### Active Task

The active task is a **session-scoped pointer**, stored at
`.specrune/.runtime/sessions/<context-key>.json`. The context key is derived from the
platform and that session's own id.

There is no fallback and no guessing. If a session has no identity, it has no
active task, and every command says so plainly. Inferring "the active task"
from how many session files happen to exist is how a session ends up writing to
another session's task.

## Phase Index

The three phases below are the whole workflow. Each has a step list; steps
marked `[required]` are gates, the rest are tool calls you reach for when the
task needs them.

### Request Triage

Not every request is a task. Fix a typo, answer a question, adjust a comment —
just do it. Create a task when the work has requirements worth writing down and
an outcome someone can accept or reject.

### Planning Artifacts

A lightweight task can stay PRD-only. Add `design.md` when there is a real
technical decision to make, and `implement.md` when execution needs an ordered
plan. Adding an artifact you will not use is worse than not adding it.

### Parent / Child Task Trees

A task that is too large to finish in one session becomes a parent with child
tasks. Children are full tasks: they get their own directory, their own
artifacts, their own manifest. The parent tracks progress and nothing else.

<!-- Per-turn breadcrumb: no active task (before Phase 1) -->
```
[workflow-state:no_task]
No active task. Unclear scope or a new feature: load the specrune-brainstorm
skill first — a task needs a real slug and description, so do not create one from
a guess. Otherwise, if this request is task-shaped, start Phase 1:
  specrune task create "<title>" --slug <ascii-slug> --description "<what it delivers>"
Simple questions, typo fixes, one-off edits: just do them.
Do not invent a task to look busy.
[/workflow-state:no_task]
```

<!-- Per-turn breadcrumb: subagent session without its own task pointer -->
```
[workflow-state:delegated]
You are a subagent session: your task context arrives in the curated prompt,
not via a session pointer. Do not create, start, finish, or set the status of
tasks - that belongs to the main session. If reality contradicts this block,
report the mismatch to the main session and continue your assigned work. Do
not invent a task to fix it.
[/workflow-state:delegated]
```

### Phase 1: Plan

Understand the request, write it down, gather the context the executor will
need, then activate the task.

<!-- Per-turn breadcrumb: Phase 1 (status='planning') -->
```
[workflow-state:planning]
Phase 1 — Plan. Active task: {task}
Step 1.1 requirement exploration — load the specrune-brainstorm skill. Write prd.md
with checkable acceptance criteria; add design.md for real technical decisions.
Step 1.3 curate implement.jsonl / check.jsonl (specrune task add-context), or the
sub-agents run with no spec context at all. Step 1.4 activates with specrune task start.
Full text of any step: specrune context --mode phase --step N.N
Do not write implementation code in this phase.
[/workflow-state:planning]
```

<!-- Per-turn breadcrumb: Phase 1 with codex.dispatch_mode=inline -->
```
[workflow-state:planning-inline]
Phase 1 — Plan (inline mode). Active task: {task}
Step 1.1 — load the specrune-brainstorm skill; fill prd.md, add design.md when needed.
Inline mode reads spec files directly instead of via jsonl manifests, but still
curate the manifests at step 1.3. Step 1.4 activates with specrune task start.
Full text of any step: specrune context --mode phase --step N.N
Do not write implementation code in this phase.
[/workflow-state:planning-inline]
```

### Phase 2: Execute

Implement against the specs and the plan, then check the result against both.

<!-- Per-turn breadcrumb: Phase 2/3 (status='in_progress') -->
```
[workflow-state:in_progress]
Phase 2 — Execute. Active task: {task}
Step 2.1 — load the specrune-before-dev skill, then dispatch the specrune-implement
agent. If its context lacks something, add it to implement.jsonl and re-dispatch;
never paste spec into the prompt by hand, the next dispatch will not have it.
Step 2.2 dispatch the specrune-check agent and fix what it finds.
When the check passes, run specrune task finish to enter Phase 3.
Full text of any step: specrune context --mode phase --step N.N
[/workflow-state:in_progress]
```

<!-- Per-turn breadcrumb: Phase 2/3 with codex.dispatch_mode=inline -->
```
[workflow-state:in_progress-inline]
Phase 2 — Execute (inline mode). Active task: {task}
Load the specrune-before-dev skill, then do steps 2.1 and 2.2 yourself in this
session — no sub-agents. Inline mode reads spec files directly rather than from
implement.jsonl / check.jsonl; run the project's lint and tests as the check pass.
When it passes, run specrune task finish to enter Phase 3.
Full text of any step: specrune context --mode phase --step N.N
[/workflow-state:in_progress-inline]
```

### Phase 3: Finish

Verify, update the specs that the change made stale, commit, and archive.

<!-- Per-turn breadcrumb: Phase 3 (status='completed') -->
```
[workflow-state:completed]
Phase 3 — Finish. Active task: {task}
Step 3.2 spec update — load the specrune-update-spec skill. Read the target spec
file before editing it (a duplicate section is worse than a missing one), and skip
typo-level changes: that noise buries the real updates.
Step 3.3 commit code and spec updates together.
Step 3.4 verify every acceptance criterion in prd.md, then: specrune task archive <task>
Full text of any step: specrune context --mode phase --step N.N
[/workflow-state:completed]

[workflow-state:canceled]
Task {task} was canceled — abandoned, not finished. There is no wrap-up to do, and
it must not be flipped back to completed: that would erase the record of why.
To look at it: specrune task show <task>. To close the record: specrune task archive <task>.
To pick it up again: specrune task start <task> — it flips the status back to in_progress
and records the pickup in notes, nothing to undo by hand. It does not know how far you
got, so say so: specrune task set-status <task> in_progress --note "进度到哪一步"
[/workflow-state:canceled]
```

### Rules

- One active task per session. Switching tasks is `task start`, not a second pointer.
- Archive before starting something unrelated. A task tree full of finished work
  is a task tree nobody reads.
- Keep each task's title and description filled in — create refuses blanks, and
  task validate flags an empty record.

### Active Task Routing

Commands take a task by name, by relative path, or by full path:

```
specrune task start my-task                        # suffix match, must be unique
specrune task start .specrune/tasks/01-31-my-task   # exact
specrune task start /abs/path/.specrune/tasks/...   # absolute
```

A bare name that matches more than one task is a failure, not a coin flip.
Pass the full directory name.

### Guardrails

- Task references are confined to `.specrune/tasks/`. A reference that resolves
  outside it is rejected — including one already written into a session file by
  an older tool version.
- Session pointers are never inferred. No identity means no active task.
- Writes are atomic (temp file + rename). A crash mid-write leaves the previous
  content intact rather than a truncated file.

### Loading Step Detail

This file carries the index and the phase summaries. The full body of a single
step is loaded on demand:

```bash
specrune context --mode phase --step 1.1
```

## Phase 1: Plan

#### 1.0 Create task `[required · once]`

```bash
specrune task create "<title>" --slug <ascii-slug> --description "<what this task delivers>"
```

A task is a commit point: once it exists, the rest of this phase has somewhere
to write its conclusions.

Binding it to this session is best-effort, not part of this step. When a session
identity is available, creating a task also points the breadcrumb at
`[workflow-state:planning]`; run from a bare shell (no session identity) or with
`--no-start` and nothing is bound — the task is still created, and step 1.4 binds
it. Do not check for a bound task to find out whether you are in Phase 1.

#### 1.1 Requirement exploration `[required · repeatable]`

Read the request against the codebase before writing requirements. The goal is
to find the parts of the request that are underspecified — those are where the
implementation will guess, and guesses are where rework comes from.

Write findings into `prd.md`, using the six sections the
`specrune-brainstorm` skill defines:

- **Goal** — one paragraph, what changes for the user.
- **Confirmed Facts** — what you verified against the codebase, with file:line
  anchors; drop facts that do not bear on the change.
- **Requirements** — what must be true when this is done.
- **Acceptance Criteria** — how someone else verifies it. Checkable boxes, not
  adjectives.
- **Out of Scope** — what this change deliberately leaves out.
- **Open Questions** — decisions still owed by the user; empty before
  `task start`.

#### 1.2 Research `[optional · repeatable]`

Dispatch a research sub-agent when any of these trigger lines is met:

- The investigation is expected to span five or more files, or needs to
  reconstruct the shape of a large subsystem or historical module.
- The answer lives outside this repository (dependency behavior, external APIs,
  protocol docs) and the conclusion affects the requirements.
- The reading itself would crowd out the main session's context — the kind of
  reading whose details are no longer needed once the conclusions are written
  down.

Research output goes to `research/*.md` and is cited from a manifest. Research
describes what exists; it does not recommend changes. Every report opens with
an evidence card — status (VERIFIED / INCONCLUSIVE / NOT_FOUND), the sources
it rests on, and the git revision it was written against.

A question too large for one pass — many files, many hops between them — is
split into smaller questions with one research agent each; they may run in
parallel. Three deep passes over the parts beat one shallow pass over the
whole.

Before each dispatch, record what the sub-agent is handed:
`specrune dispatch <slug>` writes a dispatch slip
(`.dispatch/<slug>.json`) listing the compiled inputs and the git
revision — the ledger the report's evidence card answers to.

#### 1.3 Configure context `[required · once]`

Curate `implement.jsonl` and `check.jsonl` — one JSON object per line:

```json
{"file": ".specrune/spec/<pkg>/<layer>/index.md", "reason": "conventions for the code being changed"}
```

Spec and research documents only. A manifest with no real entries means every
sub-agent runs with zero spec context, and `task start` refuses to activate such a
task unless you pass `--allow-empty-context`.

List what is available:

```bash
specrune packages
specrune specs
```

#### 1.4 Activate task `[required · once]`

```bash
specrune task start <task>
```

Ask the user before running this. Activation is where the plan stops being a draft:
`task start` flips the status and binds the pointer, so anything the user wanted
changed in `prd.md` has to be settled first. Show the slug, the goal and the
acceptance criteria, wait for a yes, then run it.

This binds the task to this session, flips `planning` → `in_progress`, and records
the checked-out branch. The breadcrumb moves to `[workflow-state:in_progress]`.

#### 1.5 Completion criteria

Phase 1 is done when `prd.md` has checkable acceptance criteria, `design.md` exists
if there was a real design decision, both manifests have real entries, and the
task is activated. Anything short of that means Phase 2 starts by guessing.

## Phase 2: Execute

#### 2.1 Implement `[required · repeatable]`

Dispatch the implement sub-agent with the task's prompt. It receives the curated
manifests plus `prd.md`, `design.md` and `implement.md`.

The implement agent modifies code and does not commit. If the injected context is
missing something it needs, add it to `implement.jsonl` and re-dispatch — do not
paste the spec into the prompt by hand, because the next dispatch will not have
it.

#### 2.2 Quality check `[required · repeatable]`

Dispatch the check sub-agent. It compares the working tree against the specs and
fixes what it finds rather than only reporting it.

The check pass reads `check.jsonl`, which is a different list from
`implement.jsonl` on purpose: implementation needs conventions, verification needs
the contracts those conventions are supposed to satisfy.

#### 2.3 Rollback `[on demand]`

If an approach turns out to be wrong, discard the changes and re-plan. Do not
layer a correction on top of a wrong shape — the result reads as intentional.

## Phase 3: Finish

#### 3.1 Debug retrospective `[on demand]`

If this task cost more than it should have, write down why while it is still
fresh. A retrospective that names a specific cause ("the spec said X but the code
did Y") is worth keeping; one that says "more testing needed" is not.

#### 3.2 Spec update `[required · once]`

If this change introduced a pattern, contract or convention that the specs do not
describe, update them now. Read the target spec file before editing it — a
duplicate section is worse than a missing one.

Skip this for changes that introduce nothing new. Updating specs for a typo fix
is noise that makes the real spec changes harder to find.

#### 3.3 Commit changes `[required · once]`

Commit the code and the spec updates together. A spec change without the code it
describes cannot be reviewed.

#### 3.4 Wrap-up reminder

Verify every acceptance criterion in `prd.md` before archiving. Then:

```bash
specrune task archive <task>
```

Archive flips the status to `completed`, unlinks children, clears the session
pointers aimed at it, moves the directory to `.specrune/tasks/archive/<YYYY-MM>/`,
and commits. Two details are deliberate: a `canceled` task keeps its status and
its empty completion date (archiving it as finished would erase the record of
why), and an already-set `completedAt` is never overwritten — that date is the
day the work finished, not the day it was filed away.

## Customizing the Workflow

This file is yours. The parser depends on the structure described at the top of
this document — the `## Phase Index` heading, the `[workflow-state:*]` blocks, and
`#### N.M` step headings. Everything else is prose you can rewrite to match how your
team actually works.
