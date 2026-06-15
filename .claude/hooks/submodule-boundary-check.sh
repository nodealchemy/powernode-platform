#!/bin/bash
# Advisory hook: warns when editing files inside git submodule directories.
# Reminds to use git -C for commits. Exit 0 always (advisory only).

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"

# Derive the extension/submodule list dynamically so the hook warns for every
# extension present on disk without naming any of them here. Private/custom
# extensions live one level deeper under extensions/private/<name>.
for ext_dir in "$PROJECT_DIR"/extensions/*/ "$PROJECT_DIR"/extensions/private/*/; do
  [[ -d "$ext_dir" ]] || continue
  submod="${ext_dir#"$PROJECT_DIR"/}"
  submod="${submod%/}"
  [[ "$submod" == "extensions/private" ]] && continue
  if [[ "$FILE_PATH" == *"$submod"* ]]; then
    NAME=$(basename "$submod")
    echo "⚠ Submodule file: $NAME — commit with 'git -C $submod', NOT parent repo git commands." >&2
    break
  fi
done

exit 0
