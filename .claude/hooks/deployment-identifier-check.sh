#!/bin/bash
# BLOCKING hook: a deployment-local identifier (this deployment's hostname, internal
# IP range, VM id, operator mailbox, ...) must never land in a git-tracked file.
# Such facts belong in the deployment's own platform knowledge store (tag
# `deployment-*`) or a gitignored local file — see
# docs/contributing/conventions/deployment-knowledge.md.
#
# One rule, one implementation: this hook delegates to the model-agnostic scan
# scripts/checks/deployment-identifier-check.sh (--file mode), which is also run
# over the whole tree by scripts/pattern-validation.sh. The identifier patterns
# come from the gitignored .claude/hooks/deployment-identifiers.local.txt; this
# hook never hardcodes one (a committed denylist would be the leak it guards
# against). No list => no-op. Gitignored targets => no-op. Fails OPEN on any
# uncertainty (missing jq, out-of-repo path, unreadable script); exits 2 only on
# a clear hit in a file git would track.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"
SCAN="$PROJECT_DIR/scripts/checks/deployment-identifier-check.sh"
[[ -r "$SCAN" ]] || exit 0

# Only files inside THIS repo or one of its extension submodules are in scope.
FILE_TOPLEVEL=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
PROJECT_TOPLEVEL=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$FILE_TOPLEVEL" || -z "$PROJECT_TOPLEVEL" ]] \
   || { [[ "$FILE_TOPLEVEL" != "$PROJECT_TOPLEVEL" ]] \
        && [[ "$FILE_TOPLEVEL" != "$PROJECT_TOPLEVEL"/extensions/* ]]; }; then
  exit 0
fi
# Private extensions are not published; the scan skips them and so does the hook.
[[ "$FILE_TOPLEVEL" == "$PROJECT_TOPLEVEL"/extensions/private/* ]] && exit 0

HITS=$(DEPLOYMENT_ID_ROOT="$PROJECT_TOPLEVEL" bash "$SCAN" --file "$FILE_PATH" 2>/dev/null)
rc=$?
[[ $rc -ne 2 ]] && exit 0

{
  echo "BLOCKED (deployment-identifier leak): $FILE_PATH names a DEPLOYMENT-LOCAL identifier in a file git tracks."
  printf '%s\n' "$HITS" | sed 's/^/  /'
  echo "Hostnames, internal IPs, VM ids and operator details of THIS deployment are irrelevant to every"
  echo "other deployment and a gratuitous disclosure on the public mirror. Genericize the text"
  echo "(<hub-host>, an example.test name, an RFC 5737 address) and keep the real value in"
  echo "platform knowledge: create_knowledge with tags [\"deployment\",\"deployment-<topic>\"],"
  echo "access_level \"account\" — or under the gitignored docs/operations/local/ and run"
  echo "\`rails ai:seed_deployment_knowledge\`. Convention: docs/contributing/conventions/deployment-knowledge.md"
} >&2
exit 2
