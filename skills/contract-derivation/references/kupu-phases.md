# Kupu phases and tool detection

This document describes how the skills detect Kupu's installed phase and choose between MCP tools and bash-fallback scripts. It is the authoritative reference; individual skill text refers to it rather than describing detection logic per skill.

## What is Kupu?

Kupu is the optional Rust MCP server that owns durable state for Taniwha projects. Without Kupu installed, the skills use bash-fallback scripts (under `_shared/scripts/`) to do the equivalent work — directly writing files under `.taniwha/kupu/`. With Kupu installed, the skills prefer Kupu's MCP tools, which provide schema enforcement, atomic writes, and structured returns.

The skills work either way. Kupu makes them substantially leaner; without Kupu they remain functional.

## Kupu phases

Kupu ships in phases. Each phase adds tools without changing previously-shipped tool surfaces. Skills detect available tools per-operation and choose accordingly.

**Phase 1** — primitives and project lifecycle:
- `kupu.new_id` — generate a fresh ULID
- `kupu.now` — current UTC instant in `{iso, filename}` form
- `kupu.init` — initialise a Taniwha project's `.taniwha/` skeleton
- `kupu.get_project` — read project metadata from `.taniwha/project.yaml`

**Phase 2** — durable writes:
- `kupu.record_event` — atomic event-plus-index write
- `kupu.record_decision` — write a decision record under `.taniwha/kupu/decisions/`
- `kupu.register_re_raise` — open a re-raise AND atomically mark blocked tree nodes
- `kupu.resolve_re_raise` — close a re-raise AND atomically unblock tree nodes

**Phase 3+** — read tools, artefact CRUD, tree operations, toolchain detection, build metrics, etc. (See `kupu-tool-surface.md` in the kupu repository for the full roadmap. Phase 3+ tools are not yet shipped.)

## Detection model

**Per-operation detection.** Each time a skill needs to perform an operation that has both an MCP-tool form and a bash-fallback form, the skill checks at the moment of need whether the corresponding `kupu.<tool>` is available.

Available means: the host (Claude Code) reports the tool in its tool list when the skill is dispatched. The skill does not poll, query, or maintain its own registry — it simply attempts to use the tool by name and falls back if not present.

The check is essentially free in tokens and latency. Per-operation detection means the skills automatically work across all Kupu phases: a Phase 1-only Kupu installation gets `kupu.new_id` and `kupu.now` from MCP and bash for everything else; a Phase 2 installation also uses MCP for event/decision/re-raise writes; a future Phase 3+ installation will use MCP for read tools too.

## Schema agreement

Both backends — Kupu and bash-fallback — must produce identical on-disk artefacts. The canonical schema for every file under `.taniwha/` is described in `state-layout.md`.

Kupu's Rust serde structs are the **source of truth** for these schemas. Bash-fallback templates in skill text are documentation that must match exactly. If they drift, that's a skill-text bug, not a Kupu bug.

This means: when state-layout.md describes a record's shape, that shape is what Kupu's serde structs serialise/deserialise. The bash-fallback templates are reverse-engineered from Kupu's output, not the other way around.

## Per-operation mapping

The table below shows how each skill operation maps to backends. When Kupu's MCP tool is available, use it; otherwise fall back to the bash form.

| Operation | Kupu MCP tool | Bash fallback |
|---|---|---|
| Generate ULID | `kupu.new_id` | `bash _shared/scripts/util/new_ulid.sh` |
| Get current time | `kupu.now` | `bash _shared/scripts/util/now.sh --both` |
| Compute event path | (none — derived in skill) | `bash _shared/scripts/util/event_path.sh` |
| Initialise project | `kupu.init` | manually create `.taniwha/` skeleton + write `project.yaml` |
| Read project metadata | `kupu.get_project` | manually parse `.taniwha/project.yaml` |
| Record event | `kupu.record_event` | manually write event file + update events index |
| Record decision | `kupu.record_decision` | manually write decision file + update decisions index |
| Register re-raise | `kupu.register_re_raise` | manually write re-raise file + mutate `tree/current.yaml` |
| Resolve re-raise | `kupu.resolve_re_raise` | manually move re-raise file + mutate `tree/current.yaml` |

For operations marked "manually" in the bash-fallback column, the skill text describes the canonical YAML/Markdown shape. The shape must match what Kupu's serde structs produce — see state-layout.md for the authoritative schemas.

## Why this matters

The bash-fallback path involves real ceremony: subprocess calls for primitives, hand-written YAML following the canonical schema, manual atomic-write patterns (write-temp-then-rename), explicit verify-after-write steps to catch the missing-decision-file class of bug.

When Kupu is present, all of that compresses. `kupu.record_event` is one MCP call. Schema validation happens server-side. Atomicity is enforced by Kupu's implementation, not by skill text discipline. Verification is implicit in the tool's success return.

The skills' job is to call the right thing at the right moment. The detection logic above keeps that simple: try MCP first, fall back if needed.

## Future direction

In a future skills release (probably v3.0), the bash-fallback path may be retired entirely once Kupu adoption is established. v2.0 keeps both paths because requiring Kupu installation as a hard dependency raises the bar for new users; better to ship "works without Kupu, dramatically better with it."

The Kupu phases model is the staging path: each Kupu phase shipped lets a corresponding chunk of bash-fallback code be retired in a later skills release.
