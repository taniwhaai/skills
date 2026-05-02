# Templates

Files that get installed into a user's project at install time, alongside the `.claude/` directory.

## CLAUDE.md

The project-level CLAUDE.md that tells Claude Code how to behave when run inside a Taniwha project. Drops into the project root.

If the user already has a CLAUDE.md, the install process should append rather than overwrite — the Taniwha section should be additive.
