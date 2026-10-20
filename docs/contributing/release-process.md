# Release Process

> Branching, versioning, and tagging for Powernode releases.

> Status: active

Powernode releases follow a Git-Flow-derived workflow: features land on `develop`, a release branch is cut for hardening, and the branch is merged into `master` and tagged once verified. This page captures the rules the release manager and reviewers need to follow.

## Table of Contents

- [Where versions come from](#where-versions-come-from)
- [Branch model](#branch-model)
- [Semantic versioning](#semantic-versioning)
- [Tag naming](#tag-naming)
- [Cutting a release](#cutting-a-release)
- [What release.sh does](#what-releasesh-does)
- [Per-runtime version sources](#per-runtime-version-sources)
- [Dual-remote push](#dual-remote-push)
- [Hotfixes](#hotfixes)
- [Changelog](#changelog)
- [History note: 0.3.0 appears twice](#history-note-030-appears-twice)
- [Common mistakes](#common-mistakes)

## Where versions come from

**Nothing in the tree hand-maintains a version.** There is no `VERSION` file, no `version.rb`,
no `extension.json` `version`. Every version is derived from, or stamped at release time by,
the release tag (`X.Y.Z`, no `v`). Running `scripts/release.sh X.Y.Z` **is** the release.

| Build | Version | Example |
|-------|---------|---------|
| Exact tag `X.Y.Z` | `X.Y.Z` | `0.3.0` |
| On `release/X.Y.Z` or `hotfix/X.Y.Z` | `X.Y.Z-rc.N+sha` | `0.3.0-rc.4+a1b2c3d` |
| Anything else (develop, features) | latest tag with minor+1, patch 0: `-dev.N+sha` | `0.3.0-dev.137+a1b2c3d` |
| No tags reachable | `0.0.0-dev.0+sha` (with a warning) | `0.0.0-dev.0+a1b2c3d` |

`N` is the number of commits since the latest tag; `sha` is the 7-character commit.

**Display contract** (unchanged): a *release* build shows `X.Y.Z`; every other build shows the
7-char sha. A build is a release only when it is an **exact tag AND the tip of `master`**.

The only files that carry a version string are written by `release.sh` alone: each extension
gemspec (`spec.version`, Bundler needs a literal) and the root and `frontend/` `package.json`.

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

We use [semver](https://semver.org/) -- `MAJOR.MINOR.PATCH`:

- **MAJOR** -- incompatible API or schema changes that require operator action.
- **MINOR** -- backward-compatible new features.
- **PATCH** -- backward-compatible bug fixes.

Release candidates are not tagged: the `release/X.Y.Z` branch builds report `X.Y.Z-rc.N+sha`.
Federation compares `major.minor.patch` only (an N-1 minor window) and always sends the plain
`X.Y.Z` core, never a prerelease string.

## Tag naming

**No `v` prefix.** Tags are bare semver:

```
0.2.0         # GOOD
v0.2.0        # WRONG — do not create
release-0.2.0 # WRONG — do not create
```

Release branches mirror the tag: `release/0.2.0`, not `release/v0.2.0`.

This is non-negotiable. Tooling that scrapes tags assumes the bare-semver format, and `v`-prefixed tags break the changelog generator and Gitea release-publishing automation.

## Cutting a release

```bash
# 1. Cut release/X.Y.Z from develop in the parent AND in every submodule
#    (all trees clean, all on release/X.Y.Z).
git checkout -b release/0.3.0 develop
git submodule foreach 'git checkout -b release/0.3.0 develop'

# 2. Update CHANGELOG.md, run the full gate, fix bugs on the release branch.
./scripts/validate.sh

# 3. Rehearse: validates everything and prints the plan, changes nothing.
./scripts/release.sh 0.3.0 --dry-run

# 4. Release.
./scripts/release.sh 0.3.0

# 5. Mirror to GitHub (release.sh pushes to origin only).
git push github master develop 0.3.0
```

Pushing the tag triggers `.gitea/workflows/release.yml`, which builds the docker images and
dispatches the module build with the tag; both compute the version from the tag.

## What release.sh does

1. **Asserts** a clean tree, branch `release/X.Y.Z` (or `hotfix/X.Y.Z`), and no `X.Y.Z` tag (local or on the remote) in the parent or any submodule.
2. **Stamps** every extension gemspec, runs `bundle lock` in `server/` (so `Gemfile.lock` follows), and `npm version X.Y.Z --no-git-tag-version` in the root and `frontend/` (this also corrects the lockfiles).
3. **Commits** inside each submodule, then the parent, one commit per concern.
4. **Merges** `release/X.Y.Z` into `master` with `--no-ff` (submodules first, so the parent records their merge commits), tags `X.Y.Z` on `master` and on each submodule's `master`, and pushes the tags.
5. **Back-merges** to `develop` (submodules, then the parent) and pushes.

`--dry-run` performs the assertions for real and only prints steps 2-5.

## Per-runtime version sources

| Runtime | Source (in order) |
|---------|-------------------|
| Server (`Powernode::Version`, `server/config/version.rb`) | `BUILD_INFO.json` -> `git describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*'` (dev only) -> `0.0.0-dev.0` |
| Worker (`worker/config/build_version.rb`) | the same chain; the worker cannot require server code |
| Frontend (`__BUILD_INFO__`) | `POWERNODE_BUILD_INFO_JSON` -> `vite.config.ts` computes it locally with the same describe logic -> `0.0.0-dev` |
| Docker images | `ARG POWERNODE_BUILD_INFO_JSON`, computed by `scripts/compute-build-info.sh` in the workflow, written to `BUILD_INFO.json` in the image |
| Module build (`stage15.sh`) | derived from the `ls-remote` refs of the shallow parent clone (exact tag, else max tag with minor+1; `N` by deepening to the tag), written to `BUILD_INFO.json` |
| Go agent | `-X main.Version=X.Y.Z` on a release build, otherwise date-sha; `make` uses `git describe --match '[0-9]*.[0-9]*.[0-9]*'` |
| Extensions | the registry reports the platform version; no per-extension version |

`BUILD_INFO.json` is git-ignored.

## Dual-remote push

The platform parent and the system extension are **dual-remoted**: `origin` is the private Gitea upstream (`<gitea-host>`; the concrete host is deployment knowledge), and `github` is the public GitHub mirror. Releases push to both.

```bash
# Parent
git push origin master --tags
git push github master --tags

# System extension (from inside extensions/system/)
git push origin master --tags
git push github master --tags
```

`git push --all` is dangerous on these repos because it can push unintended branches; always be explicit.

The marketing and supply-chain extensions are also dual-remoted. The business extension is private only and pushes to `origin` exclusively.

## Hotfixes

```bash
# 1. Branch from the tag (builds report X.Y.Z-rc.N+sha)
git checkout 0.3.0
git checkout -b hotfix/0.3.1
git submodule foreach 'git checkout -b hotfix/0.3.1'   # as needed

# 2. Apply the fix, run the suite
./scripts/validate.sh

# 3. Release it from the hotfix branch (release.sh accepts release/X.Y.Z or hotfix/X.Y.Z).
./scripts/release.sh 0.3.1
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

## History note: 0.3.0 appears twice

`master` already carries untagged `0.3.0` / `0.3.1` merges from before this scheme (the old
`VERSION` file said `0.3.1`). The first release under the scheme is `0.3.0`, cut by the
operator on a stable `master`, so "0.3.0" will appear twice in history: the old untagged merges
and the real tagged release. Only the tag is authoritative. The existing tags are `0.0.1`,
`0.0.2`, `0.1.0` and `0.2.0`; no baseline tag is created before then.

## Common mistakes

| Mistake | Consequence |
|---------|-------------|
| Prefixing tags with `v` | Breaks the changelog generator and release automation |
| Merging `release/*` to `master` without merging back to `develop` | Fixes are lost on the next minor cut |
| Pushing to only one remote of a dual-remoted repo | One mirror lags — push to both `origin` (Gitea) and `github` (GitHub) |
| Hand-editing a version anywhere | It is overwritten or contradicted by the tag; only `release.sh` writes versions |
| Running `release.sh` with a dirty tree or off `release/X.Y.Z` | It refuses; fix the tree or branch |
| Releasing on a Friday afternoon | Predictable consequences |

---

## Materials previously at

- Git Rules section of the root CLAUDE.md
- Release Process section of `docs/GITHUB_SETUP.md`

_Last verified: 2026-06-04_
