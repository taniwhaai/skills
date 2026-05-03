# Taniwha shared scripts

Bash utilities used by the dispatcher and orchestrator skills as the **fallback backend** when Kupu (the MCP server) is not installed. Shared because every Taniwha agent that needs them should produce identical output — ULIDs, timestamps, event paths, and toolchain detection are exactly the kind of thing where each agent reaching for its own implementation produces subtly different results.

When [Kupu](https://github.com/taniwhaai/kupu) is installed, skills prefer Kupu's MCP tools (`kupu.new_id`, `kupu.now`, `kupu.record_event`, etc.) over these scripts. The two backends produce identical on-disk output, so users can install Kupu later without re-running existing builds.

## Platform support

These scripts target bash on macOS and Linux. Windows users should run them under WSL — Claude Code on Windows typically already runs through WSL, so this is rarely an issue in practice. If a Windows-without-WSL user hits this, the right fix is to add a Python equivalent rather than a `.ps1` script.

## Layout

```
_shared/scripts/
├── util/
│   ├── new_ulid.sh        # Generate a ULID
│   ├── now.sh             # UTC timestamp (ISO 8601 or filename form)
│   └── event_path.sh      # Build canonical .taniwha/kupu/events/... path
└── detect/
    ├── go.sh              # Locate Go toolchain, return path + version
    ├── python.sh          # Same for Python 3
    └── node.sh            # Same for Node.js
```

## Usage from skills

Call scripts with `bash` explicitly so they work regardless of the file's executable bit:

```
bash .claude/skills/_shared/scripts/util/new_ulid.sh
bash .claude/skills/_shared/scripts/util/now.sh --filename
bash .claude/skills/_shared/scripts/util/event_path.sh "01KQGHE000VERIFPOLICY01"
bash .claude/skills/_shared/scripts/detect/go.sh
```

Detect scripts emit YAML on stdout and exit 0 on success or 1 on failure. The output is suitable for inclusion under `project_context.yaml`'s `toolchain:` block — the dispatcher captures the output verbatim.

## Adding a new utility or detector

Stay under 50 lines where possible. Bash. No external dependencies beyond the system shell, `python3` (used for ULID generation only), and `date`. If a script genuinely needs Python, that's fine — just don't introduce dependencies on third-party packages.
