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
- `git status` — see all changed/untracked files
- `git diff --stat` — see change summary for tracked files
- `git diff --cached --stat` — see already-staged changes
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

## Step 3: Create Commits

For each non-empty group:
1. `git add <specific-files>` — NEVER use `git add -A` or `git add .`
2. Commit with conventional format: `type(scope): description`
   - Types: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`
   - Scope: `backend`, `frontend`, `worker`, `config`, `db`
   - Description: concise, lowercase, no period

**Rules:**
- **NO** Claude attribution (no Co-Authored-By, no "Generated with")
- **NO** `git add -A` or `git add .`
- If a hint/scope argument was provided, use it to guide the commit messages

## Step 4: Summary

Run `git log --oneline -10` and show the commits created.
