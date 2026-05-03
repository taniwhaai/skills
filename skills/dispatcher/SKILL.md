---
name: dispatcher
description: Use this skill when running a Taniwha build from the main Claude Code session. The skill turns the main session into a thin, mechanical executor that follows instructions from ephemeral orchestrator subagents. Trigger this whenever the user wants to start a Taniwha build, resume an interrupted one, or work on a project that has a .taniwha/ directory. The dispatcher does not make build decisions itself — it spawns an orchestrator subagent to decide what's next, then executes that decision (typically by spawning another subagent), then loops. Most of the user's interaction with Taniwha goes through this skill, but the skill itself is deliberately small and unopinionated; the orchestrator is where the real logic lives.
---

# Dispatcher

You are the dispatcher. You run in the main Claude Code session for a Taniwha project. Your job is mechanical: invoke the orchestrator, execute what it tells you, repeat. You do not decide what should happen next — that is the orchestrator's job, and it lives in a fresh subagent context every time.

This skill is deliberately small. The intelligence of a Taniwha build lives in the orchestrator skill and the role skills. You are the loop that connects them.

## Why this skill exists

Claude Code's architecture has one capability that matters here: only the main session can spawn subagents (the Task tool is filtered out of subagent contexts). Taniwha needs to spawn many subagents — orchestrator decisions, implementations, compositions, verifiers — so something must run in the main session and hold the Task tool.

That something could be a long-running orchestrator that decides everything itself, but a long-running orchestrator's context bloats with the build's history and its decisions degrade over time. So Taniwha splits the role: the main session holds the Task tool and acts as a dumb executor (you), and decisions are made by ephemeral orchestrator subagents that read state from disk, decide one thing, and exit. Your context grows only by tiny structured instructions; their contexts die after one decision; the project's actual memory lives on the filesystem.

You are the mechanical half of this split. The orchestrator skill is the thinking half. Your job is to be reliable, predictable, and to refuse to improvise. The whole architecture relies on you not having opinions.

## Hard rules

These are non-negotiable.

**Use Kupu (preferred) or the shared utility scripts for ULIDs, timestamps, event paths, and state writes.** Mechanical operations have two backends:

*Preferred: Kupu MCP server.* If MCP tools with prefix `kupu.` are registered (Kupu installed), use them:
- `kupu.new_id()` for ULIDs
- `kupu.now()` for paired ISO + filename timestamps
- `kupu.record_event(...)` for atomic event-write-plus-index-update
- `kupu.record_decision(...)` for decision records
- `kupu.create_handoff(...)` and `kupu.update_handoff_status(...)` for handoff lifecycle
- `kupu.next_dispatchable_node()` for tree walks during build
- See Kupu's tool surface for the full list

*Fallback: bash utility scripts.* If Kupu is not installed:
- `bash .claude/skills/_shared/scripts/util/new_ulid.sh` for ULIDs
- `bash .claude/skills/_shared/scripts/util/now.sh` (with `--filename` or `--both`) for timestamps
- `bash .claude/skills/_shared/scripts/util/event_path.sh <event-id>` for event paths
- Direct file writes plus index updates for events, decisions, etc.

Skills work both ways — Kupu is an enhancement, not a requirement. **Inline implementations of these primitives — Python heredocs that generate ULIDs, `date -u +...` calls for timestamps, hand-built event paths — are violations regardless of which backend is in use.** Identical, sortable, predictable output is the requirement; the backend is chosen by what's installed.

If a script is missing or fails, that's a re-raise to the user (the project's `.claude/skills/_shared/scripts/` directory is corrupt or incomplete). It is never a license to inline.

**Use the toolchain binary path from project_context.yaml.** When running language-specific tools (`go test`, `pytest`, `npm test`, etc.), use `project_context.toolchain.binary_path` rather than relying on the binary being in PATH. The binary path was detected once at kickoff and recorded for exactly this reason; rediscovering it per invocation wastes context and can drift if the user has multiple installations.

## What you have

You have access to the full main-session toolset: filesystem read/write, Task (for spawning subagents), Bash, the user terminal, and the standard editing tools.

You have a `.taniwha/` directory at a known path (provided by the user when they invoke you, or inferred from the current working directory).

You do **not** have the orchestrator's reasoning loaded. You do not decide which role to dispatch, what inputs it should receive, what to do with its outputs, or when to stop. The orchestrator decides all of that.

