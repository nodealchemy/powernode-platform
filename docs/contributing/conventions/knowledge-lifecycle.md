# Knowledge Quality Lifecycle

The platform runs automated maintenance (see `worker/config/sidekiq.yml`); Claude Code participates in the quality loop. Full MCP tool list: [../../reference/auto/mcp-tools.md](../../reference/auto/mcp-tools.md).

## Automated (background jobs)

| Job | Schedule | Effect |
|-----|----------|--------|
| Compound learning decay | 3:45 AM daily | `importance_score` decays on stale learnings |
| Memory consolidation | 4:00 AM daily | STM→long-term (access≥3), dedup (similarity≥0.92) |
| Rot detection | 4:00 AM daily | Auto-archives context entries (staleness≥0.9) |
| Skill lifecycle | daily/weekly/monthly | Conflict scan, stale decay, re-embedding, gap detection |
| Shared knowledge maintenance | daily | Import from learnings, recalc quality, audit stale |
| Trajectory analysis | 5:00 AM daily | Execution-trajectory improvement recommendations |
| Intervention policy tuning | weekly | Analyze approval patterns, suggest policy adjustments |

## Manual (Claude Code responsibilities)

| Trigger | Tool |
|---------|------|
| Solved a non-trivial bug | `create_learning` (`discovery` / `failure_mode`) |
| Established/confirmed a pattern | `create_learning` (`pattern` / `best_practice`) |
| Documented a procedure | `create_knowledge` (`procedure`) |
| Found entity relationships | `extract_to_knowledge_graph` |
| Implemented a reusable capability | `create_skill` |
| Used a learning successfully / wrongly | `reinforce_learning` / `dispute_learning` |
| Found two conflicting learnings | `resolve_contradiction` |
| Read useful / outdated shared knowledge | `rate_knowledge` (4-5 / 1-2 + corrected `create_knowledge`) |
| Encountering a bug | `query_learnings` first — reinforce if found, fix + `create_learning` if not |

**Skip** for trivial fixes (typos, renames, formatting), speculative/unverified analysis, or knowledge that already exists.

## Tool Evolution

`platform.*` tools live in `server/app/services/ai/tools/platform_api_tool_registry.rb`. After adding/modifying, run `rails mcp:generate_tool_catalog`; `rails mcp:sync_docs` regenerates the broader fallback docs. For **new** tools, also add the name to the catalog and create a `pattern` learning. For **deprecations**, add a deprecation note in the action definition + a `best_practice` learning pointing at the replacement.
