#!/bin/bash
# SessionStart hook: injects a compact dev-guidance digest into the session.
#
# Sourced from the COMMITTED conventions docs (always available — no network,
# survives an MCP outage), pointing at the platform knowledge tags for full
# content (MCP-first). Bounded (titles/pointers only). NEVER blocks startup —
# always exit 0; if the docs are missing it degrades to silence.
#
# The "POWERNODE GUIDANCE" header is a sentinel: if it appears at the start of a
# fresh session, SessionStart context injection is working in this harness.
#
# ADVICE ONLY FOR VERBS THIS SESSION CAN CALL (IMP-fecf675bfc9f). The digest
# used to tell every session to "ask platform.route_task when unsure" as static
# prose, while the dev-cell's instance grant did not carry route_task — advice
# the reader could not follow. Every platform verb the digest recommends is now
# checked against the connector's own tools/list (one POST, the same endpoint
# resolution as subagent-report.sh). A verb the connector does not list is
# withheld from the advice and named on a "grant gap" line instead. When the
# listing cannot be read — no answer, no tool array, or only a first page — no
# platform verb is advertised and the digest says so; the committed-file
# pointers still print.
#
# Test seams (server/spec/hooks/session_guidance_inject_spec.rb):
#   POWERNODE_MCP_URL    the endpoint (a throwaway listener in the spec)
#   CLAUDE_PROJECT_DIR   where docs/ and .claude/agents/ live

# Drain stdin (SessionStart JSON) so the pipe never stalls; we don't need it.
cat >/dev/null 2>&1

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"
CONV="$PROJECT_DIR/docs/contributing/conventions"
[[ -d "$CONV" ]] || exit 0

# The platform verbs this digest recommends by name. Keep in step with the
# guarded advice lines below: a verb named in advice but missing here is never
# checked.
ADVISED_VERBS=(platform.search_knowledge platform.create_knowledge platform.route_task)

# --- which of them the connector lists --------------------------------------
# 3 s ceiling inside the hook's 5 s budget (a real tools/list is ~0.5-1.3 s).
listed=""
listing_error=""
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  listing_error="curl or jq is not installed"
else
  url="${POWERNODE_MCP_URL:-}"
  auth=""
  if [[ -z "$url" && -f "$HOME/.claude.json" ]]; then
    url="$(jq -r '.mcpServers.powernode.url // empty' "$HOME/.claude.json" 2>/dev/null)"
    auth="$(jq -r '.mcpServers.powernode.headers.Authorization // empty' "$HOME/.claude.json" 2>/dev/null)"
  fi
  [[ -n "$url" ]] || url="http://127.0.0.1:18443/mcp"

  request='{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
  # The credential goes to curl through a file descriptor, never its argv.
  if [[ -n "$auth" ]]; then
    response="$(curl -sS -m 3 --connect-timeout 1 -X POST "$url" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      -H @<(printf 'Authorization: %s\n' "$auth") --data-binary "$request" 2>/dev/null)"
  else
    response="$(curl -sS -m 3 --connect-timeout 1 -X POST "$url" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      --data-binary "$request" 2>/dev/null)"
  fi

  if [[ -z "$response" ]]; then
    listing_error="no response from the connector"
  else
    # A streamable-HTTP endpoint may frame the result as SSE. Detected by the
    # leading field names only: a plain JSON body can contain "data:" inside a
    # tool description. Every data payload is kept, and the tools/list reply is
    # picked out by its id, so a notification event before or after it is not
    # mistaken for the answer.
    payloads="$response"
    if [[ "$(printf '%s' "$response" | tr -d '\r' | sed -n '/[^[:space:]]/{p;q}')" =~ ^(event|data|id|retry|:) ]]; then
      payloads="$(printf '%s\n' "$response" | tr -d '\r' | sed -n 's/^data:[[:space:]]\{0,1\}//p')"
    fi
    result="$(printf '%s\n' "$payloads" | jq -c 'select(type == "object" and .id == 1 and (.result.tools | type) == "array") | .result' 2>/dev/null | head -1)"
    if [[ -z "$result" ]]; then
      listing_error="the connector's answer carried no tool list"
    elif [[ -n "$(jq -r '.nextCursor // empty' <<<"$result" 2>/dev/null)" ]]; then
      # A verb on a later page would read as a false grant gap.
      listing_error="the connector's tool list is paginated and only its first page was read"
    else
      listed="$(jq -r '.tools[]?.name // empty' <<<"$result" 2>/dev/null)"
    fi
  fi
