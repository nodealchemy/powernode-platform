# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class ContainersController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_instance, only: %i[show cancel logs artifacts]

        # GET /api/v1/mcp/containers
        # List container executions
        def index
          scope = current_user.account.mcp_container_instances

          # Apply filters
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(template_id: params[:template_id]) if params[:template_id].present?
          scope = scope.active if params[:active] == "true"
          scope = scope.finished if params[:finished] == "true"

          # Date range
          if params[:since].present?
            scope = scope.where("created_at >= ?", Time.zone.parse(params[:since]))
          end

          # Sorting and pagination
          scope = scope.order(created_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:instance_summary),
            pagination: pagination_data(scope)
          )
          log_audit_event("mcp.containers.list", current_user.account)
        end

        # GET /api/v1/mcp/containers/:id
        def show
          render_success(instance: @instance.instance_details)
          log_audit_event("mcp.containers.read", @instance)
        end

        # POST /api/v1/mcp/containers
        # Execute a container
        def execute
          template = current_user.account.mcp_container_templates.find(params[:template_id])

          service = ::Mcp::ContainerOrchestrationService.new(
            account: current_user.account,
            user: current_user
          )

          begin
            instance = service.execute(
              template: template,
              input_parameters: params[:input_parameters]&.to_unsafe_h || {},
              timeout_seconds: params[:timeout_seconds]&.to_i,
              a2a_task: params[:a2a_task_id].present? ? current_user.account.ai_a2a_tasks.find(params[:a2a_task_id]) : nil
            )

            render_success({ instance: instance.instance_details }, status: :created)
            log_audit_event("mcp.containers.execute", instance)
          rescue ::Mcp::QuotaService::QuotaExceededError => e
            render_error("Quota exceeded: #{e.message}", status: :too_many_requests)
          rescue ::Mcp::ContainerOrchestrationService::OrchestrationError => e
            render_error(e.message, status: :unprocessable_entity)
          end
        end

        # POST /api/v1/mcp/containers/:id/cancel
        def cancel
          service = ::Mcp::ContainerOrchestrationService.new(
            account: current_user.account,
            user: current_user
          )

          if service.cancel(@instance.execution_id, reason: params[:reason])
            render_success(instance: @instance.reload.instance_details)
            log_audit_event("mcp.containers.cancel", @instance)
          else
            render_error("Could not cancel execution", status: :unprocessable_entity)
          end
        end

        # GET /api/v1/mcp/containers/:id/logs
        def logs
          render_success(
            execution_id: @instance.execution_id,
            logs: @instance.logs,
            status: @instance.status
          )
        end

        # GET /api/v1/mcp/containers/:id/artifacts
        def artifacts
          render_success(
            execution_id: @instance.execution_id,
            artifacts: @instance.artifacts || [],
            status: @instance.status
          )
        end

        # GET /api/v1/mcp/containers/active
        def active
          scope = current_user.account.mcp_container_instances.active
          scope = scope.order(created_at: :desc)

          render_success(
            items: scope.map(&:instance_summary),
            count: scope.count
          )
        end

        # GET /api/v1/mcp/containers/stats
        def stats
          account = current_user.account
          instances = account.mcp_container_instances

          render_success(
            stats: {
              total: instances.count,
              active: instances.active.count,
              completed: instances.completed.count,
              failed: instances.failed.count,
              avg_duration_ms: instances.finished.average(:duration_ms)&.round(2),
              success_rate: instances.finished.count > 0 ?
                (instances.successful.count.to_f / instances.finished.count * 100).round(2) : 0,
              by_status: instances.group(:status).count,
              by_template: instances.joins(:template).group("mcp_container_templates.name").count
            }
          )
        end

        private

        def set_instance
          @instance = current_user.account.mcp_container_instances.find(params[:id])
        end
      end
    end
  end
end
