# Contributing to Powernode

Thanks for considering contributing to Powernode! This document covers how to get involved — filing issues, submitting changes, and the conventions we follow.

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you're expected to uphold this code. Report unacceptable behavior by opening a private GitHub Security Advisory on this repository (Settings → Security → Report a vulnerability — works for conduct issues too) or via [GitHub Discussions](https://github.com/nodealchemy/powernode-platform/discussions) for non-sensitive matters.

## Getting Started

### Setup

1. Read [`CLAUDE.md`](CLAUDE.md) — it covers the architecture, conventions, MCP-first workflow, and platform organization. The file is named for the AI assistant we use during development, but the conventions apply to all contributors.
2. Follow setup in [`README.md`](README.md) for installing dependencies and running the platform locally.
3. **Set up extension frontend symlinks** (one-time, after `cd frontend && npm install`):
   ```bash
   ./scripts/setup-extension-frontend-symlinks.sh
   ```
   This creates `extensions/<ext>/frontend/node_modules` symlinks to the parent's `frontend/node_modules` so extension Jest tests can resolve dependencies. The symlinks are gitignored; the script is idempotent.
4. Run the test suite to confirm your environment works:
   ```bash
   cd server && bundle exec rspec --format progress
   cd frontend && CI=true npm test
   ```

### Repository Layout

- `server/` — Rails 8 API backend
- `frontend/` — React 19 / TypeScript frontend
- `worker/` — Standalone Sidekiq worker (HTTP-only API to server, never imports server code)
- `extensions/` — Optional feature extensions: `business` (billing/SaaS), `marketing` (campaigns/landing pages), `system` (fleet/edge), `supply-chain` (SBOM/attestations)
- `docs/` — Architecture, feature, and platform documentation
- `scripts/` — Build, validation, and utility scripts

## Filing Issues

Use the appropriate template:

- **Bug reports** — for things that are broken (use the bug report template)
- **Feature requests** — for proposals (new capability, integration, or workflow)
- **Deployment / self-hosting help** — for setup and core-mode questions (use the deployment help template)
- **Security issues** — **DO NOT file as public issues.** Open a [private GitHub Security Advisory](https://github.com/nodealchemy/powernode-platform/security/advisories/new) with details; see [SECURITY.md](SECURITY.md) for our response targets and coordinated-disclosure process.

When filing a bug or feature request, identify the affected **stability tier** (see [docs/STABILITY.md](docs/STABILITY.md)) — it helps us route and prioritize.

Please search existing issues first to avoid duplicates.

## Submitting Pull Requests

1. **Fork the repo** and create a feature branch from `develop`:
   ```bash
   git checkout -b feature/your-change-name develop
   ```
2. **Branch strategy**: PRs target `develop`. The release flow is `develop → release/x.y.z → master`.
3. **Make focused changes**: one PR = one logical change. Smaller PRs review faster and ship sooner.
4. **Follow the conventions** documented in `CLAUDE.md`. Highlights:
   - **Frontend permissions**: `currentUser?.permissions?.includes('name')` — NEVER check roles
   - **Theme classes only**: `bg-theme-*`, `text-theme-*` — no hardcoded colors
   - **API responses**: `render_success()` / `render_error()` — never bare `render`
   - **Ruby pragma**: `# frozen_string_literal: true` on every `.rb` file
   - **Frontend logging**: `import { logger } from '@/shared/utils/logger'` — no `console.log` in production code
   - **TypeScript**: no `any` types — proper types required
5. **Add tests** for new behavior:
   - Backend: `spec/` (RSpec) — see existing patterns in `spec/factories/`, `spec/support/`
   - Frontend: `*.test.tsx` (Jest) — see existing component tests
   - E2E: `e2e/` (Playwright) — see `e2e/pages/` for page objects
6. **Run validation** before pushing:
   ```bash
   ./scripts/validate.sh
   ```
   Or for a quicker subset: `./scripts/validate.sh --skip-tests`
7. **Commit messages**: `type(scope): subject` — e.g., `feat(marketing): add waitlist signup endpoint`. See recent `git log --oneline` for style.
8. **No AI-assistant attribution** in commit messages (no "Co-Authored-By: Claude", etc.) — keep them clean.

## What We're Looking For

- Bug fixes (especially with regression tests)
- Documentation improvements
- New extensions (see `extensions/` for shape — `system`, `marketing`, `business`)
- Integration adapters: Claude Agent SDK, LangGraph, Mastra, OpenAI Agents SDK, AutoGen, Vercel AI SDK
- Performance improvements with measurements
- Test coverage in under-tested areas (the `extensions/business/spec/` directory in particular)
- Accessibility improvements with `data-testid` and ARIA labels

## What We're Not Looking For (right now)

- Cosmetic refactors without functional change
- Style-only PRs that fight existing patterns
- Breaking changes without prior issue discussion
- Auto-generated content (typo-fix bots, dependency-update spam unrelated to security)
- License changes (we're staying MIT — see [`LICENSE`](LICENSE))

## Development Workflow

- Read [`CLAUDE.md`](CLAUDE.md) for the full MCP-first workflow if you're using AI assistance
- Run `cd frontend && npx tsc --noEmit` after TypeScript changes
- Run `cd server && bundle exec rspec spec/path/to/relevant_spec.rb` for targeted backend specs
- Never run the full RSpec suite — only changed-file specs (the suite is large and slow)
- Use `./scripts/validate.sh` as a pre-push checklist

## Service Management (development)

Local services run via systemd. After installing:
```bash
sudo scripts/systemd/powernode-installer.sh install
sudo systemctl start powernode.target
```

Then `journalctl -u powernode-backend@default -f` to tail logs.

**Never** use manual commands (`rails server`, `sidekiq`, `npm start`) for production workflows — they bypass the health-check infrastructure.

## Communication

- **[GitHub Issues](https://github.com/nodealchemy/powernode-platform/issues)** — best for bugs and feature requests
- **[GitHub Discussions](https://github.com/nodealchemy/powernode-platform/discussions)** — best for design questions, ideas, "is this approach right?"
- **[GitHub Security Advisories](https://github.com/nodealchemy/powernode-platform/security/advisories/new)** — for private questions or security reports

## Documentation conventions

Powernode's docs follow a few clear rules. See [docs/contributing/doc-conventions.md](docs/contributing/doc-conventions.md) for the full reference.

- **Auto-generated docs** live in `docs/reference/auto/` and carry an `<!-- AUTO-GENERATED -->` header. Never edit them — they are regenerated from platform data.
- **Active docs** end with a `_Last verified: YYYY-MM-DD_` footer.
- **Diagrams** use Mermaid fenced code blocks, not ASCII or SVG.
- **Links** are relative and resolve on disk (see `docs/.verify/check-links.sh` once wired in Wave 4).
- **Counts** (number of tools, tables, etc.) link to the live source (`docs/reference/auto/mcp-tools.md`) — never inline.

## Contributor License Agreement

Powernode follows an open-core model: the platform and its public extensions (`system`, `supply-chain`, `marketing`) are MIT-licensed and always will be, while a separate commercial `business` extension is offered under a commercial license. Because the same code is offered under more than one license, contributors sign a Contributor License Agreement ([CLA.md](CLA.md)) granting Node Alchemy LLC the right to relicense their contributions. You keep full ownership of your work; the CLA only grants the licensing rights needed to support both the open-source project and a commercial edition. Contributions to the public repositories remain available under the [MIT License](LICENSE).

Thanks for being part of Powernode!
