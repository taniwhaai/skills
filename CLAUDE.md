# Repo organisation

This repo holds the Taniwha skills and subagents.

## Layout

```
taniwha/
├── .claude-plugin/
│   └── plugin.json         # Claude Code plugin manifest
├── agents/                 # Subagent definitions, one .md per agent
├── skills/                 # The seven Taniwha skills
│   ├── _shared/            # State layout, re-raise protocol, utility scripts
│   ├── design-doc/
│   ├── contract-derivation/
│   ├── leaf-implementation/
│   ├── composition/
│   ├── verifier/
│   ├── orchestrator/
│   └── dispatcher/
└── templates/
    └── .taniwha-project/   # Template for the per-project CLAUDE.md a user drops in
```

## Skill structure

Every skill has the same shape:

```
skills/<skill-name>/
├── SKILL.md                # The skill itself
└── references/             # Resources the skill points at
    ├── state-layout.md     # Authoritative description of .taniwha/
    └── re-raise-protocol.md
```

Skills are read by Claude Code at runtime; the `references/` files are loaded on demand when a SKILL.md says to.

## Agents

Each subagent is a single `.md` file in `agents/` with YAML frontmatter declaring the agent's tools and which skill it follows. The agent file itself is small — the discipline lives in the skill.

## Adding a new skill

1. Create `skills/<name>/SKILL.md`. Include `state-layout.md` and `re-raise-protocol.md` references in `skills/<name>/references/` if the skill needs them.
2. Add the skill to the table in `README.md`.
3. Add the skill to the `skills` array in `.claude-plugin/plugin.json`.
4. If the skill is dispatched as a separate subagent, add an agent file in `agents/` and reference it in `plugin.json`.

## What this repo is NOT

It is not Taniwha itself running. The output of running Taniwha (the `.taniwha/` directory of a built project) is a separate artifact that lives in the user's project, not here.
