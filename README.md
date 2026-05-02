# Taniwha Skills

A discipline for AI-generated codebases. Imposes structure that holds as projects grow, with verifier-checked contracts and a re-raise loop that surfaces under-specification before code is written.

## What this is

LLMs given an open-ended brief tend to produce sprawling, inconsistent, hard-to-review code that drifts further from the brief as it grows. Taniwha is a set of skills and subagents that constrain how the agent works: it must agree on a structural shape before writing any code, contracts must be complete enough to implement in isolation, every implementation gets independently verified, and ambiguity gets surfaced as questions rather than silently filled in.

The cost is more ceremony than a human writes by hand at small scale. The payoff is structure that holds as the codebase grows — and an audit trail of decisions, contracts, and verifications that survives the conversations that produced them.

Taniwha matches structure to the brief. A small project gets a single contract, a single implementation, a single verifier. A large project gets a tree of modules with composition agents wiring them together. The design-doc agent decides which tier the brief calls for, and the user approves; the rest of the system follows.

## Install

### As a Claude Code plugin

```
/plugin install taniwha
```

### Manual install

Drop the `.claude/` directory at the root of your project, or:

```
git clone <repo-url> taniwha
cp -r taniwha/skills .claude/skills
cp -r taniwha/agents .claude/agents
cp taniwha/CLAUDE.md ./CLAUDE.md
```

Then in Claude Code, ask it to start a Taniwha build:

> Build me a [whatever you want] as a Taniwha project.

The dispatcher takes over from there.

## How it works

A Taniwha build is a loop:

1. **Dispatcher** (the main Claude Code session) holds the Task tool and acts as a mechanical executor.
2. **Orchestrator subagents** are spawned one at a time, read project state from disk, decide the single next action, write that decision to disk, and exit. They have no memory between invocations.
3. **Role subagents** (design-doc, contract-derivation, leaf-implementation, composition, verifier) carry out the orchestrator's decisions. Each role sees a strictly whitelisted set of inputs to enforce compartmentalisation.

The project's memory lives in a `.taniwha/` directory at the project root: design docs, contracts, vocabulary, implementation manifests, decision records, event log, re-raise log. Source code lives at the repo root in whatever layout the project context names; `.taniwha/` only holds agent state.

A single user-facing run looks like this:

1. User gives a brief.
2. Dispatcher captures the brief, spawns the orchestrator.
3. Orchestrator surfaces structured questions to capture project context (language, repo layout, test framework).
4. Toolchain detection runs.
5. Design-doc subagent produces a design including the **structural tier** (single_module / small_multi_module / full_decomposition). Any under-specified parts of the brief surface as open questions.
6. User answers open questions. User approves the design and tier.
7. Contract-derivation subagent produces per-module manifests and shared vocabulary.
8. Leaf-implementation subagent(s) build modules from contracts.
9. Verifier subagent(s) independently check each implementation against its acceptance criteria.
10. Composition subagent(s) wire modules together (multi-module builds only).
11. Build complete; user reviews summary.

Every step is a fresh subagent reading filesystem state. Decisions, events, and re-raises are durable and human-readable.

## Skills

| Skill | Purpose |
|-------|---------|
| [design-doc](skills/design-doc/SKILL.md) | Produces a structural design from a brief, including the project's tier. Audits the brief for under-specification; surfaces silent decisions. |
| [contract-derivation](skills/contract-derivation/SKILL.md) | Derives per-module manifests and shared vocabulary from an approved design. Manifests are language-neutral. |
| [leaf-implementation](skills/leaf-implementation/SKILL.md) | Implements one module from one manifest, working only from the manifest + vocabulary + project context. |
| [composition](skills/composition/SKILL.md) | Wires two completed children under a parent contract. Produces canonical shared-types packages. |
| [verifier](skills/verifier/SKILL.md) | Independently verifies an implementation against its contract's acceptance criteria. Writes its own tests. |
| [orchestrator](skills/orchestrator/SKILL.md) | Ephemeral; decides the single next action by reading state. |
| [dispatcher](skills/dispatcher/SKILL.md) | Main-session loop; spawns subagents per orchestrator decisions. |

## Subagents

Defined in `agents/`; installed alongside the skills.

| Agent | Skill |
|-------|-------|
| `taniwha-orchestrator` | orchestrator |
| `taniwha-design-doc` | design-doc |
| `taniwha-contract-derivation` | contract-derivation |
| `taniwha-leaf-implementation` | leaf-implementation |
| `taniwha-composition` | composition |
| `taniwha-verifier` | verifier |

## Design principles

These are the load-bearing rules across the system:

- **Compartmentalisation.** Every role sees only a whitelisted set of inputs. Cross-role context leakage destroys the discipline.
- **Re-raise over guess.** Any under-specified clause is surfaced as a question, not silently filled in.
- **Tier match.** The structural shape matches the brief. A URL shortener gets one module; a multi-subsystem service gets a tree.
- **Verification is mandatory.** Implementor self-reports do not count. A verifier reads the contract independently and checks per-AC.
- **State on disk, not in context.** Every decision survives in `.taniwha/`. Subagents read state, decide one thing, exit.
- **Cold-readable.** A returning agent six months later, with no chat history, can pick up where it left off by reading the directory.

## Use with general-purpose skills

Taniwha focuses on project-architecture. For general-purpose engineering and productivity skills (TDD, debugging, grilling sessions, codebase improvement), [mattpocock/skills](https://github.com/mattpocock/skills) is excellent and pairs well.

## License

MIT — see [LICENSE](LICENSE).
