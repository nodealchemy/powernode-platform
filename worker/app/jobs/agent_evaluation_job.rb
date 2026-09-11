# frozen_string_literal: true

# D4 — drives the LLM judge for one completed unit of work.
#
# EVENT-DRIVEN, deliberately not on a cron: there is no sweep to run, the
# server enqueues one of these per completion (Ai::Tools::DevLoopTool#complete_task
# -> WorkerJobService.enqueue_job). It therefore has no entry in
# config/sidekiq.yml, unlike the scheduled jobs around it.
#
# The job carries IDS ONLY and no policy. Every gate — the ai.evaluation.enabled
# switch and daily cap, whether the execution is evaluable, whether the judge answered, the
# idempotency key — lives server-side in Ai::Learning::EvaluationService, so a
# retry of this job cannot produce a second evaluation.
class AgentEvaluationJob < BaseJob
  # Evaluating spends an LLM call against the account, so this is AI execution
  # and the kill switch reaches it. The server refuses too (EvaluationService
  # returns not_measured/AiSuspended), which is the authoritative gate — this
  # one stops the round trip before it starts. Listed in
  # scripts/checks/kill-switch-compliance-check.sh REQUIRED_JOBS.
  include AiSuspensionCheckConcern

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

    return { status: "not_measured", reason: "AiSuspended" } if bail_if_ai_suspended!(account_id)

    body = { account_id: account_id, execution_id: execution_id }
    body[:task_id] = payload["task_id"] if payload["task_id"].to_s != ""

    begin
      response = api_client.post("/api/v1/internal/ai/evaluations/run", body)
    rescue BackendApiClient::ApiError => e
      raise unless e.status == 404

      # The server 404s an execution that is missing OR belongs to another
      # account, indistinguishably (D4 review F2). Neither can ever succeed, so
      # a retry would only repeat the refusal: terminal, and said so. Every
      # other failure still raises, so Sidekiq retries it.
      log_warn "[AgentEvaluationJob] execution #{execution_id} not found for this worker's account; not retrying"
      return { status: "not_measured", reason: "ExecutionNotFound", evaluation_id: nil }
    end
    data = response["data"] || {}

    log_info "[AgentEvaluationJob] execution #{execution_id}: #{data['status']} #{data['reason']}".strip
    { status: data["status"], reason: data["reason"], evaluation_id: data["evaluation_id"] }
  end
end
