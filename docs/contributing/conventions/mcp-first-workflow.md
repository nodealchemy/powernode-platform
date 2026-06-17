# MCP-First Development Workflow

The Powernode MCP server (`platform.*` tools) is the **primary knowledge source**; file scanning is the fallback. These queries are mandatory protocol steps for non-trivial work, not optional. The full tool catalog lives in [../../reference/auto/mcp-tools.md](../../reference/auto/mcp-tools.md) (regenerate via `rails mcp:generate_tool_catalog`).

> The per-subsystem variants of this protocol live in the nested `server/CLAUDE.md`, `frontend/CLAUDE.md`, and `worker/CLAUDE.md`, which load automatically when you edit those trees.

## Session Start (every session)

1. `platform.knowledge_health` — baseline; identify stale/conflicting knowledge
2. `platform.learning_metrics` — active learnings, recent contributions
3. If stale_count > 0 or conflicts, note for resolution
4. `platform.code_index_status` `repository_id: "powernode-platform"` — index freshness

## Before every code change

1. Search existing knowledge for the area: `platform.query_learnings`, `platform.search_knowledge`, `platform.search_knowledge_graph`, `platform.discover_skills`, `platform.code_semantic_search`, `platform.code_identifier_search`
2. Understand impact: `platform.code_blast_radius`, `platform.code_file_skeleton`
3. Apply discovered knowledge; fall back to file scanning only when MCP returns nothing; feed file-scan discoveries back into MCP

## During work

- Relying on a learning → `platform.reinforce_learning` (prevents decay)
- Using shared knowledge → `platform.rate_knowledge` (4-5 helpful, 1-2 outdated)
- Conflicting learnings → `platform.resolve_contradiction`
- Cross-cutting change → `platform.search_knowledge_graph`; structure → `platform.code_context_tree`; impact → `platform.code_blast_radius`

## After every task (non-trivial)

Contribute via the [knowledge-lifecycle.md](knowledge-lifecycle.md) responsibilities table. Skip for trivial fixes, speculative analysis, or knowledge that already exists. Self-check: "Did I create learnings for the critical findings?"

## Invocation

Claude Code invokes `platform.*` tools directly via the streamable-http MCP server in `.claude/settings.json` (`powernode` → `http://localhost:3000/api/v1/mcp/message`). No external daemon.
