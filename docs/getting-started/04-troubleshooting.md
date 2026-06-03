# Troubleshooting

> Common errors and their fixes, extracted from the platform conventions documented in CLAUDE.md.

> Status: active

If you hit a problem during install or first run, scan this page before diving into source. Most issues are caused by a small number of recurring traps — wrong service for a port, wrong auth route, wrong theme class, wrong permission check.

## Table of Contents

- [Services and ports](#services-and-ports)
- [Authentication and JWTs](#authentication-and-jwts)
- [Permissions vs roles](#permissions-vs-roles)
- [Theme classes that do not exist](#theme-classes-that-do-not-exist)
- [Seed and migration failures](#seed-and-migration-failures)
- [Frontend type errors](#frontend-type-errors)
- [Worker behavior](#worker-behavior)
- [Submodule confusion](#submodule-confusion)
- [Where to ask](#where-to-ask)

## Services and ports

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `connection refused` on port 3000 | Backend not running | `sudo systemctl status powernode-backend@default`; restart if dead |
| `connection refused` on port 4567 | Worker HTTP API down (NOT the Sidekiq process) | Restart `powernode-worker-web@default`, not `powernode-worker@default` |
| `connection refused` on port 5173 | Frontend dev server stopped | `sudo systemctl restart powernode-frontend@default` |
| Two backends fighting for 3000 | Manual `rails server` started alongside the systemd unit | Kill the manual process; rely on the systemd unit |
| Worker stuck "deactivating" | Sidekiq draining in-flight jobs | Wait 30 s; if still stuck, `stop` + `start` (not `restart`) |

Service unit names:

- `powernode-backend@default` (Rails API, port 3000)
- `powernode-worker@default` (Sidekiq, no HTTP port)
- `powernode-worker-web@default` (worker HTTP control plane, port 4567)
- `powernode-frontend@default` (Vite, port 5173)

## Authentication and JWTs

There are two authentication surfaces. Confusing them is the most common new-contributor trap:

| Surface | Used by | Token shape |
|---------|---------|-------------|
| `/api/v1/auth/login` (primary) | Frontend, scripts, MCP clients | JWT with `sub` claim = user UUID |
| OAuth provider endpoints | External integrations | OAuth access tokens |

If you are scripting against the API:

```bash
# Get a JWT — the field is "access_token", NOT "token"
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@powernode.org","password":"..."}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['access_token'])"
```

Use the JWT as `Authorization: Bearer <token>`.

If you see a 401 with no obvious reason, check that the token is fresh (`exp` in the payload), that the user still exists, and that the route is one of the JWT-protected routes (some `/public/*` routes intentionally reject JWTs).

## Permissions vs roles

**Frontend MUST use permissions, never roles.**

```typescript
// CORRECT
currentUser?.permissions?.includes('users.manage')

// FORBIDDEN — roles are an implementation detail
currentUser?.roles?.includes('admin')
user.role === 'manager'
```

**Backend MUST use the helper, never raw array checks:**

```ruby
# CORRECT
current_user.has_permission?('users.manage')

# WRONG — current_user.permissions returns Permission objects, not strings
current_user.permissions.include?('users.manage')
```

If a user is being denied access they should have, check:

1. Is the permission on the user's role assignments? (`User.find(id).permissions.pluck(:name)`)
2. Is the controller calling `authorize!('permission.name')` with the right name?
3. Is the frontend gating on the same permission string?

## Theme classes that do not exist

A handful of theme class names look plausible but **do not exist** in our Tailwind config:

| Wrong | Right |
|-------|-------|
| `bg-theme-secondary` | `bg-theme-surface` |
| `bg-theme-tertiary` | `bg-theme-background-secondary` |
| `bg-theme-success-bg` | `bg-theme-success` (no `-bg` suffix) |
| `bg-theme-warning-bg` | `bg-theme-warning` |
| `bg-theme-danger-bg` | `bg-theme-danger` |
| `bg-theme-info-bg` | `bg-theme-info` |

Using one of the wrong names compiles fine (Tailwind is permissive) but produces invisible white-on-white surfaces at runtime. If a page renders blank or with mystery white blocks, run `rg "bg-theme-(secondary|tertiary|.*-bg)" frontend/src/` and fix the matches.

The canonical theme reference is [reference/theme-system.md](../reference/theme-system.md).

## Seed and migration failures

```bash
# Migrations
cd server && bundle exec rails db:migrate:status

# Re-run seeds (after fixing the underlying issue)
cd server && bundle exec rails db:seed

# Nuclear option — only when you can afford to lose local data
cd server && bundle exec rails db:reset
```

Common seed failures and their causes:

- **NameError on a namespaced model** → check `class_name:` uses `::` separator (e.g. `Ai::AgentTeam`, not `AiAgentTeam`).
- **Validation failure on `Ai::Agent.agent_type`** → the column has a fixed allow-list (`assistant`, `code_assistant`, `data_analyst`, `content_generator`, `image_generator`, `monitor`, `mcp_client`). Pick the closest match and use `metadata.kind` for semantic discriminators.
- **Foreign key not found** → check namespaced FK prefixes (`Ai::` → `ai_`, `Devops::` → `devops_`).

## Frontend type errors

Run the type checker often:

```bash
cd frontend && npx tsc --noEmit
```

If TypeScript complains about a hook return type that "should" be inferred:

- Make sure you have no `any` in the chain — we forbid `any` in new code.
- Check the upstream type definition; many helpers use generic constraints that need explicit type parameters when the inferred shape is too loose.

## Worker behavior

- The server is a Rails **API** — it does NOT run Sidekiq.
- The worker is a standalone Sidekiq process and talks to the server via HTTP.
- Job classes live in `worker/app/jobs/`, NEVER `server/app/jobs/`.
- Adding Sidekiq gems to `server/Gemfile` is wrong.

If a job is not running, the cause is almost always one of:

1. The wrong queue priority in `worker/config/sidekiq.yml`.
2. The job was enqueued against the wrong Redis DB.
3. The worker is not running (`sudo systemctl status powernode-worker@default`).

## Submodule confusion

`git status` in the parent repo does NOT show changes inside an extension submodule. Always check both:

```bash
git status                                 # parent repo
git -C extensions/system status            # inside the submodule
```

If you intend to commit submodule changes:

1. `cd` into the submodule.
2. Verify with `git rev-parse --show-toplevel`.
3. Commit inside the submodule first.
4. Return to the parent and `git add extensions/<name>` to update the SHA pointer.

Never `git add extensions/<name>/some-file.rb` from the parent — that only stages the pointer change, not the file.

## Where to ask

- Conventions and patterns → [../contributing/conventions.md](../contributing/conventions.md)
- Architecture → [../concepts/architecture.md](../concepts/architecture.md)
- Agents and autonomy → [../concepts/agents-and-autonomy.md](../concepts/agents-and-autonomy.md)
- File a bug → [github-workflow.md](../contributing/github-workflow.md)

---

## Materials previously at

- Sections of the root CLAUDE.md (Service Management, Auth, Frontend Patterns, Theme System)

_Last verified: 2026-06-03_
