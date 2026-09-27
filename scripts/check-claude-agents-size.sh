#!/bin/bash
# Guard: the generated Claude Code agent roster (.claude/agents/powernode/*.md)
# must stay within the size ceilings in scripts/claude-agents-size-ceilings.txt:
#   max_tools_per_agent  no agent's frontmatter `tools:` list may hold more entries
#   max_roster_bytes     all agent files together may not exceed this many bytes
# The ceilings can only be LOWERED: the check also fails when a ceiling in the
# working file is higher than in the version committed at HEAD, or when a key
# HEAD has is missing. See the header of the ceilings file.
#
# Unlike check-claude-agents-fresh.sh this needs no database: it reads the
# committed files, so it runs (and can fail) on an unseeded checkout too.
# It is called from check-claude-agents-fresh.sh, so it runs wherever that runs.
#
# Exit: 0 within every ceiling; 1 a ceiling is exceeded, raised, or unreadable.
#
# Test seams (all optional):
#   CLAUDE_AGENTS_DIR               replaces the agents directory (shared with
#                                   check-claude-agents-fresh.sh)
#   CLAUDE_AGENTS_SIZE_CEILINGS     replaces the ceilings file
#   CLAUDE_AGENTS_SIZE_BASELINE     replaces the HEAD baseline with a file; set it
#                                   to an empty string to skip the raise check
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CEILINGS_TRACKED="scripts/claude-agents-size-ceilings.txt"
AGENTS_DIR="${CLAUDE_AGENTS_DIR:-.claude/agents/powernode}"
CEILINGS="${CLAUDE_AGENTS_SIZE_CEILINGS:-$CEILINGS_TRACKED}"

failed=0
fail() { echo "  ✗ $*" >&2; failed=1; }

# read_ceiling FILE KEY -> the value, or empty when absent. Last one wins.
read_ceiling() {
    awk -F= -v k="$2" '
        /^[[:space:]]*(#|$)/ { next }
        { key=$1; gsub(/[[:space:]]/, "", key); if (key == k) { v=$2; gsub(/[[:space:]]/, "", v); val=v } }
        END { print val }
    ' "$1"
}

# count_tools FILE -> number of entries in the frontmatter `tools:` field.
# Accepts the inline form (`tools: A, B, C`) and the YAML block form
# (`tools:` followed by `  - A` lines). No `tools:` field counts as 0.
count_tools() {
    awk '
        NR == 1 { if ($0 != "---") exit; fm = 1; next }
        fm && $0 == "---" { exit }
        fm && /^tools:/ {
            line = $0; sub(/^tools:[[:space:]]*/, "", line)
            if (line != "") { n = split(line, parts, ","); for (i = 1; i <= n; i++) if (parts[i] ~ /[^[:space:]]/) c++ ; exit }
            block = 1; next
        }
        fm && block && /^[[:space:]]+-[[:space:]]*[^[:space:]]/ { c++; next }
        fm && block && /^[^[:space:]]/ { exit }
        END { print c + 0 }
    ' "$1"
}

if [[ ! -f "$CEILINGS" ]]; then
    echo "Claude agent size check FAILED: ceilings file $CEILINGS is missing." >&2
    exit 1
fi

KEYS=(max_tools_per_agent max_roster_bytes)
declare -A ceiling
for key in "${KEYS[@]}"; do
    value="$(read_ceiling "$CEILINGS" "$key")"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        fail "ceiling $key in $CEILINGS is missing or not a whole number (got '${value}')"
        continue
    fi
    ceiling[$key]="$value"
done

# Raise detection against the committed ceilings.
baseline=""
cleanup_baseline=""
if [[ -n "${CLAUDE_AGENTS_SIZE_BASELINE+set}" ]]; then
    baseline="$CLAUDE_AGENTS_SIZE_BASELINE"
elif git cat-file -e "HEAD:$CEILINGS_TRACKED" 2>/dev/null; then
    baseline="$(mktemp)"
    cleanup_baseline="$baseline"
    git show "HEAD:$CEILINGS_TRACKED" >"$baseline"
fi
trap '[[ -n "$cleanup_baseline" ]] && rm -f "$cleanup_baseline"; true' EXIT

if [[ -n "$baseline" ]]; then
    if [[ ! -f "$baseline" ]]; then
        fail "baseline ceilings file $baseline is missing"
    else
        for key in "${KEYS[@]}"; do
            was="$(read_ceiling "$baseline" "$key")"
            [[ "$was" =~ ^[0-9]+$ ]] || continue
            now="${ceiling[$key]:-}"
            if [[ -z "$now" ]]; then
                fail "ceiling $key was removed (committed value $was); ceilings can only be lowered"
            elif (( now > was )); then
                fail "ceiling $key was RAISED from $was to $now; ceilings can only be lowered"
            fi
        done
    fi
fi

# Measure the roster.
shopt -s nullglob
files=("$AGENTS_DIR"/*.md)
shopt -u nullglob

total_bytes=0
max_tools=0
max_tools_file=""
for f in "${files[@]}"; do
    bytes="$(wc -c <"$f")"
    total_bytes=$((total_bytes + bytes))
    tools="$(count_tools "$f")"
    if (( tools > max_tools )); then
        max_tools=$tools
        max_tools_file="$f"
    fi
    if [[ -n "${ceiling[max_tools_per_agent]:-}" ]] && (( tools > ceiling[max_tools_per_agent] )); then
        fail "$f lists $tools tools; the ceiling is ${ceiling[max_tools_per_agent]}"
    fi
done

if [[ -n "${ceiling[max_roster_bytes]:-}" ]] && (( total_bytes > ceiling[max_roster_bytes] )); then
    fail "the roster in $AGENTS_DIR is $total_bytes bytes over ${#files[@]} files; the ceiling is ${ceiling[max_roster_bytes]}"
fi

if [[ "$failed" -ne 0 ]]; then
    echo "Claude agent size check FAILED (ceilings: $CEILINGS). Shrink the roster; never raise a ceiling to pass." >&2
    exit 1
fi

echo "Claude agent size check passed: ${#files[@]} files, $total_bytes/${ceiling[max_roster_bytes]} bytes, max tools $max_tools/${ceiling[max_tools_per_agent]}${max_tools_file:+ ($(basename "$max_tools_file"))}."
exit 0
