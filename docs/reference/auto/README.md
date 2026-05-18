# Auto-Generated Reference Docs

Files in this directory are regenerated from platform data sources. **Do not edit by hand** — changes will be overwritten by the next regen.

See [manifest.yml](manifest.yml) for the regeneration command and source for each file.

## Regenerating

```bash
cd server
bundle exec rails mcp:generate_tool_catalog   # → mcp-tools.md
bundle exec rails mcp:sync_docs                # → skills.md, knowledge-base.md, knowledge-graph.md, learnings.md, todo.md
```

The `AiKnowledgeDocSyncJob` runs nightly at 5:30 AM UTC and regenerates the `mcp:sync_docs` outputs automatically.

## Verification

`docs/.verify/check-auto-gen-headers.sh` confirms every file here has the `<!-- AUTO-GENERATED -->` marker.

`docs/.verify/manifest.yml` drift is verified by CI (when wired).
