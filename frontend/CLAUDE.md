# Frontend CLAUDE.md

React TypeScript frontend for Powernode.

## Critical Rules

- `currentUser?.permissions?.includes('name')` - NEVER check roles
- Theme classes only: `bg-theme-*`, `text-theme-*` - no hardcoded colors
- Flat navigation - no submenus
- Actions ALL in PageContainer - none in page content
- Global notifications only - no local success/error
- Imports: `@/shared/`, `@/features/` for cross-feature
- No `console.log` in production, no `any` types

## MCP-First Frontend Workflow

Query MCP before non-trivial frontend changes (full protocol: [conventions/mcp-first-workflow.md](../docs/contributing/conventions/mcp-first-workflow.md)).

### Starting a change

Before writing code for a non-trivial change:
1. `platform.query_learnings` — check for existing patterns/gotchas in the area being modified
2. `platform.search_knowledge` — find relevant procedures/references for the component/feature
3. `platform.search_knowledge_graph` — understand component relationships and page hierarchy

### Before Creating/Modifying

| Task | MCP Query |
|------|-----------|
| New component or page | `platform.discover_skills` + `platform.search_knowledge` query: "React component patterns" |
| Theme/styling changes | `platform.search_knowledge` query: "theme system" |
| Permission checks | `platform.search_knowledge` query: "permission system frontend" |
| State management | `platform.query_learnings` query: "state management" — known patterns and anti-patterns |
| Form implementation | `platform.search_knowledge` query: "form patterns" |
| AI feature UI | `platform.search_knowledge_graph` query: "AI frontend" — entity relationships, page structure |
| Autonomy dashboard/panels | `platform.search_knowledge` query: "autonomy dashboard" |
| Admin panel | `platform.search_knowledge` query: "admin panel" |
| API hooks / data fetching | `platform.query_learnings` query: "React hooks" — established fetch patterns |
| Agent/team UI | `platform.get_agent` / `platform.get_team` — understand data shapes |
| KB article UI | `platform.list_kb_articles` / `platform.get_kb_article` — check content structure |
| Page UI | `platform.list_pages` / `platform.get_page` — check page data model |
| Memory visualization | `platform.memory_stats` / `platform.search_memory` — understand memory tier data |

### During Work

- **Before new UI patterns**: `platform.query_learnings` — check if pattern is established or has known issues
- **Before component architecture decisions**: `platform.search_knowledge_graph` — understand feature-to-component relationships
- **Before adding dependencies**: `platform.query_learnings` query: "package name" — check for known integration gotchas

### After Work (MANDATORY for non-trivial changes)

| Change type | Contribution |
|-------------|-------------|
| New component pattern | `platform.create_learning` category: `pattern` — document the approach |
| UI bug fix | `platform.create_learning` category: `discovery` — root cause + fix |
| New feature page structure | `platform.extract_to_knowledge_graph` — page hierarchy, component relationships |
| Reusable hook or utility | `platform.create_skill` — codify the approach |

## Context-Aware Documentation (file fallback)

Query MCP first. Use these files when MCP returns no relevant results:

| When working on | MCP Query | File Fallback |
|-----------------|-----------|---------------|
| `features/ai/*` | `platform.search_knowledge` query: "AI frontend" | [concepts/agents-and-autonomy.md](../docs/concepts/agents-and-autonomy.md) |
| `shared/components/*` | `platform.search_knowledge` query: "UI components" | [guides/frontend.md](../docs/guides/frontend.md) |
| Theme/styling | `platform.search_knowledge` query: "theme system" | [reference/theme-system.md](../docs/reference/theme-system.md) |
| Permission checks | `platform.search_knowledge` query: "permission frontend" | [concepts/permissions.md](../docs/concepts/permissions.md) |
| Forms | `platform.search_knowledge` query: "form patterns" | [guides/frontend.md](../docs/guides/frontend.md) |
| State management | `platform.query_learnings` query: "state management" | [guides/frontend.md](../docs/guides/frontend.md) |
| `features/admin/*` | `platform.search_knowledge` query: "admin panel" | [guides/frontend.md](../docs/guides/frontend.md) |
| `features/ai/autonomy/*` | `platform.search_knowledge` query: "AI autonomy frontend" | [concepts/agents-and-autonomy.md](../docs/concepts/agents-and-autonomy.md) |

## MCP Tool Reference

Full tool catalog with parameters: [reference/auto/mcp-tools.md](../docs/reference/auto/mcp-tools.md). To load a tool's schema in a session, use ToolSearch (e.g. `select:mcp__powernode__platform_search_knowledge`).

## Key Specialists

Use `platform.discover_skills` with your task description first. File fallback:

- [Frontend guide](../docs/guides/frontend.md) — React architecture, UI components, dashboards, forms, state, plugin UI, WebSocket integration
