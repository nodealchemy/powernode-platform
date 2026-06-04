# Aspirational MCP Actions — Documented Backlog

> Status: active

The `check-mcp-actions.sh` harness may report unknown actions because
some docs reference `platform.X(...)` MCP syntax for actions that aren't
yet in the platform's `server/app/services/ai/tools/platform_api_tool_registry.rb`.

Each entry below is intentional: the doc shows the **intended** MCP
shape, with a callout explaining that the wrapper is forthcoming and
operators should use the REST endpoint today.

## Known-aspirational catalog (as of 2026-06-03)

The system extension maintains the authoritative aspirational list for its
`system_*` actions (`extensions/system/docs/.verify/ASPIRATIONAL_MCP.md`) — those
are out of scope here. Platform (non-system) actions the harness reports as unknown:

| Action | Doc | Note |
|--------|-----|------|
| `cost_analysis` | `docs/operations/incident-response.md` | Real MCP action exposed by the running server (present in the live tool list as `platform.cost_analysis`); not matched by the static `check-mcp-actions.sh` grep of `platform_api_tool_registry.rb`. Treat as an expected unknown — the documented usage is correct. |
| `recent_events` | `docs/operations/incident-response.md` | Real MCP action exposed by the running server (`platform.recent_events`); same static-grep limitation. Treat as an expected unknown. |

If the platform's `check-mcp-actions.sh` flags a non-system action that
should be aspirational rather than fixed in the docs, add a row in the
following form:

| Action | Doc | Operator workaround today |
|--------|-----|---------------------------|
| `<action_name>` | `docs/path/to/doc.md` | `<REST endpoint or alternative MCP call>` |

## When to use this list

- **Adding a new aspirational reference?** Append to the table above + add
  a comment-callout in the doc (`// aspirational MCP — use REST today`)
  + briefly explain the REST workaround at the call site
- **Implementing one of these wrappers?** Add the action to
  `server/app/services/ai/tools/platform_api_tool_registry.rb`, implement
  the action method in the corresponding tool class, then remove the row
- **Running the verification harness?** The `check-mcp-actions.sh` script
  will report listed entries as unknowns; this is expected. The script's
  exit 1 signals operators to check this catalog rather than treat it as
  a hard error

## Triage heuristics

When the harness reports an unknown action that's NOT in this catalog,
one of three things happened:

1. **A new aspirational reference** was added without updating this catalog → add it
2. **An action was renamed** in the registry and a doc still uses the old name → fix the doc
3. **A typo or accidental new doc reference** → fix the doc or remove

## Related

- [`README.md`](./README.md) — verification harness overview
- `../reference/auto/mcp-tools.md` — current platform MCP action catalog (auto-generated)
- `server/app/services/ai/tools/platform_api_tool_registry.rb` — source of truth for registered actions
- `extensions/system/docs/.verify/ASPIRATIONAL_MCP.md` — system extension's aspirational catalog (system_* actions)

_Last verified: 2026-06-04_
