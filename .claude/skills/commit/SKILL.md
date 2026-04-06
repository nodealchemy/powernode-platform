---
name: commit
description: Create staged logical commits grouped by concern
disable-model-invocation: true
argument-hint: [optional scope or message hint]
---

# Staged Commit Workflow

Create logical, grouped commits from all current changes. Follow this process exactly:

## Step 0: Verify CWD & Submodule State

Before analyzing changes, verify the working state:

1. `pwd` — confirm you are in the project root
2. `git rev-parse --show-toplevel` — confirm parent repo identity
3. `git submodule status` — check all submodule pointers

If any submodule shows a `+` prefix (modified pointer), note it — this must be committed after the submodule's internal commits.

## Step 1: Analyze Changes

Run these commands in parallel:
- `git status` — see all changed/untracked files in the parent repo
- `git diff --stat` — see change summary for tracked files
- `git diff --cached --stat` — see already-staged changes
- `git -C extensions/business status --short` — changes in business submodule
- `git -C extensions/trading status --short` — changes in trading submodule
- `git -C extensions/supply-chain status --short` — changes in supply-chain submodule
- `git log --oneline -5` — see recent commit style

## Step 1.5: Pre-commit Safety Scan

Before creating any commits:

1. **Extension file leak**: Check `git status` output for files under `extensions/business/`, `extensions/trading/`, or `extensions/supply-chain/` staged in the parent repo. These MUST be committed inside their submodule, not the parent.
   - If found: Unstage them (`git reset HEAD extensions/...`) and commit inside the submodule instead
2. **Ruby syntax gate**: If there are staged `.rb` files, verify: `git diff --cached --name-only -- '*.rb' | head -5 | xargs -I{} ruby -c {}`
3. **TypeScript gate**: If there are staged `.ts`/`.tsx` files, verify: `cd frontend && npx tsc --noEmit 2>&1 | tail -5`

## Step 2: Group Files by Concern

Organize changed files into groups (skip empty groups):
1. **Migrations** — `db/migrate/`
2. **Models** — `app/models/`
3. **Services** — `app/services/`
4. **Controllers & Routes** — `app/controllers/`, `config/routes.rb`
5. **Frontend** — `frontend/src/`
6. **Tests** — `spec/`, `e2e/`, `__tests__/`
7. **Seeds & Config** — `db/seeds/`, `config/`, `.claude/`, `scripts/`
8. **Documentation** — `docs/`, `*.md` (only if explicitly changed)

When changes span multiple repos, group each submodule's changes separately from core.

## Step 3: Create Commits

### Submodules (commit FIRST if they have changes)

For each submodule with changes (business, trading, supply-chain):
1. `git -C extensions/<name> rev-parse --show-toplevel` — verify identity
2. Group submodule changes by concern (backend vs frontend vs worker)
3. Stage with `git -C extensions/<name> add <specific-files>`
4. Commit with `git -C extensions/<name> commit -m "type(scope): description"`
5. After all submodule commits, update pointers in parent: `git add extensions/<name>`

### Parent repo

For each non-empty group:
1. `git add <specific-files>` — NEVER use `git add -A` or `git add .`
2. Commit with conventional format: `type(scope): description`
   - Types: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`
   - Scope: `backend`, `frontend`, `worker`, `config`, `db`, `business`, `trading`
   - Description: concise, lowercase, no period

If submodule pointers changed (from submodule commits above), include them in the appropriate parent commit or as a separate `chore(<name>): update submodule pointer` commit.

**Rules:**
- **NO** Claude attribution (no Co-Authored-By, no "Generated with")
- **NO** `git add -A` or `git add .`
- If a hint/scope argument was provided, use it to guide the commit messages

## Step 4: Summary

Run these in parallel:
- `git log --oneline -10` — show parent repo commits
- `git -C extensions/business log --oneline -5` — show business commits (if changes)
- `git -C extensions/trading log --oneline -5` — show trading commits (if changes)
- `git -C extensions/supply-chain log --oneline -5` — show supply-chain commits (if changes)

Show all commits created across all repos.
