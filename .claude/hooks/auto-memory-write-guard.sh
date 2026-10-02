#!/bin/bash
# BLOCKING PreToolUse hook (IMP-c4f263d08b3a): memory lives on the platform, not in local
# auto-memory files. A memory write is a plain Write/Edit call, so "never write local memory"
# needs a harness-level guard: exit 2 when the target is under the auto-memory directory
# (<config>/projects/*/memory/) and is not that directory's own MEMORY.md.
#
# MEMORY.md stays writable and stays loaded as the pointer to platform memory (operator
# direction — this is why the guard exists instead of autoMemoryEnabled:false).
#
# Covers Write / Edit / MultiEdit (.tool_input.file_path) and the filesystem MCP write_file /
# edit_file (.tool_input.path). NOT covered: a shell redirect from the Bash tool — a hook
# cannot tell a memory write from any other command there.
#
# Fails OPEN (exit 0) on any uncertainty — malformed input, no path, no jq — so it can never
# block an unrelated edit; exit 2 only on a path it resolved into the memory directory.

input="$(cat 2>/dev/null)"
[[ -n "$input" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v realpath >/dev/null 2>&1 || exit 0

targets="$(jq -r '[.tool_input.file_path, .tool_input.path] | map(strings) | .[]' <<<"$input" 2>/dev/null)" || exit 0
[[ -n "$targets" ]] || exit 0
cwd="$(jq -r '.cwd // empty | strings' <<<"$input" 2>/dev/null)"
[[ -n "$cwd" ]] || cwd="$PWD"

roots=()
[[ -n "${HOME:-}" ]] && roots+=("$(realpath -m "$HOME/.claude" 2>/dev/null)")
[[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && roots+=("$(realpath -m "$CLAUDE_CONFIG_DIR" 2>/dev/null)")

while IFS= read -r target; do
  [[ -n "$target" ]] || continue
  case "$target" in
    "~") target="$HOME" ;;
    "~/"*) target="$HOME/${target#\~/}" ;;
  esac
  [[ "$target" == /* ]] || target="$cwd/$target"
  resolved="$(realpath -m -- "$target" 2>/dev/null)" || continue

  for root in "${roots[@]}"; do
    [[ -n "$root" ]] || continue
    rest="${resolved#"$root"/projects/}"
    [[ "$rest" != "$resolved" ]] || continue
    # rest = <project>/memory/<path...>
    project="${rest%%/*}"
    [[ -n "$project" && "$rest" == "$project"/memory/* ]] || continue
    inside="${rest#"$project"/memory/}"
    [[ "$inside" == "MEMORY.md" ]] && continue

    cat >&2 <<'MSG'
BLOCKED: local auto-memory files are no longer written — memory lives on the platform.
Record this memory with platform.create_knowledge instead:
  tags          [memory, memory-<type>, memory-<slug>]   (<type>: feedback, project, reference or user)
  access_level account
  key           "memory:<slug>"   (an upsert: re-writing the same key updates the entry)
Recall it with platform.search_knowledge tags:["memory"]. MEMORY.md stays as the pointer and may be edited.
MSG
    exit 2
  done
done <<<"$targets"

exit 0
