# frozen_string_literal: true

module Api
  module V1
    module Ai
      class McpAppsController < ApplicationController
        before_action :authenticate_request
        before_action :validate_permissions

        # GET /api/v1/ai/mcp_apps
        def index
          apps = renderer_service.list_apps(filter_params)

          render_success(
            apps: apps.map { |a| serialize_app(a) }
          )
        end

        # GET /api/v1/ai/mcp_apps/:id
        def show
          app = renderer_service.get_app(params[:id])
          render_success(app: serialize_app(app, detailed: true))
        rescue ActiveRecord::RecordNotFound
          render_not_found("MCP App")
        end

        # POST /api/v1/ai/mcp_apps
        def create
          app = renderer_service.create_app(
            app_params.merge(created_by_id: current_user&.id)
          )

          render_success(app: serialize_app(app), status: :created)
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        end

        # PATCH /api/v1/ai/mcp_apps/:id
        def update
          app = renderer_service.update_app(params[:id], app_params)
          render_success(app: serialize_app(app))
        rescue ActiveRecord::RecordNotFound
          render_not_found("MCP App")
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        end

        # DELETE /api/v1/ai/mcp_apps/:id
        def destroy
          renderer_service.delete_app(params[:id])
          render_success(message: "MCP App deleted")
        rescue ActiveRecord::RecordNotFound
          render_not_found("MCP App")
        end

        # POST /api/v1/ai/mcp_apps/:id/render
        def render_app
          app = renderer_service.get_app(params[:id])

          session = nil
          if params[:session_id].present?
            session = ::Ai::AguiSession.where(account_id: current_account.id).find(params[:session_id])
          end

          result = renderer_service.render_app(
            mcp_app: app,
            context: params[:context] || {},
            session: session
          )

          render_success(
            html: result[:html],
            instance_id: result[:instance].id,
            csp_headers: result[:csp_headers],
            sandbox_attrs: result[:sandbox_attrs]
          )
        rescue ActiveRecord::RecordNotFound
          render_not_found("MCP App")
        end

        # POST /api/v1/ai/mcp_apps/:id/process
        def process_input
          result = renderer_service.process_user_input(
            instance_id: params[:instance_id],
            input_data: params[:input_data] || {}
          )

          render_success(
            response: result[:response],
            state_update: result[:state_update]
          )
        rescue ActiveRecord::RecordNotFound
          render_not_found("MCP App Instance")
        end

        private

        def validate_permissions
          return if current_worker

          require_permission("ai.agents.read")
        end

        def renderer_service
          @renderer_service ||= ::Ai::McpApps::RendererService.new(account: current_account)
        end

        def app_params
          params.permit(
            :name, :description, :app_type, :status,
            :html_content, :version,
            csp_policy: {},
            sandbox_config: {},
            input_schema: {},
            output_schema: {},
            metadata: {}
          ).to_h.symbolize_keys
        end

        def filter_params
          params.permit(:status, :app_type, :search).to_h.symbolize_keys
        end

        def serialize_app(app, detailed: false)
          data = {
            id: app.id,
            account_id: app.account_id,
            name: app.name,
            description: app.description,
            app_type: app.app_type,
            status: app.status,
            version: app.version,
            created_by_id: app.created_by_id,
            input_schema: app.input_schema,
            output_schema: app.output_schema,
            metadata: app.metadata,
            created_at: app.created_at,
            updated_at: app.updated_at
          }

          if detailed
            data[:html_content] = app.html_content
            data[:csp_policy] = app.csp_policy
            data[:sandbox_config] = app.sandbox_config
            data[:instance_count] = app.mcp_app_instances.count
          end

          data
        end
      end
    end
  end
end
