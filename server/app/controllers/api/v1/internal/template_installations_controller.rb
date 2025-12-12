# frozen_string_literal: true

# Internal API for AI workflow template installation operations
class Api::V1::Internal::TemplateInstallationsController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token

  # POST /api/v1/internal/template_installations/:id/update
  def update
    installation = AiWorkflowTemplateInstallation.find(params[:id])
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
      render_error("Template update failed", status: :unprocessable_entity)
    end
  rescue ActiveRecord::RecordNotFound => e
    render_error("Installation not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Template installation update error: #{e.message}"
    render_error("Update failed: #{e.message}", status: :internal_server_error)
  end

  private

  def authenticate_service_token
    token = request.headers["Authorization"]&.split(" ")&.last

    unless token.present?
      render_error("Service token required", status: :unauthorized)
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: "HS256").first

      unless payload["service"] == "worker" && payload["type"] == "service"
        render_error("Invalid service token", status: :unauthorized)
        nil
      end

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error("Invalid service token", status: :unauthorized)
    end
  end
end
