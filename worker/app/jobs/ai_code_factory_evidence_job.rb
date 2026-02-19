# frozen_string_literal: true

class AiCodeFactoryEvidenceJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 2

  def execute(evidence_params)
    validate_required_params(evidence_params, 'review_state_id')

    review_state_id = evidence_params['review_state_id']
    account_id = evidence_params['account_id']
    pr_number = evidence_params['pr_number']

    log_info("Starting evidence capture",
      review_state_id: review_state_id, pr_number: pr_number)

    # Fetch evidence requirements from server
    review_state = backend_api_get("/api/v1/ai/code_factory/review_states/#{review_state_id}")
    unless review_state['success']
      log_error("Could not fetch review state", review_state_id: review_state_id)
      return
    end

    state_data = review_state.dig('data', 'review_state')
    evidence_config = state_data&.dig('risk_contract', 'evidence_requirements') || {}

    # Capture evidence artifacts
    artifacts = []
    assertions = []

    # Browser evidence capture (Playwright integration)
    urls = evidence_config['urls'] || []

    urls.each do |url_config|
      url = url_config['url'] || url_config
      log_info("Capturing evidence for URL", url: url)

      artifact = capture_url_evidence(url)
      artifacts << artifact if artifact
    end

    # Run assertions if configured
    assertion_configs = evidence_config['assertions'] || []
    assertion_configs.each do |assertion_config|
      assertion_result = run_assertion(assertion_config)
      assertions << assertion_result
    end

    # Submit evidence manifest to server
    result = backend_api_post("/api/v1/ai/code_factory/evidence", {
      review_state_id: review_state_id,
      manifest_type: determine_manifest_type(artifacts, assertions),
      artifacts: artifacts,
      assertions: assertions
    })

    if result['success']
      log_info("Evidence submitted successfully",
        artifacts_count: artifacts.size, assertions_count: assertions.size)
    else
      log_error("Evidence submission failed",
        error: result.dig('error', 'message'))
    end
  rescue StandardError => e
    log_error("Evidence capture job failed", error: e.message)
    raise
  end

  private

  def capture_url_evidence(url)
    {
      'type' => 'screenshot',
      'url' => url,
      'status' => 'not_available',
      'reason' => 'Browser evidence capture requires Playwright setup',
      'captured_at' => Time.current.iso8601
    }
  rescue StandardError => e
    log_warn("Evidence capture failed for URL", url: url, error: e.message)
    nil
  end

  def run_assertion(config)
    {
      'type' => config['type'] || 'element_exists',
      'selector' => config['selector'],
      'expected' => config['expected'],
      'status' => 'skipped',
      'reason' => 'Assertion evaluation requires browser runtime'
    }
  end

  def determine_manifest_type(artifacts, assertions)
    return 'combined' if artifacts.any? && assertions.any?
    return 'assertion' if assertions.any?
    return 'screenshot' if artifacts.any? { |a| a['type'] == 'screenshot' }
    return 'video' if artifacts.any? { |a| a['type'] == 'video' }

    'browser_test'
  end
end