fi

has_verb() { [[ -z "$listing_error" ]] && grep -qxF "$1" <<<"$listed"; }

missing=()
if [[ -z "$listing_error" ]]; then
  for verb in "${ADVISED_VERBS[@]}"; do has_verb "$verb" || missing+=("$verb"); done
fi

echo "=== POWERNODE GUIDANCE (auto-injected · SessionStart) ==="
echo "Safety-critical rules live in CLAUDE.md (always loaded). Mechanizable rules are enforced by"
echo ".claude/hooks/*.sh + scripts/pattern-validation.sh. Situational conventions below are in these files:"
for f in "$CONV"/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"
  case "$base" in MANIFEST.md|adherence-baseline.md|README.md) continue ;; esac
  title="$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^#[[:space:]]*//')"
  [[ -z "$title" ]] && title="$base"
  if has_verb platform.search_knowledge; then
    echo "  - ${title} → conventions/${base} (tag guidance-${base%.md})"
  else
    echo "  - ${title} → conventions/${base}"
  fi
done
if has_verb platform.search_knowledge; then
  echo "Each is also recallable via platform.search_knowledge tag:guidance-<name> (MCP-first)."
fi
echo "Deployment-local facts (this deployment's hosts/IPs/VM ids/remotes) are NEVER in tracked files."
if has_verb platform.search_knowledge; then
  echo "  Recall them via platform.search_knowledge tag:deployment-* (production connector)."
fi
if has_verb platform.create_knowledge; then
  echo "  Author them via platform.create_knowledge or docs/operations/local/ (gitignored)."
else
  echo "  Author them in docs/operations/local/ (gitignored)."
fi
echo "Improvement loop: /improve discover → approve → /dev-loop dev-improve (or delegate to a platform agent)."
# Platform agents as Claude Code subagents: count the committed canonical skeletons
# (no Rails boot — this hook has a 5 s budget). Regenerate after a seed/renderer change.
AGENTS_DIR="$PROJECT_DIR/.claude/agents/powernode"
agent_count=0
if [[ -d "$AGENTS_DIR" ]]; then
  for f in "$AGENTS_DIR"/*.md; do [[ -e "$f" ]] && agent_count=$((agent_count + 1)); done
fi
echo "Platform agents: ${agent_count} canonical platform agent(s) available as subagents (.claude/agents/powernode/, Agent(subagent_type: \"<slug>\"))."
if has_verb platform.route_task; then
  echo "  For platform work prefer these subagents over general-purpose; ask platform.route_task when unsure."
else
  echo "  For platform work prefer these subagents over general-purpose."
fi
echo "  Regenerate after a seed change: cd server && bundle exec rails claude:sync_agents (gate: scripts/check-claude-agents-fresh.sh)."
if [[ -n "$listing_error" ]]; then
  echo "Could not read the powernode connector's tools/list (${listing_error}), so no platform.* verb is advised above."
  echo "  Check a verb with ToolSearch before relying on it."
elif (( ${#missing[@]} > 0 )); then
  echo "Grant gap: this session's connector does not list ${missing[*]}, so advice naming them is withheld."
  echo "  For an instance principal an operator widens its grant (docs/operations/instance-principal-grant-survey-2026-08-15.md);"
  echo "  for a user session the account's permissions decide what is listed."
fi
echo "=== end guidance ==="
exit 0
