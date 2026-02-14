# frozen_string_literal: true

module Api
  module V1
    module Ai
      class SandboxesController < ApplicationController
        before_action :set_service
        before_action :set_sandbox, only: %i[show update destroy activate deactivate analytics]
        before_action :validate_permissions

        # GET /api/v1/ai/sandboxes
        def index
          sandboxes = current_account.ai_sandboxes
                                     .order(created_at: :desc)
                                     .page(params[:page])
                                     .per(params[:per_page] || 20)

          sandboxes = sandboxes.by_type(params[:sandbox_type]) if params[:sandbox_type].present?
          sandboxes = sandboxes.where(status: params[:status]) if params[:status].present?

          render_success(
            sandboxes: sandboxes.map { |s| sandbox_json(s) },
            pagination: pagination_meta(sandboxes)
          )
        end

        # POST /api/v1/ai/sandboxes
        def create
          sandbox = @service.create_sandbox(
            name: params[:name],
            sandbox_type: params[:sandbox_type] || "standard",
            user: current_user,
            description: params[:description],
            configuration: params[:configuration] || {},
            expires_at: params[:expires_at]
          )

          render_success(sandbox: sandbox_json(sandbox), status: :created)
        end

        # GET /api/v1/ai/sandboxes/:id
        def show
          render_success(sandbox: sandbox_json(@sandbox, detailed: true))
        end

        # PUT /api/v1/ai/sandboxes/:id
        def update
          @sandbox.update!(sandbox_params)
          render_success(sandbox: sandbox_json(@sandbox))
        end

        # DELETE /api/v1/ai/sandboxes/:id
        def destroy
          @sandbox.update!(status: "deleted")
          render_success(message: "Sandbox deleted successfully")
        end

        # PUT /api/v1/ai/sandboxes/:id/activate
        def activate
          result = @service.activate_sandbox(@sandbox)

          if result[:success]
            render_success(sandbox: sandbox_json(result[:sandbox]))
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # PUT /api/v1/ai/sandboxes/:id/deactivate
        def deactivate
          @sandbox.deactivate!
          render_success(sandbox: sandbox_json(@sandbox))
        end

        # GET /api/v1/ai/sandboxes/:id/analytics
        def analytics
          analytics = @service.get_sandbox_analytics(@sandbox)
          render_success(analytics: analytics)
        end

        private

        def validate_permissions
          return if current_worker

          case action_name
          when "index", "show", "analytics"
            require_permission("ai.sandboxes.read")
          when "create"
            require_permission("ai.sandboxes.create")
          when "update"
            require_permission("ai.sandboxes.update")
          when "destroy"
            require_permission("ai.sandboxes.delete")
          when "activate", "deactivate"
            require_permission("ai.sandboxes.manage")
          end
        end

        def set_service
          @service = ::Ai::SandboxService.new(current_account)
        end

        def set_sandbox
          @sandbox = current_account.ai_sandboxes.find(params[:id] || params[:sandbox_id])
        end

        def sandbox_params
          params.permit(:name, :description, :sandbox_type, :configuration, :resource_limits, :expires_at)
        end

        def sandbox_json(sandbox, detailed: false)
          json = {
            id: sandbox.id,
            name: sandbox.name,
            description: sandbox.description,
            sandbox_type: sandbox.sandbox_type,
            status: sandbox.status,
            is_isolated: sandbox.is_isolated,
            recording_enabled: sandbox.recording_enabled,
            test_runs_count: sandbox.test_runs_count,
            total_executions: sandbox.total_executions,
            last_used_at: sandbox.last_used_at,
            expires_at: sandbox.expires_at,
            created_at: sandbox.created_at
          }

          if detailed
            json.merge!(
              configuration: sandbox.configuration,
              mock_providers: sandbox.mock_providers,
              environment_variables: sandbox.environment_variables,
              resource_limits: sandbox.resource_limits
            )
          end

          json
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count,
            per_page: collection.limit_value
          }
        end
      end
    end
  end
end