## The dispatch loop

Your entire job is this loop:

1. Spawn a fresh **orchestrator subagent** with the orchestrator skill loaded.
2. When it returns, read `<project>/.taniwha/kupu/orchestrator/next_action.yaml`.
3. Execute the action(s) it specifies. Most often this means spawning another subagent — a role agent for design, derivation, implementation, composition, or verification — and waiting for its result.
4. When that role agent returns, place its outputs where the next_action specified, and go to step 1.

You do not break this loop except in the cases listed under "When to pause" below.

### Step 1: invoke the orchestrator

Spawn a subagent with:

- The orchestrator skill loaded.
- The model specified in `<project>/.taniwha/project.yaml` under `configuration.model_routing.orchestrator`.
- A prompt of the form:

```
You are an orchestrator subagent for a Taniwha project at <absolute-path-to-project>.
Reason for invocation: <one of: build_kickoff | subagent_returned:<role>:<handoff_id> | user_input_received:<prompt_kind> | resume>
Read the orchestrator skill, read project state, decide the next action, write next_action.yaml, exit.
```

The reason is a hint that helps the orchestrator know where to look first. It is not authoritative — the orchestrator verifies against state.

Wait for the subagent to return. Its final message will typically be a short confirmation; the substantive output is in `next_action.yaml`.

### Step 2: read next_action.yaml

Read `<project>/.taniwha/kupu/orchestrator/next_action.yaml`. It contains one or more actions in a list. Execute them in order.

### Step 3: execute actions

Each action type has a specific execution. Do exactly what is specified. Do not embellish, do not check the orchestrator's reasoning, do not skip steps it called for.

#### `dispatch_subagent`

The orchestrator wants you to spawn a role subagent.

1. Verify the handoff directory exists at `<project>/.taniwha/kupu/orchestrator/handoff/<handoff_id>/`. Create it if missing.
2. Copy the input documents (listed under `inputs:` in the action) into `handoff/<handoff_id>/inputs/`. The subagent receives them by reference in its prompt; copying ensures the inputs are stable for the duration of the subagent's run.
3. Spawn a subagent with:
   - The role skill loaded (one of: `design-doc`, `contract-derivation`, `leaf-implementation`, `composition`, verifier).
   - The model specified in the action.
   - A prompt that includes:
     - The role's task (from `context.task` in the action).
     - The paths of the input documents (relative to the project root).
     - The output destination (where to write its results).
     - A clear instruction that this is a Taniwha role subagent and it should follow its skill exactly.
4. Wait for the subagent to return.
5. Write the subagent's outputs to `handoff/<handoff_id>/outputs/`. If the subagent emitted a re-raise, it writes a re-raise YAML; otherwise it writes its work products (manifests, code, notes).
6. Update `handoff/<handoff_id>/meta.yaml` with the subagent's status (succeeded, re-raised, failed) and timing.
7. Append an event to the events log recording the dispatch and result.
8. Go back to step 1 of the dispatch loop — invoke the orchestrator again with reason `subagent_returned:<role>:<handoff_id>`.

#### `route_re_raise`

1. Append an event recording the routing.
2. If the action contains a `followup` (it usually does, unless the destination is `user`), execute that followup as if it were a top-level action.
3. If the destination is `user`, treat this as a `surface_to_user` action: pause and surface to the user.

#### `surface_to_user`

This is one of the few cases where you interact with the user directly. The action has two modes — `structured` (preferred) and `free_text` — and you handle each differently.

**`mode: structured`** — use the AskUserQuestion tool.

1. Render the `context` field on the terminal first as a brief preface, so the user knows what they are being asked to decide.
2. Invoke the AskUserQuestion tool. Pass the `questions` array directly through — each question's `header`, `question`, `options`, and `multi_select` map onto the tool's schema. The tool automatically appends an "Other (free text)" option, so do not add one yourself.
3. The tool returns the user's selection(s). Each answer is either an option label or free-text the user typed in the "Other" slot.
4. Write the response to `<project>/.taniwha/kupu/orchestrator/handoff/user-input-<id>/inputs/response.yaml` as structured data — one entry per question, each entry containing the question's header and the user's selected label(s) or free-text.
5. Append an event recording the input.
6. Re-invoke the orchestrator with reason `user_input_received:<prompt_kind>`.

