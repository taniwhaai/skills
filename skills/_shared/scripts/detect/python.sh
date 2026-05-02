#!/usr/bin/env bash
# detect/python.sh — locate the Python toolchain on this machine.
#
# Tries python3 first, then python. Returns binary path and version.
#
# Output (on success): YAML fragment on stdout, exit 0
# Output (on failure): YAML fragment on stdout with error, exit 1

set -uo pipefail

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

candidates=()
if which python3 >/dev/null 2>&1; then
    candidates+=("$(which python3)")
fi
if which python >/dev/null 2>&1; then
    candidates+=("$(which python)")
fi
candidates+=(
    "/usr/local/bin/python3"
    "/opt/homebrew/bin/python3"
    "/usr/bin/python3"
)

found_path=""
for path in "${candidates[@]}"; do
    if [ -x "$path" ]; then
        # Quick sanity check that this is Python 3.x
        if "$path" -c "import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)" 2>/dev/null; then
            found_path="$path"
            break
        fi
    fi
done

if [ -z "$found_path" ]; then
    echo "binary_path: null"
    echo "detected_version: null"
    echo "detected_at: $now"
    echo "error: \"Python 3 toolchain not found in PATH or standard locations\""
    echo "tried:"
    for path in "${candidates[@]}"; do
        echo "  - \"$path\""
    done
    exit 1
fi

# Extract version. `python --version` outputs e.g.: Python 3.11.6
version_output=$("$found_path" --version 2>&1 || echo "")
version=$(echo "$version_output" | sed -n 's/^Python \([0-9.]*\).*/\1/p')

if [ -z "$version" ]; then
    echo "binary_path: \"$found_path\""
    echo "detected_version: null"
    echo "detected_at: $now"
    echo "error: \"Python binary found but version could not be parsed\""
    echo "raw_output: \"$version_output\""
    exit 1
fi

echo "binary_path: \"$found_path\""
echo "detected_version: \"$version\""
echo "detected_at: $now"
