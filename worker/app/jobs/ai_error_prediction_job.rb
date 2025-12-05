# frozen_string_literal: true

class AiErrorPredictionJob < BaseJob
  queue_as :default

  def execute(workflow_run_id)
    validate_required_params(workflow_run_id: workflow_run_id)

    log_info "Running error prediction for workflow run: #{workflow_run_id}"

    # Call backend API to perform error prediction
    # Prediction logic and ML models should be on the backend
    response = with_api_retry do
      api_client.post("/api/v1/ai/workflow_runs/#{workflow_run_id}/predict_errors")
    end

    if response['success']
      data = response['data']
      predictions_count = data['predictions_count'] || 0

      if predictions_count > 0
        log_info "Found #{predictions_count} potential errors for run: #{workflow_run_id}"
      else
        log_info "No potential errors detected for run: #{workflow_run_id}"
      end

      {
        success: true,
        workflow_run_id: workflow_run_id,
        predictions_found: predictions_count,
        measures_applied: data['measures_applied'] || 0
      }
    else
      error_message = response['error'] || 'Error prediction failed'
      log_error "Error prediction failed: #{error_message}"

      {
        success: false,
        workflow_run_id: workflow_run_id,
        error: error_message
      }
    end
  rescue StandardError => e
    log_error "Error prediction job failed: #{e.message}"
    { success: false, workflow_run_id: workflow_run_id, error: e.message }
  end
end
