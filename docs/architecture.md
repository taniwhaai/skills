# Taniwha architecture

This document describes the load-bearing architectural choices in Taniwha and why they exist. Read this if you want to understand *why* the system is structured the way it is, or if you're considering modifying or extending it.

## Position: AI design as a primitive of the codebase

Taniwha's broader thesis is that **AI design should be a primitive of the codebase, not a chat ephemeral.** A repository that is built and modified by AI agents should carry its own structural discipline, decision history, and contract definitions in a form that survives any individual conversation, agent, or developer. Source code is one artefact among several; design docs, contracts, vocabulary, decision records, and verification reports are first-class citizens of the repo.

The skills described in this repo are one piece of that broader thesis. They constrain how the agent works during a build. The runtime backbone — Kupu — manages the durable state those skills produce. Together they let an AI-centric codebase be self-describing, audit-friendly, and resistant to drift across many conversations.

## The problem Taniwha solves

LLMs given an open-ended brief produce code that:

- **Sprawls.** A "small URL shortener" becomes six modules with three abstractions per module, when one file would do.
- **Drifts.** Decisions made early in the conversation get forgotten or contradicted later; the agent reaches for whatever is locally convenient.
- **Fills in silence.** When the brief doesn't specify a retry count, the agent picks one. When it doesn't specify error semantics, the agent picks them. The user never knows.
- **Doesn't compose.** Modules built independently each invent their own copies of shared types; integrating them requires extensive type translation.
- **Verifies itself.** "Tests pass" means "the implementor's tests pass", which means "the implementor's interpretation of the contract is internally consistent" — not "the contract is satisfied".

Taniwha's structure exists to address each of these directly.

## Compartmentalisation

A Taniwha build is decomposed into many small decisions, each made by a fresh subagent reading durable filesystem state. Each subagent sees only a strictly whitelisted set of inputs.

Why: an agent's natural failure mode is to use whatever context is available. If a leaf-implementation agent can see the design doc, it will rationalise its way to "what the design wants" rather than "what the contract specifies", and that's how scope expansion happens. By limiting each role to inputs the role's contract genuinely needs, the discipline becomes structural rather than aspirational.

The whitelists are non-negotiable. Including off-whitelist inputs ("just to give context") destroys the property the architecture provides.

## Re-raise over guess

When any role finds a clause it cannot satisfy from its inputs alone — under-specification, ambiguity, internal contradiction, missing dependency — the role emits a re-raise rather than guessing.

Re-raises bubble up to the appropriate level of authority:
- Implementor-level under-specification → contract author
- Contract-level under-specification → design author
- Design-level under-specification → user

The user is the only one who can fill in genuinely missing requirements. Letting the agent fill them in produces decisions buried in code that the user never agreed to.

## Tier matching

A Taniwha project is one of three structural tiers:

- **`single_module`**: one contract, one implementation, one verifier. No vocabulary, no composition.
- **`small_multi_module`**: 2–4 modules with one composition layer.
- **`full_decomposition`**: 5+ modules with nested composition tree.

The design-doc agent picks the tier and justifies it against specific brief content. The user approves. The rest of the system follows.

The agent's bias is toward decomposition; the system counters that with a default-to-smallest rule and a per-module justification requirement.

## Verification as a separate role

A verifier subagent reads each contract independently, writes its own tests against the acceptance criteria, runs them, and reports per-AC pass/fail. The verifier did not write the code; it reads the contract from scratch.

Why: the implementor's tests can be wrong in the same way the implementation is wrong. Two independent interpretations of the contract converging is meaningful evidence; one interpretation testing itself is not.

## State on disk, not in context

All project state lives in `.taniwha/kupu/`: design docs, contracts, vocabulary, manifests, decisions, events, re-raises. (`.taniwha/` itself is the company-level namespace; `kupu/` is the skills' subtree, and other Taniwha tools may use other subtrees.) Subagents read state, decide one thing, write to state, exit. They have no memory between invocations.

Why: an LLM context window is finite and degrades over long conversations. State on disk is durable, inspectable, and version-controlled. A returning agent six months later can pick up where the previous build left off by reading the directory.

## Cold-readability

The directory is structured so a returning agent (or human) can answer specific questions by reading specific files:

- "What is this project for?" → `.taniwha/kupu/brief/v<N>.md`
- "What's the current shape?" → `.taniwha/kupu/tree/current.yaml`
- "What does this module promise?" → `.taniwha/kupu/contracts/<module>/v<N>.md`
- "What was decided about X?" → `.taniwha/kupu/decisions/<id>.md`
- "What happened?" → `.taniwha/kupu/events/<year>/<month>/<day>/...`

Every file is named so its purpose is obvious. Every cross-reference uses paths that are valid on disk. No file points at content that lives only in some agent's context.

## Source code separation

Source code lives at the repo root in whatever layout the project context names. `.taniwha/` holds only agent state. Implementation manifests reference source files by repo-root paths.

Why: users expect source code to live in the obvious place. A `.taniwha/`-internal source tree would conflict with build tools, IDEs, version control, and human navigation.

## What the architecture does NOT optimise for

- **Speed.** Taniwha is slower than freewheeling AI for any individual task. The structure costs invocations.
- **Token efficiency.** State writes, decision records, and event logs cost context. The audit trail is the point, not a bug.
- **Small-scale convenience.** A 200-line script doesn't need Taniwha. The single_module tier is as light as Taniwha gets, and even that is heavier than just writing the script.

The architecture optimises for builds where structure matters: where the codebase will grow, where multiple agents (or humans) will work on it, where decisions need to survive the conversations that produced them.