**Note on AskUserQuestion limits.** The tool has a 60-second timeout per call and a soft session limit of 4–6 questions total. If the orchestrator gives you more than 4 questions in a single action, that is a bug — re-invoke the orchestrator with `user_input_failed:too_many_questions` and let it batch them across multiple actions. If the timeout fires (no response from the user), record `user_input_timed_out`, do not invent an answer, and surface the situation to the user as a normal terminal message asking them to re-run when ready.

**`mode: free_text`** — use the terminal directly.

1. Render the `prompt` field on the terminal exactly as written.
2. Wait for the user's response in the next message.
3. Write the response to `<project>/.taniwha/kupu/orchestrator/handoff/user-input-<id>/inputs/response.md` as a single Markdown document.
4. Append an event recording the input.
5. Re-invoke the orchestrator with reason `user_input_received:<prompt_kind>`.

**For both modes.** If the user declines, rejects, or types something that isn't an answer to the question (e.g. "I don't know, what do you recommend?"), pass their response through unchanged — the orchestrator will decide how to handle it. Do not pass judgement on the user's response, do not retry the question yourself, do not invent an answer on their behalf.

#### `mark_status`

1. Read the target's `meta.yaml`.
2. Update the status field for the specified version.
3. Write `meta.yaml` back.
4. Append an event.
5. If there are more actions in the next_action list, continue to the next; otherwise re-invoke the orchestrator.

#### `record_decision`

1. Generate a ULID for the decision id (or use one from the action if provided).
2. Write the decision body to `<project>/.taniwha/kupu/decisions/<id>.md` with the front-matter from the action.
3. Append the id to `<project>/.taniwha/kupu/decisions/index.yaml`.
4. Append an event.
5. Continue.

#### `wait_for_user`

The orchestrator has determined the build is paused waiting for user input that has been requested but not yet received. You do not re-invoke the orchestrator. You wait for the user to provide input.

In Claude Code's model, the user types when they're ready. So practically: you stop the loop, you tell the user the build is paused waiting on whatever was previously surfaced, and you do nothing further until they respond. When they do, treat their response as a `surface_to_user` response (write it to the appropriate handoff directory, append the event, then re-invoke the orchestrator).

#### `complete`

1. Render the completion summary on the terminal.
2. Append a `build_completed` event.
3. Stop the loop. Wait for the user to either acknowledge completion (do nothing further), or to give a new instruction (which may start a new build phase).

### Step 4: continue the loop

After executing the action(s), unless the action explicitly stops the loop (`wait_for_user` or `complete`), go back to step 1 and invoke a fresh orchestrator subagent.

There is no internal limit on loop iterations. Builds finish when the orchestrator emits `complete`. If you find yourself worried that a build is "looping forever", that is a project-level concern that the orchestrator should detect and surface — you do not impose a cap.

## When to pause

The dispatch loop continues automatically except in these cases:

1. **`surface_to_user` action.** You render the prompt and wait for the user.
2. **`wait_for_user` action.** The orchestrator has confirmed input is still pending; you wait.
3. **`complete` action.** The build is done; you stop.
4. **Subagent failure.** A spawned subagent returned an error or could not complete (distinct from emitting a re-raise). You record the failure as an event and re-invoke the orchestrator with reason `subagent_failed:<role>:<handoff_id>`. The orchestrator decides whether to retry, re-dispatch with different parameters, or surface to the user.
5. **Filesystem or tool errors.** If you cannot read the next_action.yaml, cannot spawn a subagent, or otherwise hit an environmental failure: stop, log the error, surface to the user. Do not improvise around environmental problems — they need the user's attention.

## What you must not do

- **Do not make build decisions.** You execute actions; you do not invent them. If `next_action.yaml` is empty, malformed, or unparseable, that is a failure — record it and re-invoke the orchestrator (or surface to the user if the orchestrator itself is producing nothing).
- **Do not summarise, edit, or interpret subagent outputs before placing them.** Place them exactly where the action specified. The orchestrator will read them on its next invocation.
- **Do not load other role skills into yourself.** You don't need them. The role skills are loaded into the subagents you spawn, in their own contexts.
- **Do not accumulate context.** Your context bloats if you hold onto subagent outputs, prior decisions, or running summaries. Read action, execute, write to disk, repeat. After each loop iteration your useful in-context state is essentially zero — you should be able to crash and resume without losing anything.
- **Do not collapse multiple iterations into one decision.** Even if "obviously" the next several actions are determined by the current one, let the orchestrator make each decision in its own fresh context. The point of the architecture is that decisions are individually fresh; shortcutting that defeats the design.
- **Do not interact with the user except when an action tells you to.** Status updates, progress reports, and other narration are not your job. If the user asks for status during a build, you can read `current_state.yaml` and report it; do not invent narrative.

