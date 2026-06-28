#!/bin/bash
# Advisory: flags text-color theme tokens misused as backgrounds/borders/rings, plus the
# inert `*-theme-primary-hover` token. theme-{primary,secondary,tertiary,quaternary} are TEXT
# colors — using them as bg/border/ring renders a text color as a surface (white-on-white in
# dark mode). See docs/reference/theme-system.md ("The #1 footgun").

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[[ "$FILE_PATH" != *.ts && "$FILE_PATH" != *.tsx ]] && exit 0
[[ "$FILE_PATH" != *frontend/src* ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

BASENAME=$(basename "$FILE_PATH")
[[ "$BASENAME" == *".test."* || "$BASENAME" == *".spec."* ]] && exit 0

# Solid (non-opacity) text-token used as a BACKGROUND — the white-on-white footgun. Excludes
# `/N` tints, the `-fg/-bg/-border` triad, and `-hover` (below). (border-/ring- with these text
# tokens render high-contrast and are not invisibility bugs, so they're not hard-flagged here.)
SOLID=$(grep -nP 'bg-theme-(primary|secondary|tertiary|quaternary)(?![\w/-])' "$FILE_PATH" 2>/dev/null | grep -vP '^\s*\d+:\s*(\*|//|/\*)')
# Inert token: --color-theme-{primary,...}-hover does not exist (only -interactive-primary-hover).
INERT=$(grep -nP 'theme-(primary|secondary|tertiary|quaternary)-hover\b' "$FILE_PATH" 2>/dev/null)

if [[ -n "$SOLID" || -n "$INERT" ]]; then
  echo "Advisory: theme TEXT tokens misused as a background in $FILE_PATH (white-on-white in dark mode)." >&2
  [[ -n "$SOLID" ]] && { echo "  bg-theme-{primary,secondary,tertiary,quaternary} → use bg-theme-surface* (panel) or bg-theme-interactive-primary (accent):" >&2; echo "$SOLID" >&2; }
  [[ -n "$INERT" ]] && { echo "  inert *-theme-*-hover (token doesn't exist) → use hover:bg-theme-interactive-primary-hover:" >&2; echo "$INERT" >&2; }
  echo "  Ref: docs/reference/theme-system.md (#1 footgun)" >&2
fi
exit 0
