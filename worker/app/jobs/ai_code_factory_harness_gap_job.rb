# frozen_string_literal: true

class AiCodeFactoryHarnessGapJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_maintenance', retry: 3

  def execute(gap_params)
    validate_required_params(gap_params, 'harness_gap_id')

    gap_id = gap_params['harness_gap_id']
    account_id = gap_params['account_id']

    log_info("Processing harness gap", gap_id: gap_id)

    # Fetch gap details from server
    gap_response = backend_api_get("/api/v1/ai/code_factory/harness_gaps")
    unless gap_response['success']
      log_error("Could not fetch harness gaps")
      return
    end

    gaps = gap_response.dig('data', 'harness_gaps') || []
    gap = gaps.find { |g| g['id'] == gap_id }

    unless gap
      log_error("Harness gap not found", gap_id: gap_id)
      return
    end

    # Analyze regression context
    incident_source = gap['incident_source']
    description = gap['description']
    severity = gap['severity']

    # Generate test case reference based on incident type
    test_reference = generate_test_reference(incident_source, description, severity)

    if test_reference
      # Submit test case to server
      result = backend_api_patch("/api/v1/ai/code_factory/harness_gaps/#{gap_id}/add_case", {
        test_reference: test_reference
      })

      if result['success']
        log_info("Test case added to harness gap",
          gap_id: gap_id, test_reference: test_reference)
      else
        log_error("Failed to add test case",
          gap_id: gap_id, error: result.dig('error', 'message'))
      end
    else
      log_warn("Could not generate test reference", gap_id: gap_id)
    end
  rescue StandardError => e
    log_error("Harness gap job failed", error: e.message)
    raise
  end

  private

  def generate_test_reference(source, description, severity)
    case source
    when 'production_regression', 'test_failure'
      "spec/regression/#{sanitize_for_filename(description)}_spec.rb"
    when 'review_finding'
      "spec/code_factory/review_findings/#{sanitize_for_filename(description)}_spec.rb"
    when 'manual'
      "spec/manual/#{sanitize_for_filename(description)}_spec.rb"
    else
      "spec/harness_gaps/#{sanitize_for_filename(description)}_spec.rb"
    end
  end

  def sanitize_for_filename(text)
    text.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')[0..60]
  end
end
