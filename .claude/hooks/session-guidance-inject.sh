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

# Drain stdin (SessionStart JSON) so the pipe never stalls; we don't need it.
cat >/dev/null 2>&1

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"
CONV="$PROJECT_DIR/docs/contributing/conventions"
[[ -d "$CONV" ]] || exit 0

echo "=== POWERNODE GUIDANCE (auto-injected · SessionStart) ==="
echo "Safety-critical rules live in CLAUDE.md (always loaded). Mechanizable rules are enforced by"
echo ".claude/hooks/*.sh + scripts/pattern-validation.sh. Situational conventions below are recallable"
echo "via platform.search_knowledge tag:guidance-<name> (MCP-first) or by reading the file:"
for f in "$CONV"/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"
  case "$base" in MANIFEST.md|adherence-baseline.md|README.md) continue ;; esac
  title="$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^#[[:space:]]*//')"
  [[ -z "$title" ]] && title="$base"
  echo "  - ${title} → conventions/${base} (tag guidance-${base%.md})"
done
echo "Improvement loop: /improve discover → approve → /dev-loop dev-improve (or delegate to a platform agent)."
# Platform agents as Claude Code subagents: count the committed canonical skeletons
# (no Rails boot — this hook has a 5 s budget). Regenerate after a seed/renderer change.
AGENTS_DIR="$PROJECT_DIR/.claude/agents/powernode"
agent_count=0
if [[ -d "$AGENTS_DIR" ]]; then
  for f in "$AGENTS_DIR"/*.md; do [[ -e "$f" ]] && agent_count=$((agent_count + 1)); done
fi
echo "Platform agents: ${agent_count} canonical platform agent(s) available as subagents (.claude/agents/powernode/, Agent(subagent_type: \"<slug>\"))."
echo "  For platform work prefer these subagents over general-purpose; ask platform.route_task when unsure."
echo "  Regenerate after a seed change: cd server && bundle exec rails claude:sync_agents (gate: scripts/check-claude-agents-fresh.sh)."
echo "=== end guidance ==="
exit 0
