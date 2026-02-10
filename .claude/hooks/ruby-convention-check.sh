#!/bin/bash
# Advisory hook: checks Ruby naming conventions, FK prefixes, JSON defaults, and migration indexes
# Exit 0 always (advisory) — warnings printed to stderr

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ "$FILE_PATH" != *.rb ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

WARNINGS=""

# --- Namespace class_name checks ---
# All namespaced models MUST use :: separator, not flat concatenation
# Check for flat namespace references in class_name strings and class definitions
NAMESPACES="Ai|Devops|BaaS|Baas|Chat|KnowledgeBase|FileManagement|SupplyChain|Monitoring|Marketplace|Review|Account|DataManagement"

# Check class_name: "FlatName" patterns (e.g., class_name: "AiAgentTeam" instead of "Ai::AgentTeam")
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  WARNINGS="${WARNINGS}${line}\n"
done < <(grep -nP "class_name:\s*['\"]($NAMESPACES)[A-Z][a-zA-Z]*['\"]" "$FILE_PATH" 2>/dev/null | grep -vP "::")

# Check class definitions (e.g., class AiAgentTeam instead of class Ai::AgentTeam)
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  WARNINGS="${WARNINGS}${line}\n"
done < <(grep -nP "^\s*class\s+($NAMESPACES)[A-Z][a-zA-Z]+" "$FILE_PATH" 2>/dev/null | grep -vP "::")

# --- FK prefix checks for namespaced models ---
# Ai:: models should use ai_ prefix on FKs
if echo "$FILE_PATH" | grep -qP "(models/ai/|migrate/)"; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Check for bare agent_id, provider_id, workflow_id without ai_ prefix in Ai:: context
    if echo "$line" | grep -qP "(belongs_to|has_many|has_one|references)" && echo "$line" | grep -qP "class_name:.*Ai::"; then
      if echo "$line" | grep -qP "foreign_key:.*['\"](?!ai_)" 2>/dev/null; then
        WARNINGS="${WARNINGS}Warning: Ai:: association should use ai_ FK prefix: ${line}\n"
      fi
    fi
  done < <(grep -nP "(belongs_to|has_many|has_one)" "$FILE_PATH" 2>/dev/null)
fi

# Devops:: models should use ci_cd_ prefix on FKs
if echo "$FILE_PATH" | grep -qP "(models/devops/|models/ci_cd/|migrate/)"; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if echo "$line" | grep -qP "class_name:.*Devops::" && echo "$line" | grep -qP "foreign_key:" ; then
      if ! echo "$line" | grep -qP "foreign_key:.*ci_cd_" 2>/dev/null; then
        WARNINGS="${WARNINGS}Warning: Devops:: association should use ci_cd_ FK prefix: ${line}\n"
      fi
    fi
  done < <(grep -nP "(belongs_to|has_many|has_one)" "$FILE_PATH" 2>/dev/null)
fi

# BaaS:: models should use baas_ prefix on FKs
if echo "$FILE_PATH" | grep -qP "(models/baas/|models/ba_as/|migrate/)"; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if echo "$line" | grep -qP "class_name:.*BaaS::" && echo "$line" | grep -qP "foreign_key:" ; then
      if ! echo "$line" | grep -qP "foreign_key:.*baas_" 2>/dev/null; then
        WARNINGS="${WARNINGS}Warning: BaaS:: association should use baas_ FK prefix: ${line}\n"
      fi
    fi
  done < <(grep -nP "(belongs_to|has_many|has_one)" "$FILE_PATH" 2>/dev/null)
fi

# --- JSON default check ---
# Warn on default: {} (should be default: -> { {} })
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  WARNINGS="${WARNINGS}Warning: Use lambda default: -> { {} } instead of literal default: ${line}\n"
done < <(grep -nP "default:\s*\{\s*\}" "$FILE_PATH" 2>/dev/null | grep -vP "default:\s*->\s*\{")

# --- class_name/foreign_key pairing ---
# Warn when class_name: appears without foreign_key: on the same line
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  WARNINGS="${WARNINGS}Warning: class_name: without foreign_key: — always pair them: ${line}\n"
done < <(grep -nP "class_name:" "$FILE_PATH" 2>/dev/null | grep -vP "foreign_key:")

# --- Migration index check ---
# In migration files, warn if add_index follows t.references for the same column
if echo "$FILE_PATH" | grep -qP "db/migrate/"; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    COL=$(echo "$line" | grep -oP 'add_index\s+:\w+,\s*:(\w+)' | grep -oP ':\w+$' | tail -1)
    if [[ -n "$COL" ]]; then
      REF_COL=$(echo "$COL" | sed 's/^://' | sed 's/_id$//')
      if grep -qP "t\.references\s+:$REF_COL" "$FILE_PATH" 2>/dev/null; then
        WARNINGS="${WARNINGS}Warning: Separate add_index for t.references column ${COL} — use inline index: option instead: ${line}\n"
      fi
    fi
  done < <(grep -nP "add_index" "$FILE_PATH" 2>/dev/null)
fi

# --- Output warnings ---
if [[ -n "$WARNINGS" ]]; then
  echo -e "Ruby convention warnings in $FILE_PATH:" >&2
  echo -e "$WARNINGS" >&2
fi
exit 0
