# GitHub Workflow

> Branch strategy, pull requests, and release tagging for Powernode contributors.

> Status: active

Powernode uses a `develop` → `feature/*` → `release/*` → `master` workflow modeled on Git-Flow. This page documents the conventions external contributors need to know, the fork-and-PR loop, and the repository protections we expect on the public GitHub mirror.

## Table of Contents

- [Branch strategy](#branch-strategy)
- [Tag naming](#tag-naming)
- [Fork and PR workflow](#fork-and-pr-workflow)
- [Pull request template](#pull-request-template)
- [Issue templates](#issue-templates)
- [Branch protection rules](#branch-protection-rules)
- [Repository settings](#repository-settings)
- [GitHub Actions](#github-actions)
- [Commit message convention](#commit-message-convention)
- [Troubleshooting](#troubleshooting)

## Branch strategy

| Branch | Role |
|--------|------|
| `develop` | Default branch. All feature work targets this. CI runs the full suite. |
| `feature/<short-description>` | Individual feature or fix branches. Cut from `develop`, merged back via PR. |
| `release/<x.y.z>` | Hardening branches cut from `develop` when preparing a release. Bug fixes during the freeze land here. |
| `master` | Release-only. Tagged once a release branch is verified. Force-pushes are forbidden. |

The platform parent and the `extensions/system` submodule are dual-remoted (private Gitea origin + public GitHub mirror). Releases push to both.

## Tag naming

**No `v` prefix.** Tags are bare semver:

```
0.2.0          # GOOD
0.2.0-rc.1     # GOOD
v0.2.0         # WRONG — do not push
```

Release branches follow the same rule: `release/0.2.0`, never `release/v0.2.0`. See [release-process.md](./release-process.md) for the full release cadence.

## Fork and PR workflow

External contributors work via fork + PR:

1. Fork `nodealchemy/powernode-platform` on GitHub.
2. Clone your fork locally and add the upstream remote:
   ```bash
   git clone https://github.com/<your-username>/powernode-platform.git
   cd powernode-platform
   git remote add upstream https://github.com/nodealchemy/powernode-platform.git
   git fetch upstream
   ```
3. Cut a feature branch from upstream `develop`:
   ```bash
   git checkout -b feature/my-change upstream/develop
   ```
4. Make your changes, run `./scripts/validate.sh`, and commit.
5. Push to your fork and open a PR against `nodealchemy/powernode-platform:develop`.

Keep PRs focused. Large changes should be staged into logical commits by concern (models, services, controllers, frontend, tests, config) — never one monolithic commit.

## Pull request template

The PR template at `.github/PULL_REQUEST_TEMPLATE.md` is loaded automatically when you open a PR. The current template covers:

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Tests pass locally
- [ ] New tests added for new functionality
- [ ] Manual testing completed

## Checklist
- [ ] Code follows project conventions (see docs/contributing/conventions.md)
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No breaking changes without version bump
```

## Issue templates

Issue templates live under `.github/ISSUE_TEMPLATE/`. The common ones are:

- **Bug report** — what you saw, what you expected, repro steps, environment.
- **Feature request** — problem statement, proposed solution, alternatives.
- **Security report** — DO NOT use; email security@nodealchemy.com per [SECURITY.md](../../SECURITY.md).

If you cannot map your report to a template, file a blank issue and one of the maintainers will retag.

## Branch protection rules

Maintainers configure these on the public mirror:

### `master`

- Require a pull request before merging
- Require approvals (1+)
- Dismiss stale PR approvals when new commits are pushed
- Require status checks to pass (`validate.sh` equivalent)
- Require branches to be up to date before merging
- Require conversation resolution
- Restrict pushes that create files larger than 100 MB
- Do not allow bypassing

### `develop`

- Require a pull request before merging
- Require status checks to pass
- Require branches to be up to date before merging
- Allow force pushes is **disabled** in normal operation (was enabled briefly during Git-Flow bootstrap)

## Repository settings

Under **Settings > General**, the public mirror enables:

- Wikis (for community-authored docs)
- Issues
- Discussions
- Squash merge + rebase merge (merge commits also allowed for release branches)
- "Automatically delete head branches" on merge

## GitHub Actions

The repo ships workflows under `.github/workflows/`. The most important one for contributors is the validation workflow that runs on every PR: it executes the same `./scripts/validate.sh` you can run locally.

Maintainer secrets (`NPM_TOKEN`, `DEPLOY_KEY`, etc.) are managed under **Settings > Secrets and variables > Actions**. Contributors do not need them.

## Commit message convention

Conventional Commits, scoped where useful:

```
type(scope): description

feat(auth): add OAuth2 integration
fix(billing): resolve subscription renewal issue
docs(api): update endpoint documentation
chore(submodule): bump extensions/system
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `perf`, `ci`, `build`.

Body wraps at 72 characters. Mention the issue or PR number in a trailer (`Refs #123`) when applicable.

## Troubleshooting

### Authentication issues

Use a personal access token (PAT) with `repo` scope, or configure SSH keys. We recommend SSH for daily use.

### Large file issues

Use Git LFS for files larger than 100 MB. Better yet, do not commit large binary artifacts at all — host them externally and link.

### My PR is failing CI for "subscription platform" identity strings

Run `rg "subscription platform" docs/ README.md` against your branch. Wave 0 of the doc consolidation purged this wording; new references should not be reintroduced.

---

## Materials previously at

- `docs/GITHUB_SETUP.md`

_Last verified: 2026-05-17_
