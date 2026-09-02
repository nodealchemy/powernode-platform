# Auto-Generated Reference Docs

Files in this directory are regenerated from platform sources. **Do not edit by hand** — changes will be overwritten by the next regen.

## Tracking policy

This directory follows a split policy: docs sourced from **static code** are committed to git; docs sourced from **runtime database state** are local-only.

| File | Source | Tracked? | Regen command | Cadence |
|------|--------|----------|---------------|---------|
| `mcp-tools.md` | `Ai::Tools::PlatformApiToolRegistry.all_tools` (Ruby code, public-bundle rendering — see note below) | ✅ Yes | `bundle exec rails mcp:generate_tool_catalog` | On tool-class change (manual) |
| `skills.md` | `ai_skills` table | ❌ No | `bundle exec rails mcp:sync_docs` | Nightly via `AiKnowledgeDocSyncJob` |
| `knowledge-base.md` | `ai_shared_knowledges` table | ❌ No | `bundle exec rails mcp:sync_docs` | Nightly |
| `knowledge-graph.md` | `ai_knowledge_graph_nodes` + edges | ❌ No | `bundle exec rails mcp:sync_docs` | Nightly |
| `learnings.md` | `ai_compound_learnings` (active) | ❌ No | `bundle exec rails mcp:sync_docs` | Nightly |
| `todo.md` | `ai_shared_knowledges` (tag=todo) | ❌ No | `bundle exec rails mcp:sync_docs` | Nightly |

**Catalog scope.** `Ai::Tools::PlatformApiToolRegistry.all_tools` is the static core `TOOLS` merged with whatever tools the loaded extension engines registered, so the generator's output depends on the bundle it runs in. The **tracked** `mcp-tools.md` is the **public-bundle** rendering; `scripts/check-mcp-catalog-fresh.sh` pins that environment (`BUNDLE_GEMFILE` unset, `POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0`, `POWERNODE_DEPLOYED=0`) when it regenerates, so a copy generated with private extensions loaded fails the freshness gate rather than being committed to a publicly mirrored file. Regenerate a full local catalog for an environment with extensions loaded if you need one — just don't commit it.

**Why split?** The MCP tool catalog reflects platform code — it changes only when developers add tool classes, so committing it gives OSS visitors a browsable reference without daily churn. The five DB-backed files reflect account-specific runtime state — they change with normal platform use, so committing them would create dozens of churn commits per week and leak account data into the public mirror.

For the DB-backed registries, **query MCP directly** instead of reading the local Markdown snapshot:

- `platform.list_skills`, `platform.discover_skills`
- `platform.search_knowledge`, `platform.query_learnings`
- `platform.search_knowledge_graph`, `platform.list_graph_nodes`

If you want a local Markdown snapshot for browsing, run `cd server && bundle exec rails mcp:sync_docs` — the outputs land in this directory but stay untracked.

## Verification

`docs/.verify/check-auto-gen-headers.sh` confirms every auto-generated file here begins with the `<!-- AUTO-GENERATED -->` marker. Hand-edits to tracked auto-gen files are rejected by the harness at push time.

The `manifest.yml` next to this README is the machine-readable source of truth for each file's regeneration command and source.
