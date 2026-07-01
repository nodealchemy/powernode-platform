#!/bin/bash
# Kill-switch compliance check (model-agnostic; run by scripts/pattern-validation.sh,
# scripts/validate.sh, and the git pre-commit hook — so it binds ANY committer/executor,
# not just Claude).
#
# Enforces the rule in worker/CLAUDE.md L11: every worker job that performs AI
# execution (direct LLM inference OR backend AI dispatch) MUST
# `include AiSuspensionCheckConcern` AND call `bail_if_ai_suspended!` first in
# #execute, so the global emergency_halt / per-account kill switch actually stops it.
# An include with no call is still a silent bypass, so both are required.
#
# Two layers:
#   1. AUTHORITATIVE required set — mirrors the regression specs (source of truth):
#        worker/spec/jobs/ai_direct_inference_suspension_spec.rb
#        worker/spec/jobs/ai_backend_dispatch_suspension_spec.rb
#        worker/spec/jobs/ai_agent_execution_job_spec.rb
#      Keep REQUIRED_JOBS below in sync with those specs.
#   2. MARKER sweep — catches a NEWLY-added job that calls a provider directly or
#      delegates through the LLM proxy but forgot the concern. Low false-positive:
#      these markers only ever appear in real AI-execution jobs.
#
# Excluded by design (documented in the backend-dispatch spec): global,
# cross-account memory jobs (ai_memory_consolidation_job / ai_memory_maintenance_job)
# — there is no single account to gate on; they are handled separately.
#
# Exit 0 = compliant; exit 1 = one or more violations (names printed to stdout).

set -euo pipefail

# Resolve the repo root from this script's own location so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
JOBS_DIR="${REPO_ROOT}/worker/app/jobs"

# --- Layer 1: authoritative required set (mirror the regression specs) --------
REQUIRED_JOBS=(
  # ai_direct_inference_suspension_spec.rb
  ai_chat_response_job
  ai_workspace_response_job
  ai_conversation_response_job
  ai_code_factory_prd_job
  # ai_backend_dispatch_suspension_spec.rb
  ai_mission_execute_job
  ai_mission_plan_job
  ai_provisioning_capture_intent_job
  ai_provisioning_compose_plan_job
  ai_code_factory_remediation_job
  ai_codebase_index_job
  ai_agent_team_execution_job
  ai_ralph_loop_run_all_job
  ai_a2a_external_task_job
  ai_reflexion_job
  ai_goal_plan_execution_job
  ai_self_challenge_job
  # ai_agent_execution_job_spec.rb
  ai_agent_execution_job
)

violations=()

for job in "${REQUIRED_JOBS[@]}"; do
  file="${JOBS_DIR}/${job}.rb"
  if [[ ! -f "$file" ]]; then
    violations+=("${job}.rb: MISSING (required by kill-switch regression specs)")
    continue
  fi
  if ! grep -q 'include AiSuspensionCheckConcern' "$file"; then
    violations+=("${job}.rb: missing 'include AiSuspensionCheckConcern'")
  fi
  if ! grep -q 'bail_if_ai_suspended!' "$file"; then
    violations+=("${job}.rb: missing 'bail_if_ai_suspended!' call")
  fi
done

# --- Layer 2: marker sweep for newly-added AI-execution jobs -------------------
# Job files that call a provider directly or delegate through the LLM proxy but
# do not include the concern. Concern definition files are excluded (they DEFINE
# these markers rather than consume them).
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in */concerns/*) continue ;; esac
  if ! grep -q 'include AiSuspensionCheckConcern' "$file"; then
    rel="${file#"${REPO_ROOT}/"}"
    violations+=("${rel}: AI-execution marker (provider/LLM-proxy call) but missing 'include AiSuspensionCheckConcern'")
  fi
done < <(grep -rlE 'call_ai_provider|call_provider_streaming|include AiLlmProxyConcern' "$JOBS_DIR" --include='*.rb' 2>/dev/null || true)

if [[ ${#violations[@]} -eq 0 ]]; then
  echo "kill-switch compliance OK (${#REQUIRED_JOBS[@]} required AI-execution jobs include AiSuspensionCheckConcern + call bail_if_ai_suspended!)"
  exit 0
fi

echo "kill-switch compliance FAILED — ${#violations[@]} violation(s):"
for v in "${violations[@]}"; do
  echo "  - $v"
done
exit 1
