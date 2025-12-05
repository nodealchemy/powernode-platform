# frozen_string_literal: true

class AiAnalyticsReportJob < BaseJob
  queue_as :default

  def execute(workflow_id, account_id, time_range_days = 30, format = 'json')
    validate_required_params(workflow_id: workflow_id, account_id: account_id)

    log_info "Generating analytics report for workflow: #{workflow_id}"

    # Call backend API to generate the analytics report
    # Analytics logic should be on the backend, not in the worker
    response = with_api_retry do
      api_client.post("/api/v1/ai/workflows/#{workflow_id}/analytics_export", {
        account_id: account_id,
        time_range_days: time_range_days,
        format: format
      })
    end

    if response['success']
      data = response['data']
      log_info "Analytics report generated successfully for workflow: #{workflow_id}"

      {
        success: true,
        workflow_id: workflow_id,
        report_size: data['size'] || 0,
        format: format,
        report_url: data['report_url']
      }
    else
      error_message = response['error'] || 'Analytics report generation failed'
      log_error "Analytics report generation failed: #{error_message}"

      {
        success: false,
        workflow_id: workflow_id,
        error: error_message
      }
    end
  rescue StandardError => e
    log_error "Analytics report job failed: #{e.message}"
    { success: false, workflow_id: workflow_id, error: e.message }
  end
end
