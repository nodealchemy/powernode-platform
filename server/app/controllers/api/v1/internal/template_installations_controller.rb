# frozen_string_literal: true

# Internal API for AI workflow template installation operations
class Api::V1::Internal::TemplateInstallationsController < Api::V1::Internal::InternalBaseController

  # POST /api/v1/internal/template_installations/:id/update
  def update
    installation = ::Ai::WorkflowTemplateInstallation.find(params[:id])
    user = params[:user_id] ? User.find(params[:user_id]) : installation.installed_by_user

    preserve_customizations = params[:preserve_customizations].nil? ? true : params[:preserve_customizations]

    success = installation.update_to_latest_version!(user, preserve_customizations: preserve_customizations)

    if success
      Rails.logger.info "Template installation updated successfully: #{installation.installation_id}"

      render_success({
        installation_id: installation.installation_id,
        template_name: installation.template_name,
        version: installation.template_version,
        updated_at: installation.updated_at
      })
    else
      Rails.logger.error "Template installation update failed: #{installation.installation_id}"
      render_error("Template update failed", status: :unprocessable_content)
    end
  rescue ActiveRecord::RecordNotFound => e
    render_error("Installation not found", status: :not_found)
  rescue StandardError => e
    render_internal_error("Update failed", exception: e)
  end
end
