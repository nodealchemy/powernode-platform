# Platform Documentation Verification Harness

Five read-only bash scripts that audit the `docs/` corpus and root meta
files for common drift classes: broken markdown links, missing code path
references, unknown MCP action names, auto-gen marker enforcement, and
advisory count-drift.

**All scripts are read-only.** They never modify the file tree.

The single hard gate before `git push` is `check-links.sh`; the other
four are tools reviewers run on demand.

## Scripts

| Script | What it checks | Hard gate? | Exit codes |
|--------|----------------|------------|------------|
| `check-links.sh` | Every `[text](path)` in every `.md` resolves on disk | YES (pre-push) | 0=clean, 1=broken, 2=invocation error |
| `check-code-refs.sh` | Every backtick-quoted path-shaped string (`server/app/...`, `frontend/src/...`, etc.) exists | no | 0=clean, 1=missing, 2=invocation error |
| `check-mcp-actions.sh` | Every `platform.<action>(` call site exists in `server/app/services/ai/tools/platform_api_tool_registry.rb` | no | 0=clean (or registry unreachable), 1=unknown, 2=invocation error |
| `check-counts.sh` | Advisory regex scan for drift-prone hardcoded counts | no (non-failing) | always 0 |
| `check-auto-gen-headers.sh` | Every `docs/reference/auto/*.md` has `<!-- AUTO-GENERATED` in first 5 lines | no | 0=clean, 1=missing |

## Running locally

From the platform root:

```bash
bash docs/.verify/check-links.sh
bash docs/.verify/check-code-refs.sh
bash docs/.verify/check-mcp-actions.sh
bash docs/.verify/check-counts.sh
bash docs/.verify/check-auto-gen-headers.sh
```

Run any one in isolation, or wire them together:

```bash
set -e
for s in check-links check-code-refs check-mcp-actions check-counts check-auto-gen-headers; do
  echo "--- $s ---"
  bash "docs/.verify/${s}.sh"
done
echo "All checks passed."
```

## When to run

- **Before `git push`** — `check-links.sh` runs automatically via the
  pre-push hook installed by `scripts/install-git-hooks.sh`. Use
  `git push --no-verify` to bypass for emergencies.
- **During doc PR review** — reviewers run the others on demand.
- **In CI (future)** — wire any subset into `.gitea/workflows/docs.yml`.

## Output format

Each script prints findings as `<file>:<line>: <CLASSIFICATION> -> <detail>`
followed by a summary footer.

Examples:

```
docs/concepts/architecture.md:120: BROKEN -> ../guides/missing.md

docs/operations/docker-swarm.md:45: MISSING -> server/app/services/system/old_service.rb

UNKNOWN actions (referenced via platform.X() but not in registry):
  system_legacy_action
    referenced in: docs/runbooks/legacy.md
```

## Scope conventions

| Scope | Included | Excluded |
|-------|----------|----------|
| Files audited | `docs/**/*.md` + root `README.md` + `CLAUDE.md` + `CONTRIBUTING.md` + `CODE_OF_CONDUCT.md` + `SECURITY.md` + `CHANGELOG.md` | `docs/reference/auto/**` (auto-gen; refreshed nightly), `docs/.verify/**` (self), `docs/_consolidation-map.json`, `docs/_redirects.json`, anything inside `extensions/*` (submodule territory) |
| Path checks | Platform paths (`server/`, `frontend/`, `worker/`, `scripts/`, `config/`, `docs/`, `initramfs/`) and submodule directories (`extensions/<slug>/` existence only) | URLs, paths with spaces, glob patterns, paths inside submodules past the slug |
| MCP actions | Call-site syntax `platform.<action>(` | Prose mentions, table entries, blockquote text, comment lines |

## Tradeoffs + limitations

**`check-links.sh`** uses regex extraction of `[text](path)` pairs.
It handles:

- Relative paths (resolved against the file's directory)
- Anchor fragments (stripped before resolution)
- URL schemes (http/https/mailto/ftp/tel skipped)

It does NOT handle:

- Reference-style links (`[text][ref]` then `[ref]: path`)
- Auto-links (`<http://...>`)

**`check-code-refs.sh`** uses a conservative whitelist of platform-prefix
patterns. Strings without a leading directory match (e.g. ad-hoc
filenames like `Gemfile`) are skipped. Paths into `extensions/<slug>/`
are checked for the submodule directory existence only — file-level
checks are the submodule's harness's job.

**`check-mcp-actions.sh`** depends on
`server/app/services/ai/tools/platform_api_tool_registry.rb`. The script
extracts identifier-shaped quoted strings from the registry, which
includes both action names AND other quoted strings (parameter names,
descriptions). This errs on the side of accepting more than necessary,
keeping false-positive unknowns low.

Aspirational MCP actions documented in
[`ASPIRATIONAL_MCP.md`](./ASPIRATIONAL_MCP.md) are expected unknowns;
add new aspirational uses there.

**`check-counts.sh`** is intentionally advisory. Counts in
`docs/reference/auto/` are canonical (they auto-regenerate); inline
counts elsewhere should be either accurate or, ideally, replaced with a
link to the auto-gen catalog.

## Pre-push hook

The platform's `scripts/install-git-hooks.sh` installs a pre-push hook
that calls `bash docs/.verify/check-links.sh`. To install:

```bash
bash scripts/install-git-hooks.sh
```

To bypass (use sparingly — broken links degrade docs quickly):

```bash
git push --no-verify
```

## Related

- [`RENDER_PARITY.md`](./RENDER_PARITY.md) — Mermaid diagram render
  parity between Gitea and the GitHub mirror
- [`ASPIRATIONAL_MCP.md`](./ASPIRATIONAL_MCP.md) — known-aspirational
  MCP action catalog (expected unknowns)
- `../contributing/doc-conventions.md` — authoring rules these scripts
  validate
