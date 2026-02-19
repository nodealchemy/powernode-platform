# frozen_string_literal: true

class AiCodeFactoryRunJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(run_params)
    validate_required_params(run_params, 'contract_id', 'pr_number', 'head_sha')

    contract_id = run_params['contract_id']
    pr_number = run_params['pr_number']
    head_sha = run_params['head_sha']
    changed_files = run_params['changed_files'] || []
    repository_id = run_params['repository_id']
    account_id = run_params['account_id']

    log_info("Starting Code Factory run",
      contract_id: contract_id, pr_number: pr_number, head_sha: head_sha[0..7])

    # Step 1: PREFLIGHT - Run risk classification and validate SHA
    log_info("Running preflight gate check")
    preflight_result = backend_api_post("/api/v1/ai/code_factory/preflight", {
      contract_id: contract_id,
      pr_number: pr_number,
      head_sha: head_sha,
      changed_files: changed_files,
      repository_id: repository_id
    })

    unless preflight_result['success'] && preflight_result.dig('data', 'preflight', 'passed')
      reason = preflight_result.dig('data', 'preflight', 'reason') || 'Preflight gate failed'
      log_error("Preflight gate failed", reason: reason)
      broadcast_status(account_id, 'preflight_failed', { pr_number: pr_number, reason: reason })
      return
    end

    review_state_id = preflight_result.dig('data', 'preflight', 'review_state_id')
    risk_tier = preflight_result.dig('data', 'preflight', 'risk_tier')
    evidence_required = preflight_result.dig('data', 'preflight', 'evidence_required')

    broadcast_status(account_id, 'preflight_complete', {
      pr_number: pr_number, risk_tier: risk_tier, review_state_id: review_state_id
    })

    # Step 2: REVIEW - Trigger AI code review via server
    log_info("Code review phase", review_state_id: review_state_id)
    broadcast_status(account_id, 'review_started', { pr_number: pr_number })

    review_result = backend_api_post("/api/v1/internal/ai/code_reviews", {
      pr_number: pr_number, repository_id: repository_id,
      review_state_id: review_state_id, head_sha: head_sha
    })

    # Step 3: REMEDIATION - If findings, dispatch remediation job
    if review_result['success'] && review_result.dig('data', 'findings')&.any?
      log_info("Findings detected, dispatching remediation", findings_count: review_result.dig('data', 'findings').size)
      AiCodeFactoryRemediationJob.perform_async({
        'review_state_id' => review_state_id,
        'findings' => review_result.dig('data', 'findings'),
        'account_id' => account_id,
        'pr_number' => pr_number
      })
    else
      log_info("No remediation needed")
    end

    # Step 4: EVIDENCE - Capture if required
    if evidence_required
      log_info("Evidence capture required, dispatching evidence job")
      AiCodeFactoryEvidenceJob.perform_async({
        'review_state_id' => review_state_id,
        'account_id' => account_id,
        'pr_number' => pr_number
      })
    end

    # Step 5: RESOLVE - Auto-resolve bot threads
    log_info("Resolving bot-only threads")
    backend_api_post("/api/v1/ai/code_factory/review_states/#{review_state_id}/resolve_threads", {})

    # Step 6: COMPLETE
    broadcast_status(account_id, 'run_completed', {
      pr_number: pr_number,
      risk_tier: risk_tier,
      review_state_id: review_state_id
    })

    log_info("Code Factory run completed",
      pr_number: pr_number, risk_tier: risk_tier)
  rescue StandardError => e
    log_error("Code Factory run failed", error: e.message, pr_number: run_params['pr_number'])
    broadcast_status(run_params['account_id'], 'run_failed', {
      pr_number: run_params['pr_number'], error: e.message
    })
    raise
  end

  private

  def broadcast_status(account_id, event_type, payload)
    backend_api_post("/api/v1/internal/broadcasts", {
      channel: "code_factory:account:#{account_id}",
      event: "code_factory.#{event_type}",
      payload: payload
    })
  rescue StandardError => e
    log_warn("Broadcast failed", error: e.message)
  end
end
