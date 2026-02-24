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

**Always query MCP before writing frontend code.** This is mandatory, not optional.

### Session Start (MANDATORY — every session touching frontend code)

Before writing any code:
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
| Admin panel | `platform.search_knowledge` query: "admin panel" |
| API hooks / data fetching | `platform.query_learnings` query: "React hooks" — established fetch patterns |
| Agent/team/workflow UI | `platform.get_agent` / `platform.get_team` / `platform.get_workflow` — understand data shapes |
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
| `features/ai/*` | `platform.search_knowledge` query: "AI frontend workflow" | [WORKFLOW_FRONTEND_GUIDE.md](../docs/frontend/WORKFLOW_FRONTEND_GUIDE.md) |
| `shared/components/*` | `platform.search_knowledge` query: "UI components" | [UI_COMPONENT_DEVELOPER_SPECIALIST.md](../docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md) |
| Theme/styling | `platform.search_knowledge` query: "theme system" | [THEME_SYSTEM_REFERENCE.md](../docs/platform/THEME_SYSTEM_REFERENCE.md) |
| Permission checks | `platform.search_knowledge` query: "permission frontend" | [PERMISSION_SYSTEM_REFERENCE.md](../docs/platform/PERMISSION_SYSTEM_REFERENCE.md) |
| Forms | `platform.search_knowledge` query: "form patterns" | [FORM_PATTERNS.md](../docs/frontend/FORM_PATTERNS.md) |
| State management | `platform.query_learnings` query: "state management" | [STATE_MANAGEMENT_GUIDE.md](../docs/frontend/STATE_MANAGEMENT_GUIDE.md) |
| `features/admin/*` | `platform.search_knowledge` query: "admin panel" | [ADMIN_PANEL_DEVELOPER_SPECIALIST.md](../docs/frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md) |

## Frontend-Relevant MCP Tools

Scoped to tools useful for frontend development. Full catalog: [MCP_TOOL_CATALOG.md](../docs/platform/MCP_TOOL_CATALOG.md).

### Context & Discovery
| Tool | Use Case |
|------|----------|
| `search_knowledge` | Find procedures, patterns, and code snippets |
| `query_learnings` | Check for known UI anti-patterns and gotchas |
| `search_knowledge_graph` | Understand entity relationships for page/component design |
| `reason_knowledge_graph` | Multi-hop reasoning for complex feature dependencies |
| `discover_skills` | Find reusable capabilities matching the UI task |
| `get_skill_context` | Get full execution context for a discovered skill |
| `search_memory` | Search agent memory for relevant working context |
| `get_api_reference` | Look up API endpoint contracts for hook implementation |

### Understanding AI Feature Data (read-only)
| Tool | Use Case |
|------|----------|
| `list_agents` / `get_agent` | Understand agent data shape for agent management UI |
| `list_teams` / `get_team` | Understand team data shape for team management UI |
| `list_workflows` / `get_workflow` | Understand workflow data shape for workflow builder UI |
| `list_skills` / `get_skill` | Understand skill data shape for skill browser UI |
| `list_kb_articles` / `get_kb_article` | Understand article data shape for KB UI |
| `list_pages` / `get_page` | Understand page data shape for CMS UI |
| `list_graph_nodes` / `get_graph_neighbors` | Understand graph data shape for visualization |
| `memory_stats` | Understand memory tier data for dashboard widgets |

### Knowledge Contribution
| Tool | Use Case |
|------|----------|
| `create_learning` | Document UI patterns and component decisions |
| `create_knowledge` | Create reference docs for new component patterns |
| `create_skill` | Register reusable hooks or utilities as skills |
| `extract_to_knowledge_graph` | Record page hierarchy and component relationships |
| `verify_learning` | Verify a learning used during UI implementation |
| `rate_knowledge` | Rate shared knowledge quality after using it |
| `knowledge_health` | Run diagnostics on knowledge system health |

**Excluded**: Backend write operations (agent/team/workflow CRUD), DevOps tools, RAG processing, memory write/consolidation, skill admin, knowledge curation. See root [CLAUDE.md](../CLAUDE.md) for the full catalog.

## Key Specialists

Use `platform.discover_skills` with your task description first. File fallbacks:

- [React Architect](../docs/frontend/REACT_ARCHITECT_SPECIALIST.md)
- [UI Components](../docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md)
- [Dashboard](../docs/frontend/DASHBOARD_SPECIALIST.md)
