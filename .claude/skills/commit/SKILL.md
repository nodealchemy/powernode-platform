---
name: commit
description: Create staged logical commits grouped by concern
disable-model-invocation: true
argument-hint: [optional scope or message hint]
---

# Staged Commit Workflow

Create logical, grouped commits from all current changes. Follow this process exactly:

## Step 1: Analyze Changes

Run these commands in parallel:
- `git status` — see all changed/untracked files in the parent repo
- `git diff --stat` — see change summary for tracked files
- `git diff --cached --stat` — see already-staged changes
- `git -C extensions/enterprise status --short` — see changes inside the enterprise submodule
- `git log --oneline -5` — see recent commit style

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

When changes span both repos, group enterprise changes separately from core.

## Step 3: Create Commits

### Enterprise submodule (commit FIRST if it has changes)

If `git -C extensions/enterprise status` shows changes:
1. Group enterprise changes by concern (backend vs frontend)
2. Stage with `git -C extensions/enterprise add <specific-files>`
3. Commit with `git -C extensions/enterprise commit -m "type(scope): description"`
4. After all enterprise commits, update the submodule pointer in the parent: `git add extensions/enterprise`

### Parent repo

For each non-empty group:
1. `git add <specific-files>` — NEVER use `git add -A` or `git add .`
2. Commit with conventional format: `type(scope): description`
   - Types: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`
   - Scope: `backend`, `frontend`, `worker`, `config`, `db`, `enterprise`
   - Description: concise, lowercase, no period

If the enterprise submodule pointer changed (from enterprise commits above), include it in the appropriate parent commit or as a separate `chore(enterprise): update submodule pointer` commit.

**Rules:**
- **NO** Claude attribution (no Co-Authored-By, no "Generated with")
- **NO** `git add -A` or `git add .`
- If a hint/scope argument was provided, use it to guide the commit messages

## Step 4: Summary

Run these in parallel:
- `git log --oneline -10` — show parent repo commits
- `git -C extensions/enterprise log --oneline -5` — show enterprise commits

Show all commits created in both repos.
