# Powernode Documentation

Open-source mission control for AI agent fleets.

## Start here

1. **Run it locally** → [getting-started/01-quickstart.md](getting-started/01-quickstart.md)
2. **Ship your first agent** → [getting-started/02-first-agent.md](getting-started/02-first-agent.md)
3. **Understand the architecture** → [concepts/architecture.md](concepts/architecture.md)
4. **Operate it in production** → [operations/production-deployment.md](operations/production-deployment.md)
5. **Contribute** → [contributing/development-setup.md](contributing/development-setup.md)

## Documentation map

| Tree | Purpose |
|------|---------|
| [getting-started/](getting-started/) | Tutorials for first-time users |
| [concepts/](concepts/) | Architecture, agents, knowledge/memory, permissions, data model, MCP, chat/realtime, cost |
| [guides/](guides/) | Role-themed how-to: backend, frontend, testing, devops, security, extensions, etc. |
| [reference/](reference/) | API contracts, database schema, scripts, theme system, plugin system |
| [reference/auto/](reference/auto/) | **Auto-generated** — MCP tool catalog (do not edit; other DB-backed registries are queried live via MCP) |
| [operations/](operations/) | Production runbooks: deployment, docker swarm, AI ops, worker ops, perf tuning |
| [contributing/](contributing/) | Dev setup, conventions, GitHub workflow, doc conventions, release process |
| [history/](history/) | Archived audits and plans — preserved for context |

## Conventions

- Auto-generated files carry an `<!-- AUTO-GENERATED -->` header. Do not edit by hand.
- Archived files in `history/` carry an `**ARCHIVED**` banner.
- All active docs end with a `_Last verified:_` footer.
- See [contributing/doc-conventions.md](contributing/doc-conventions.md) for the full conventions.

_Last verified: 2026-05-17_
