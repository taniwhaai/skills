#!/usr/bin/env bash
# detect/node.sh — locate the Node.js toolchain on this machine.

set -uo pipefail

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

candidates=()
if which node >/dev/null 2>&1; then
    candidates+=("$(which node)")
fi
candidates+=(
    "/usr/local/bin/node"
    "/opt/homebrew/bin/node"
    "/usr/bin/node"
)
# nvm-installed node
if [ -n "${NVM_DIR:-}" ]; then
    while IFS= read -r path; do
        [ -n "$path" ] && candidates+=("$path")
    done < <(ls -1 "$NVM_DIR"/versions/node/*/bin/node 2>/dev/null | sort -V | tail -1)
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
    echo "error: \"Node.js toolchain not found in PATH or standard locations\""
    echo "tried:"
    for path in "${candidates[@]}"; do
        echo "  - \"$path\""
    done
    exit 1
fi

# `node --version` outputs e.g.: v20.11.0
version_output=$("$found_path" --version 2>/dev/null || echo "")
version=$(echo "$version_output" | sed -n 's/^v\([0-9.]*\).*/\1/p')

if [ -z "$version" ]; then
    echo "binary_path: \"$found_path\""
    echo "detected_version: null"
    echo "detected_at: $now"
    echo "error: \"Node binary found but version could not be parsed\""
    echo "raw_output: \"$version_output\""
    exit 1
fi

echo "binary_path: \"$found_path\""
echo "detected_version: \"$version\""
echo "detected_at: $now"
