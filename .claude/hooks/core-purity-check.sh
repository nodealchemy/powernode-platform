#!/bin/bash
# BLOCKING hook (gate #9): bars a CORE source file from referencing a SPECIFIC
# private extension. Core = any path NOT under extensions/. A *generic* reference
# to the extensions/ or extensions/private/ directory (the decoupling seam) is
# allowed; naming a specific private extension is a leak — its Ruby namespace
# (e.g. Trading::), its submodule path (extensions/private/trading) or its import
# alias (@ext/trading/, @business/).
#
# Private-extension names are derived dynamically from extensions/private/* on
# disk, so this public hook never hardcodes one. Fails OPEN (exit 0) on any
# uncertainty so it can never block an unrelated edit; exits 2 only on a clear,
# structural private-extension reference in a core source file.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# Only source code can create a code-level dependency.
case "$FILE_PATH" in
  *.rb|*.ts|*.tsx|*.js|*.jsx) ;;
  *) exit 0 ;;
esac

# A file inside an extension may reference its own namespace.
[[ "$FILE_PATH" == *"/extensions/"* ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"

# Derive private-extension names dynamically — never hardcode them here.
shopt -s nullglob
priv_names=()
for d in "$PROJECT_DIR"/extensions/private/*/; do
  [[ -d "$d" ]] || continue
  priv_names+=("$(basename "$d")")
done
shopt -u nullglob
[[ ${#priv_names[@]} -eq 0 ]] && exit 0

HITS=""
for name in "${priv_names[@]}"; do
  cap="${name^}"
  # Structural references only: namespace ::, submodule path, import alias.
  pat="(\b${cap}::)|(extensions/private/${name}\b)|(@ext/${name}/)|(@${name}/)"
  m=$(grep -nE "$pat" "$FILE_PATH" 2>/dev/null)
  if [[ -n "$m" ]]; then
    HITS+="  [private extension: ${name}]"$'\n'"${m}"$'\n'
  fi
done

if [[ -n "$HITS" ]]; then
  {
    echo "BLOCKED (core-purity / gate #9): $FILE_PATH is a CORE file but names a private extension."
    echo "$HITS"
    echo "Core must never depend on a private extension. Either move this logic into the extension,"
    echo "or route through a generic seam (e.g. register_extension_tools / a provider) that does not name it."
    echo "Maintainer-only notes that must name a private extension belong in CLAUDE.local.md."
  } >&2
  exit 2
fi
exit 0
