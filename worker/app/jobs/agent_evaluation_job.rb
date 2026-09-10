# frozen_string_literal: true

# D4 — drives the LLM judge for one completed unit of work.
#
# EVENT-DRIVEN, deliberately not on a cron: there is no sweep to run, the
# server enqueues one of these per completion (Ai::Tools::DevLoopTool#complete_task
# -> WorkerJobService.enqueue_job). It therefore has no entry in
# config/sidekiq.yml, unlike the scheduled jobs around it.
#
# The job carries IDS ONLY and no policy. Every gate — the :agent_evaluation
# flag, whether the execution is evaluable, whether the judge answered, the
# idempotency key — lives server-side in Ai::Learning::EvaluationService, so a
# retry of this job cannot produce a second evaluation.
class AgentEvaluationJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 2

  # args arrives from Sidekiq as JSON, so its keys are STRINGS however the
  # server wrote them. Reading symbols here would find nothing and post a
  # payload of nils, which the server would answer with a cheerful
  # not_measured — a silent no-op that looks like success.
  def execute(args = {})
    payload = (args || {}).transform_keys(&:to_s)
    account_id = payload["account_id"]
    execution_id = payload["execution_id"]

    if account_id.to_s.empty? || execution_id.to_s.empty?
      log_warn "[AgentEvaluationJob] missing account_id or execution_id; nothing to evaluate"
      return { status: "not_measured", reason: "MissingArguments" }
    end

    body = { account_id: account_id, execution_id: execution_id }
    body[:task_id] = payload["task_id"] if payload["task_id"].to_s != ""

    response = api_client.post("/api/v1/internal/ai/evaluations/run", body)
    data = response["data"] || {}

    log_info "[AgentEvaluationJob] execution #{execution_id}: #{data['status']} #{data['reason']}".strip
    { status: data["status"], reason: data["reason"], evaluation_id: data["evaluation_id"] }
  end
end
