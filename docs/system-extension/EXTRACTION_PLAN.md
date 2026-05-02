# System Extension Repository Extraction Plan

**Status:** Both repos created. Meta files prepared. Extraction (git filter-repo + push + submodule conversion) pending operator confirmation.

This document captures the precise steps to migrate `extensions/system/` from
in-tree code to a submodule pointing at the new `powernode-system` repo, mirroring
the existing `extensions/trading/` pattern.

## Repos

| Side | URL | Visibility | State |
|---|---|---|---|
| Gitea | `git@git.ipnode.org:powernode/powernode-system.git` | private | ✅ created (3-file scaffold commit — overwritten by `--force` on first push) |
| GitHub | `git@github.com:rett/powernode-system.git` | **public** | ✅ created (empty — clean push works) |

Topics on GitHub: `powernode, infrastructure, kubernetes-alternative, node-management, composefs, ipxe, golang, rails, typescript`.

## Meta files prepared in extensions/system/ (will be in the first push)

- `README.md` — public-facing overview
- `LICENSE` — MIT
- `CONTRIBUTING.md` — development + submodule workflow
- `.gitignore` — Ruby/Node/Go/initramfs-build artifacts + secret patterns
- `.gitea/workflows/ci.yaml` — full rspec via parent platform mount + frontend tsc + go agent + ruby syntax
- `.github/workflows/ci.yaml` — public CI (no parent platform required): ruby syntax, rubocop advisory, go vet+test+cross-compile, frontend lint, shellcheck, yamllint
- `docs/ARCHITECTURE.md` — comprehensive design reference (replaces Gitea scaffold's placeholder)
- `docs/TASKS.md` — active milestone tracker (replaces Gitea scaffold's placeholder)

## Step 1 — GitHub repo creation (DONE)

Created via `gh repo create rett/powernode-system --public --description ...`
on 2026-05-02. Empty, ready for the extraction's first push.

```bash
# Reference command (already executed):
gh repo create rett/powernode-system \
  --public \
  --description "Powernode platform's system extension — node lifecycle, module CRUD, fleet autonomy, observability, on-node Go agent, initramfs, multi-arch boot artifact builder, CLI. Mounted into powernode-platform as a submodule at extensions/system/." \
  --homepage "https://github.com/rett/powernode-platform"

gh repo edit rett/powernode-system \
  --add-topic powernode --add-topic infrastructure \
  --add-topic kubernetes-alternative --add-topic node-management \
  --add-topic composefs --add-topic ipxe --add-topic golang \
  --add-topic rails --add-topic typescript
```

## Step 2 — Extract the history with git filter-repo

We want `extensions/system/` to become the root of the new repo, preserving its
file history.

```bash
# Work outside the platform tree to avoid contaminating the parent repo
cd /tmp
git clone --no-local /home/rett/Drive/Projects/powernode-platform powernode-system-extract
cd powernode-system-extract

# Use git-filter-repo (much faster + safer than filter-branch)
# Install once: pip install --user git-filter-repo
git filter-repo \
  --subdirectory-filter extensions/system \
  --force

# Result: a repo whose root is the former extensions/system/ contents,
# with history rewritten so file paths drop the "extensions/system/" prefix.

# Verify
ls   # should show server/ frontend/ worker/ agent/ initramfs/ ...
git log --oneline | head -5   # should still have meaningful commits

# Add both remotes
git remote add origin git@git.ipnode.org:powernode/powernode-system.git
git remote add github git@github.com:rett/powernode-system.git

# Force-push to Gitea — the MCP scaffold-on-create added .gitignore +
# docs/ARCHITECTURE.md + docs/TASKS.md as a single bootstrap commit; the
# filter-repo extraction has the FULL history of extensions/system/ which
# is what we want, so the scaffold gets overwritten cleanly.
git push -u origin master --force

# GitHub starts empty (we tell `gh repo create` to skip README/etc), so a
# normal push works.
git push -u github master
```

**Note:** the scaffold's `docs/ARCHITECTURE.md` + `docs/TASKS.md` are
generic placeholders. The extraction includes our real `README.md`,
`CONTRIBUTING.md`, `LICENSE`, `.gitignore`, `.gitea/workflows/ci.yaml`, and
`.github/workflows/ci.yaml` — those win on the force-push.

## Step 3 — Replace in-tree extensions/system with a submodule

```bash
cd /home/rett/Drive/Projects/powernode-platform

# Make sure the parent has no uncommitted changes touching extensions/system
git status -- extensions/system

# Remove the in-tree directory
git rm -r extensions/system
rm -rf extensions/system   # in case anything's still there
git commit -m "Extract system extension to submodule"

# Add as submodule (origin = Gitea, like trading)
git submodule add git@git.ipnode.org:powernode/powernode-system.git extensions/system

# The submodule will check out master by default. Pin to the SHA we just pushed.
cd extensions/system
git remote add github git@github.com:rett/powernode-system.git
git fetch github
cd ../..

# Commit the submodule pointer
git add .gitmodules extensions/system
git commit -m "Mount powernode-system as submodule"
```

## Step 4 — Verify

```bash
# In the parent repo:
git submodule status   # should show extensions/system at the expected SHA

# Inside the submodule:
git -C extensions/system remote -v   # should list both origin (Gitea) and github
git -C extensions/system status      # should be clean

# Test that the platform still builds:
cd server && bundle exec rspec ../extensions/system/server/spec/  # should be 1262 / 0
cd ../frontend && npx tsc --noEmit  # should be clean
```

## Step 5 — Update CI / workflows

The existing `extensions/system/.gitea/workflows/build.yaml` for the initramfs
will now run from the powernode-system repo's perspective, not the platform's.
Verify the runner has access (`gitea_runner` service on the swarm — see
extensions/trading's runner config for the canonical setup).

The platform's CI may need a `submodules: recursive` flag added to its
checkout step so the submodule contents are present during platform tests
(this is the trading-mirror pattern).

## Step 6 — Update documentation

Files that reference `extensions/system/` need a small framing pass:

- `CLAUDE.md` (root) — under "Submodule Safety", `extensions/system` is added to the existing list of submodules
- `extensions/system/CLAUDE.md` — note that the extension lives in its own repo
- `docs/system-extension/` — anything operator-facing referencing the path

## Decision points still to make

1. **Branching strategy** — Trading uses `develop` as its working branch with
   tagged releases on `master`. Same for system, or simpler `master`-only?
2. **CI cross-ref** — Should the platform's CI block on the submodule's CI status?
3. **Public docs** — The GitHub repo will be public. Anything in
   `extensions/system/docs/` that contains internal-only context (Vault PKI bootstrap,
   Trading's Polymarket adapter cross-refs, etc.) should be moved or genericized
   before the first push.

---

*Generated 2026-05-02 by the Golden Eclipse session that created the Gitea repo.*
