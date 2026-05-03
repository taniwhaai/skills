#!/usr/bin/env bash
# detect/go.sh — locate the Go toolchain on this machine.
#
# Tries the standard locations and returns information about the Go binary
# and version. Used at kickoff to populate project_context.yaml so subsequent
# agents do not have to rediscover Go on each invocation.
#
# Output (on success): YAML fragment on stdout, exit 0
#   binary_path: /path/to/go
#   detected_version: 1.24.1
#   detected_at: 2026-05-01T22:08:33Z
#
# Output (on failure): YAML fragment on stdout, exit 1
#   binary_path: null
#   detected_version: null
#   detected_at: 2026-05-01T22:08:33Z
#   error: "Go not found in PATH or standard locations"
#   tried:
#     - /usr/local/go/bin/go
#     - /opt/homebrew/bin/go
#     - ...

set -uo pipefail

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Locations to probe, in priority order. PATH first.
candidates=()
if which go >/dev/null 2>&1; then
    candidates+=("$(which go)")
fi
candidates+=(
    "/usr/local/go/bin/go"
    "/opt/homebrew/bin/go"
    "/usr/lib/go/bin/go"
)
# User-local SDKs (common locations)
if [ -n "${HOME:-}" ]; then
    # Match patterns like ~/sdk/go1.24.1/bin/go and pick the highest-versioned
    while IFS= read -r path; do
        [ -n "$path" ] && candidates+=("$path")
    done < <(ls -1 "$HOME"/sdk/go*/bin/go 2>/dev/null | sort -V | tail -1)

    # Also check ~/go/bin if the user has Go installed via gvm or similar
    [ -x "$HOME/go/bin/go" ] && candidates+=("$HOME/go/bin/go")
fi

found_path=""
for path in "${candidates[@]}"; do
    if [ -x "$path" ]; then
        found_path="$path"
        break
    fi
done

if [ -z "$found_path" ]; then
    echo "binary_path: null"
    echo "detected_version: null"
    echo "detected_at: $now"
    echo "error: \"Go toolchain not found in PATH or standard locations\""
    echo "tried:"
    for path in "${candidates[@]}"; do
        echo "  - \"$path\""
    done
    exit 1
fi

# Extract version. `go version` outputs e.g.: go version go1.24.1 linux/amd64
version_output=$("$found_path" version 2>/dev/null || echo "")
version=$(echo "$version_output" | sed -n 's/^go version go\([0-9.]*\).*/\1/p')

if [ -z "$version" ]; then
    echo "binary_path: \"$found_path\""
    echo "detected_version: null"
    echo "detected_at: $now"
    echo "error: \"Go binary found but version could not be parsed\""
    echo "raw_output: \"$version_output\""
    exit 1
fi

echo "binary_path: \"$found_path\""
echo "detected_version: \"$version\""
echo "detected_at: $now"
