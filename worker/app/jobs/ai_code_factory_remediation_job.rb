# frozen_string_literal: true

class AiCodeFactoryRemediationJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 2

  def execute(remediation_params)
    validate_required_params(remediation_params, 'review_state_id')

    review_state_id = remediation_params['review_state_id']
    findings = remediation_params['findings'] || []
    account_id = remediation_params['account_id']

    log_info("Starting Code Factory remediation",
      review_state_id: review_state_id, findings_count: findings.size)

    return if findings.empty?

    # Group findings by file for efficient patching
    findings_by_file = findings.group_by { |f| f['file_path'] }

    fixed_count = 0
    failed_count = 0

    findings_by_file.each do |file_path, file_findings|
      log_info("Attempting remediation for file", file_path: file_path, findings: file_findings.size)

      begin
        # Call AI provider for fix generation via server API
        fix_result = backend_api_post("/api/v1/ai/code_factory/review_states/#{review_state_id}/remediate", {
          findings: file_findings
        })

        if fix_result['success']
          fixed_count += file_findings.size
        else
          failed_count += file_findings.size
          log_warn("Remediation failed for file", file_path: file_path,
            error: fix_result.dig('error', 'message'))
        end
      rescue StandardError => e
        failed_count += file_findings.size
        log_error("Remediation error for file", file_path: file_path, error: e.message)
      end
    end

    log_info("Remediation completed",
      fixed: fixed_count, failed: failed_count, total: findings.size)
  rescue StandardError => e
    log_error("Code Factory remediation job failed", error: e.message)
    raise
  end

  private

  def build_fix_prompt(file_path, findings)
    finding_descriptions = findings.map do |f|
      severity = f['severity'] || 'medium'
      message = f['message'] || f['description'] || 'Unknown issue'
      line = f['line_start']
      "- [#{severity.upcase}] Line #{line}: #{message}"
    end.join("\n")

    "Fix the following code review findings in `#{file_path}`:\n\n#{finding_descriptions}"
  end
end
