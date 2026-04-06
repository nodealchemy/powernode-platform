#!/bin/bash
# Advisory hook: warns when editing files inside git submodule directories.
# Reminds to use git -C for commits. Exit 0 always (advisory only).

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/home/rett/Drive/Projects/powernode-platform}"
SUBMODULES=("extensions/business" "extensions/trading" "extensions/supply-chain")

for submod in "${SUBMODULES[@]}"; do
  if [[ "$FILE_PATH" == *"$submod"* ]]; then
    NAME=$(basename "$submod")
    echo "⚠ Submodule file: $NAME — commit with 'git -C $submod', NOT parent repo git commands." >&2
    break
  fi
done

exit 0
