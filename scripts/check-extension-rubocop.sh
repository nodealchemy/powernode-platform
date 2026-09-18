#!/bin/bash
# scripts/check-extension-rubocop.sh
#
# Mirrors the extensions/system `rubocop` CI job (extensions/system's own
# .gitea/workflows/ci.yaml) so an offense is caught locally, before push,
# instead of only by CI afterward. IMP-b531fc42ed51 cleared 22 offences that
# had kept that job red; nothing then kept it clear (IMP-d96158bf07df) — this
# script plus its pattern-validation.sh wiring is that gate.
#
# WHAT CI ACTUALLY DOES (so this can match it, not just resemble it): checks
# out core at the branch's resolved core-ref, mounts the extension under that
# core checkout's extensions/system, then runs `bundle exec rubocop` from
# THAT core's server/ against the extension's server/{app,lib,spec} and
# worker/app. Two things fall out of running it that way instead of inside
# the extension's own tree:
#   - VERSION: `bundle exec` resolves rubocop from core server/Gemfile.lock,
#     not from any Gemfile the extension might carry on its own.
#   - CONFIG: RuboCop resolves each target file's config by searching upward
#     from the FILE's own directory, independent of CWD — so it still finds
#     extensions/system/server/.rubocop.yml (and worker/.rubocop.yml) even
#     though the invocation's CWD is core/server, one level up and sideways.
#     Verified empirically here, including through extensions/system being a
#     symlink to a separate worktree (the actual on-disk shape on this
#     machine) — RuboCop follows the symlink like any other path.
#
# This script runs the identical command from the CURRENT checkout's server/,
# so it inherits both properties for free: same Gemfile.lock (same rubocop
# version CI would resolve for THIS commit) and the same per-directory config
# resolution CI relies on.
#
# ONE PLACE THIS CAN STILL DIVERGE FROM CI, DELIBERATELY LEFT OPEN RATHER
# THAN PAPERED OVER: CI resolves core at a RESOLVED REF for the PR's branch
# name (scripts/ci-resolve-core-ref.sh), which can be a different commit than
# whatever you happen to have checked out locally right now (e.g. your core
# tree is ahead of, or on a different branch than, what CI will pair the
# extension with). When that happens, the rubocop VERSION can differ, because
# it comes from THIS checkout's server/Gemfile.lock, not CI's resolved one.
# There is no local fetch-a-second-core-checkout step here to close that
# gap — flagged, not silently assumed away. In the common case (this script
# run from the same core branch/commit the extension's CI will pair with),
# there is no divergence.
#
# Exit codes:
#   0  nothing to check (extensions/system absent — public clone with the
#      submodule uninitialised) OR present and clean.
#   1  extension present and rubocop reported >=1 offense.
#   2  extension present but rubocop could not be resolved from core's
#      server/ (e.g. `bundle install` never ran) — an environment gap, not a
#      code offense; the caller should score this distinctly from a real FAIL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXT_SERVER="$PROJECT_ROOT/extensions/system/server"
EXT_WORKER="$PROJECT_ROOT/extensions/system/worker"

# Absent submodule / extension not on disk: nothing to check, not a failure —
# same treatment as every other extension-presence check in this repo (e.g.
# validate.sh's tsc-check-optouts loop, which only scores extensions that
# exist).
if [[ ! -d "$EXT_SERVER" ]]; then
  exit 0
fi

TARGETS=()
[[ -d "$EXT_SERVER/app" ]] && TARGETS+=("$EXT_SERVER/app")
[[ -d "$EXT_SERVER/lib" ]] && TARGETS+=("$EXT_SERVER/lib")
[[ -d "$EXT_SERVER/spec" ]] && TARGETS+=("$EXT_SERVER/spec")
[[ -d "$EXT_WORKER/app" ]] && TARGETS+=("$EXT_WORKER/app")

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  exit 0
fi

cd "$PROJECT_ROOT/server"

if ! bundle exec rubocop --version >/dev/null 2>&1; then
  echo "rubocop not resolvable from server/ (run: cd server && bundle install)" >&2
  exit 2
fi

# Mirrors CI's invocation exactly (.gitea/workflows/ci.yaml, `rubocop` job,
# step "Run RuboCop on extension Ruby"): same four target dirs, same CWD
# (server/), same `bundle exec rubocop` with no extra flags.
bundle exec rubocop "${TARGETS[@]}"
