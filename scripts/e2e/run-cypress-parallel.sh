#!/usr/bin/env bash
# Provisions per-run E2E test logins ONCE and shares them via E2E_LOGINS with
# every parallel `cypress run` process, then launches the split.
#
# NOTE: cypress-split has no CLI of its own (only cypress-split-merge /
# cypress-split-preview bins) — it is a Node plugin (see
# frontend/cypress.config.ts, which wires `cypressSplit(on, config)` into
# setupNodeEvents) that reads SPLIT/SPLIT_INDEX from process.env
# (cypress-split/src/index.js: `parseSplitInputs(process.env, config.env)`)
# to decide which spec subset THIS `cypress run` process handles — see
# https://github.com/bahmutov/cypress-split#split-across-several-machines.
# Real N-way parallelism on one machine means invoking `cypress run` N times
# with the same SPLIT and SPLIT_INDEX=0..N-1, which is what this script does.
#
# Without sharing E2E_LOGINS, each of those N processes' setupNodeEvents
# would call provisionTestLogins() independently (see
# scripts/e2e/provision-test-logins.cjs), and since resetting a user's
# password invalidates any password a sibling process already cached, the
# processes would race and later resets would 401 earlier ones. Exporting
# E2E_LOGINS here short-circuits provisionTestLogins() in every process so
# they all share one set of logins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "${SCRIPT_DIR}/../../frontend" && pwd)"

split=""
pass_through=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --split)
      split="$2"
      shift 2
      ;;
    *)
      pass_through+=("$1")
      shift
      ;;
  esac
done

export E2E_LOGINS
E2E_LOGINS="$(node "${SCRIPT_DIR}/provision-test-logins.cjs")"

cd "${FRONTEND_DIR}"

if [[ -z "${split}" || "${split}" -le 1 ]]; then
  exec npx cypress run "${pass_through[@]}"
fi

pids=()
for ((i = 0; i < split; i++)); do
  SPLIT="${split}" SPLIT_INDEX="${i}" npx cypress run "${pass_through[@]}" &
  pids+=("$!")
done

status=0
for pid in "${pids[@]}"; do
  wait "${pid}" || status=$?
done
exit "${status}"
