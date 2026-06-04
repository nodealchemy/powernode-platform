# Release Process

> Branching, versioning, and tagging for Powernode releases.

> Status: active

Powernode releases follow a Git-Flow-derived workflow: features land on `develop`, a release branch is cut for hardening, and the branch is merged into `master` and tagged once verified. This page captures the rules the release manager and reviewers need to follow.

## Table of Contents

- [Branch model](#branch-model)
- [Semantic versioning](#semantic-versioning)
- [Tag naming](#tag-naming)
- [Step-by-step: cutting a release](#step-by-step-cutting-a-release)
- [Submodule coordination](#submodule-coordination)
- [Dual-remote push](#dual-remote-push)
- [Hotfixes](#hotfixes)
- [Changelog](#changelog)
- [Common mistakes](#common-mistakes)

## Branch model

| Branch | Role | Who writes here |
|--------|------|------------------|
| `develop` | Default branch. Active development. CI runs the full suite | Everyone, via PR |
| `feature/<short-description>` | Single-feature work | Author, cut from `develop` |
| `release/<x.y.z>` | Hardening before a release. Bug fixes during freeze | Release manager + reviewers |
| `master` | Release-only. Tagged after merge | Release manager (PR from `release/<x.y.z>`) |
| `hotfix/<x.y.z>` | Urgent fix against a tagged release | Release manager, branched from the tagged commit on `master` |

Promotion path: `feature/*` → `develop` → `release/x.y.z` → `master` (tag) + back to `develop`.

## Semantic versioning

We use [semver](https://semver.org/) — `MAJOR.MINOR.PATCH`:

- **MAJOR** — incompatible API or schema changes that require operator action.
- **MINOR** — backward-compatible new features.
- **PATCH** — backward-compatible bug fixes.

Pre-release suffixes are allowed for release candidates: `0.3.0-rc.1`, `0.3.0-rc.2`, then `0.3.0`.

## Tag naming

**No `v` prefix.** Tags are bare semver:

```
0.2.0         # GOOD
0.2.0-rc.1    # GOOD
v0.2.0        # WRONG — do not create
release-0.2.0 # WRONG — do not create
```

Release branches mirror the tag: `release/0.2.0`, not `release/v0.2.0`.

This is non-negotiable. Tooling that scrapes tags assumes the bare-semver format, and `v`-prefixed tags break the changelog generator and Gitea release-publishing automation.

## Step-by-step: cutting a release

```bash
# 1. From an up-to-date develop, cut the release branch
git checkout develop
git pull origin develop
git checkout -b release/0.3.0

# 2. Bump version constants (Gemfile.lock, package.json, etc.)
# 3. Update CHANGELOG.md with the new section
# 4. Open a PR from release/0.3.0 against develop for review
#    (or push the branch directly and announce in your release channel)

# 5. Run the full validation suite locally
./scripts/validate.sh

# 6. During the freeze, fix bugs DIRECTLY on the release branch
git commit -m "fix(scope): describe the fix"
git push origin release/0.3.0

# 7. When the release is verified, merge to master and tag
git checkout master
git merge --no-ff release/0.3.0
git tag 0.3.0
git push origin master --tags

# 8. Merge release branch back to develop so the fixes don't get lost
git checkout develop
git merge --no-ff release/0.3.0
git push origin develop

# 9. Delete the release branch
git branch -d release/0.3.0
git push origin --delete release/0.3.0
```

## Submodule coordination

The platform parent contains submodules. A release that includes submodule changes follows this order:

1. Inside the affected submodule, run that submodule's own release flow and tag.
2. Push the submodule release tag to its remotes.
3. Update the parent's submodule pointer (`git add extensions/<name>`) on the parent's `release/x.y.z` branch.
4. Continue the parent release as usual.

If a submodule does not have changes, it does not need a release — leave the pointer alone.

The system extension is the most likely to be co-released because its work cadence is closely coupled with the parent platform. Marketing, supply-chain, business, and trading typically release independently.

## Dual-remote push

The platform parent and the system extension are **dual-remoted**: `origin` is the public GitHub mirror, and `ipnode` is the private Gitea upstream. Releases push to both.

```bash
# Parent
git push origin master --tags
git push ipnode master --tags

# System extension (from inside extensions/system/)
git push origin master --tags
git push ipnode master --tags
```

`git push --all` is dangerous on these repos because it can push unintended branches; always be explicit.

The marketing and supply-chain extensions are also dual-remoted. The business and trading extensions are private only and push to `ipnode` exclusively.

## Hotfixes

When a tagged release needs an urgent fix:

```bash
# 1. Branch from the tag
git checkout 0.3.0
git checkout -b hotfix/0.3.1

# 2. Apply the fix, run the suite
./scripts/validate.sh

# 3. Bump patch version + CHANGELOG entry
# 4. Merge to master and tag
git checkout master
git merge --no-ff hotfix/0.3.1
git tag 0.3.1
git push origin master --tags
git push ipnode master --tags

# 5. Merge back to develop
git checkout develop
git merge --no-ff hotfix/0.3.1
git push origin develop
```

## Changelog

The canonical changelog is the root `CHANGELOG.md`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) with semver headings.

Each release section has:

```markdown
## [0.3.0] - YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Deprecated
- ...

### Removed
- ...

### Fixed
- ...

### Security
- ...
```

Pre-release entries (`0.3.0-rc.1`) get their own section that gets squashed into the final release section once it tags.

## Common mistakes

| Mistake | Consequence |
|---------|-------------|
| Prefixing tags with `v` | Breaks the changelog generator and release automation |
| Merging `release/*` to `master` without merging back to `develop` | Fixes are lost on the next minor cut |
| Pushing to only one remote of a dual-remoted repo | One mirror lags — push to both `origin` (GitHub) and `ipnode` (Gitea) |
| Forgetting to bump the parent's submodule pointer after a coupled submodule release | Parent release ships against the previous submodule SHA |
| Releasing on a Friday afternoon | Predictable consequences |

---

## Materials previously at

- Git Rules section of the root CLAUDE.md
- Release Process section of `docs/GITHUB_SETUP.md`

_Last verified: 2026-06-04_
