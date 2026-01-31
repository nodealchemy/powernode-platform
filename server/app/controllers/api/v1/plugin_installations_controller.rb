# frozen_string_literal: true

module Api
  module V1
    class PluginInstallationsController < ApplicationController
      before_action :set_installation, only: [ :show, :update, :activate, :deactivate, :configure ]

      # GET /api/v1/plugin_installations
      def index
        installations = current_account.plugin_installations
                                       .includes(:plugin, :installed_by)
                                       .order(installed_at: :desc)

        # Apply filters
        installations = installations.where(status: params[:status]) if params[:status].present?

        render_success(
          installations: installations.as_json(
            include: {
              plugin: { only: [ :id, :plugin_id, :name, :version, :plugin_types ] },
              installed_by: { only: [ :id, :email, :full_name ] }
            },
            methods: [ :execution_count, :total_cost ]
          )
        )
      end

      # GET /api/v1/plugin_installations/:id
      def show
        render_success(
          installation: @installation.as_json(
            include: {
              plugin: {
                include: {
                  ai_provider_plugin: {},
                  workflow_node_plugins: {}
                }
              },
              installed_by: { only: [ :id, :email, :full_name ] }
            },
            methods: [ :execution_count, :total_cost ]
          )
        )
      end

      # PATCH /api/v1/plugin_installations/:id
      def update
        if @installation.update(installation_params)
          render_success(
            installation: @installation.as_json,
            message: "Installation updated successfully"
          )
        else
          render_validation_error(@installation.errors)
        end
      end

      # POST /api/v1/plugin_installations/:id/activate
      def activate
        @installation.activate!
        render_success(
          installation: @installation.as_json,
          message: "Plugin activated successfully"
        )
      rescue StandardError => e
        render_error("Activation failed: #{e.message}", status: :unprocessable_content)
      end

      # POST /api/v1/plugin_installations/:id/deactivate
      def deactivate
        @installation.deactivate!
        render_success(
          installation: @installation.as_json,
          message: "Plugin deactivated successfully"
        )
      rescue StandardError => e
        render_error("Deactivation failed: #{e.message}", status: :unprocessable_content)
      end

      # PATCH /api/v1/plugin_installations/:id/configure
      def configure
        service = PluginInstallationService.new
        service.update_plugin_configuration(@installation, configuration_params)

        render_success(
          installation: @installation.reload.as_json,
          message: "Plugin configuration updated successfully"
        )
      rescue StandardError => e
        render_error("Configuration update failed: #{e.message}", status: :unprocessable_content)
      end

      # POST /api/v1/plugin_installations/:id/set_credential
      def set_credential
        credential_key = params[:credential_key]
        credential_value = params[:credential_value]

        if credential_key.blank? || credential_value.blank?
          return render_error("Credential key and value are required", status: :unprocessable_content)
        end

        @installation.set_credential(credential_key, credential_value)

        render_success(message: "Credential set successfully")
      rescue StandardError => e
        render_error("Failed to set credential: #{e.message}", status: :unprocessable_content)
      end

      private

      def set_installation
        @installation = current_account.plugin_installations.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Installation not found")
      end

      def installation_params
        params.require(:installation).permit(
          :status,
          configuration: {}
        )
      end

      def configuration_params
        # Plugin configurations have dynamic schemas defined by each plugin
        params.require(:configuration).to_unsafe_h
      end
    end
  end
end
