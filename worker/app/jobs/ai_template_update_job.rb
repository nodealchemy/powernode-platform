# frozen_string_literal: true

class AiTemplateUpdateJob < BaseJob
  queue_as :default

  def execute(installation_id, user_id = nil)
    validate_required_params(installation_id: installation_id)

    log_info "Updating template installation: #{installation_id}"

    # Call backend API to perform the update
    response = with_api_retry do
      api_client.post("/api/v1/internal/template_installations/#{installation_id}/update", {
        user_id: user_id,
        preserve_customizations: true
      })
    end

    if response['success']
      data = response['data']
      log_info "Template update successful: #{data['template_name']} -> #{data['version']}"

      {
        success: true,
        installation_id: data['installation_id'],
        new_version: data['version']
      }
    else
      error_message = response['error'] || 'Update failed'
      log_error "Template update failed: #{error_message}"

      {
        success: false,
        installation_id: installation_id,
        error: error_message
      }
    end
  rescue StandardError => e
    log_error "Template update job failed: #{e.message}"
    { success: false, installation_id: installation_id, error: e.message }
  end
end