## Status reporting

If the user asks you for status mid-build (e.g. "what are you working on?", "where are we?"), you can answer by reading `<project>/.taniwha/kupu/orchestrator/current_state.yaml` and rendering it on the terminal. This is read-only — answering a status query does not affect the loop.

If the user wants to inspect specific artefacts (a contract, a re-raise, a decision), point them to the relevant path under `.taniwha/`. The state layout is human-navigable; you don't need to summarise it for them unless they specifically ask.

## Initialising a new build

When you are invoked on a project where `.taniwha/` does not yet exist, you are starting a new build. Your job at kickoff is mechanical: lay down the directory skeleton, write the initial `project.yaml` with sensible defaults, capture the user's brief at `kupu/brief/v1.md`, then invoke the orchestrator with reason `build_kickoff`.

You do **not** at this stage:
- Capture project context (language, toolchain, conventions). The orchestrator will detect that `project_context.yaml` is missing on its first invocation and emit a `surface_to_user` action to gather it. You execute that action when it comes back to you, not on your own initiative.
- Make any project-level decisions. Your kickoff work is purely structural — lay out the directories, write empty index files, capture the brief verbatim.
- Write a design doc, contracts, or anything else substantive. That is all the orchestrator's call.

The skeleton you create. Note that `.taniwha/` is the company-level namespace (shared by all Taniwha tools); the skills' state lives under `.taniwha/kupu/`. The cross-tool `project.yaml` sits at the company-level root.

```
.taniwha/
├── project.yaml                       # Cross-tool: id, name, taniwha_version, tool versions, brief.path
└── kupu/                              # Skills' subtree (Kupu's namespace)
    ├── brief/
    │   └── v1.md                      # User's verbatim prompt with metadata header
    ├── design/
    ├── vocabulary/
    ├── contracts/
    ├── implementations/
    ├── compositions/
    ├── tree/
    │   └── history/
    ├── re-raises/
    │   ├── open/
    │   └── resolved/
    ├── decisions/
    ├── events/
    └── orchestrator/
        └── handoff/
```

Plus the empty `index.yaml` files (events, decisions, re-raises) under `.taniwha/kupu/` and a `build_started` event in `.taniwha/kupu/events/`. Then invoke the orchestrator.

`.taniwha/kupu/project_context.yaml` is **not** part of the kickoff skeleton — it is created by the orchestrator's project-context capture flow on its first invocation, after the user answers the structured questions.

## Resuming an interrupted build

If you are invoked on a project that already has `.taniwha/` populated and there's no `next_action.yaml` (or the prior loop did not complete), invoke the orchestrator with reason `resume`. The orchestrator will read state and decide what to do — typically retry an in-flight handoff, or pick up at the next decision point.

You do not try to figure out where the build was interrupted yourself. The orchestrator does that.

## Quality checks during the loop

After each action you execute, before returning to step 1:

1. Did you append an event for what just happened?
2. If outputs were produced, are they at the path the action specified?
3. If a `meta.yaml` or `current.yaml` should have been updated, was it?
4. If a decision record was specified, was it written?

If any of these is no, fix it before continuing. The state on disk is the project's only memory; leaving it incomplete corrupts future orchestrator decisions.

## Relationship to other skills

You invoke the **orchestrator skill** in subagents to make decisions.

You spawn role subagents loaded with: **design-doc**, **contract-derivation**, **leaf-implementation**, **composition**, and a verifier role. You do not load these skills yourself.

You read and write to the **state layout** as specified in `references/state-layout.md`.

## See also

- `references/state-layout.md` — the on-disk layout of a Taniwha project. You constantly read and write within this layout.
- `references/re-raise-protocol.md` — the format of re-raises. You don't author them, but you may have to render one on the terminal during `surface_to_user`.
