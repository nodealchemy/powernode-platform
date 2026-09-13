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
| `check-mcp-actions.sh` | Every `platform.<action>(` call site exists in `server/app/services/ai/tools/platform_api_tool_registry.rb` or is catalogued in `ASPIRATIONAL_MCP.md` | no | 0=clean (or registry unreachable), 1=uncatalogued unknown, 2=invocation error |
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
[`ASPIRATIONAL_MCP.md`](./ASPIRATIONAL_MCP.md) are expected unknowns. That
catalog is **machine-read** (IMP-01a05ec2): the script subtracts its rows from
the unknowns, so an unknown fails ONLY when it is not catalogued, and the check
has a green baseline. It also names a catalogued action nothing references any
more, so the allowlist does not quietly outlive its docs.

Until that change the script merely told the reader to cross-check by hand, so
it exited 1 on every run — two of the reported unknowns (`cost_analysis`,
`recent_events`) are real verbs the running server exposes that a static grep
of the registry cannot see. The step is advisory, so this never failed a
workflow; it did something quieter. A step that is red every time is one nobody
reads, and a genuinely new unknown moved the count from 2 to 3 inside an
already-failing step. Its baseline is asserted by
`server/spec/integration/docs_verify_mcp_actions_spec.rb`, which also drives
the real script in a sandbox to prove an uncatalogued unknown still reds it —
"exits 0 today" alone would pass against a script that can never fail.

It stays **advisory** in CI deliberately: a static grep against a Ruby registry
has known blind spots, and blocking doc PRs on it would trade a quiet
false-negative for a loud false-positive.

**`check-links.sh`** is the ONE hard gate in `.gitea/workflows/docs.yml` —
every sibling check sets `continue-on-error: true`. It therefore has to be
green when nothing is wrong, and it was not (IMP-01a08a0f): four correct
references to `docs/reference/auto/todo.md` and `.../learnings.md` failed it on
every run. Those files are DB-backed artifacts the repo deliberately does not
track (`.gitignore`, commit `0bbe16e63` — "split auto-gen tracking policy —
mcp-tools tracked, DB-backed not"), and the workflow runs this gate straight
after checkout with no generation step, so they can never exist in CI. The only
two outcomes were permanent failure or the `[docs-skip-verify]` marker, which
disables *all* doc verification.

A missing target that `git check-ignore` matches is now reported as
`GENERATED` and does not fail the run. The exemption is DERIVED from the repo's
own tracking policy rather than a second hand-kept list, so another generated
doc needs no edit here; it is reported rather than hidden, so a doc that stops
being generated is visible before it becomes a failure; and it is fail-closed —
without git, or outside a work tree, the target counts as broken exactly as
before. Guarded by `server/spec/integration/docs_verify_links_spec.rb`, which
asserts the real-tree baseline AND drives the script over a throwaway repo to
prove a genuinely dead link still reds it, including when it sits beside an
exempt one.

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

_Last verified: 2026-06-04_
- `../contributing/doc-conventions.md` — authoring rules these scripts
  validate
