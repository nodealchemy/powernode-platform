# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ContainerSandboxesController < ApplicationController
        before_action :validate_permissions
        before_action :set_sandbox, only: %i[show destroy pause resume metrics]

        # GET /api/v1/ai/container_sandboxes
        def index
          sandboxes = ::Devops::ContainerInstance
            .where(account_id: current_account.id)
            .where("input_parameters->>'sandbox_mode' = ?", "true")
            .order(created_at: :desc)

          sandboxes = sandboxes.where(status: params[:status]) if params[:status].present?

          render_success(data: sandboxes.map { |s| serialize_sandbox(s) })
        end

        # GET /api/v1/ai/container_sandboxes/stats
        def stats
          scope = ::Devops::ContainerInstance
            .where(account_id: current_account.id)
            .where("input_parameters->>'sandbox_mode' = ?", "true")

          render_success(data: {
            total: scope.count,
            running: scope.where(status: "running").count,
            paused: scope.where(status: "paused").count,
            completed: scope.where(status: "completed").count,
            failed: scope.where(status: "failed").count
          })
        end

        # GET /api/v1/ai/container_sandboxes/:id
        def show
          render_success(data: serialize_sandbox(@sandbox))
        end

        # POST /api/v1/ai/container_sandboxes
        def create
          agent = current_account.ai_agents.find(params[:agent_id])
          service = ::Ai::Runtime::SandboxManagerService.new(account: current_account)
          instance = service.create_sandbox(agent: agent, config: sandbox_params)

          render_success(data: serialize_sandbox(instance), status: :created)
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error("[ContainerSandboxes] Create failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/container_sandboxes/:id
        def destroy
          service = ::Ai::Runtime::SandboxManagerService.new(account: current_account)
          service.destroy_sandbox(instance: @sandbox, reason: params[:reason])

          render_success(message: "Sandbox destroyed")
        rescue StandardError => e
          Rails.logger.error("[ContainerSandboxes] Destroy failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/container_sandboxes/:id/pause
        def pause
          service = ::Ai::Runtime::SandboxManagerService.new(account: current_account)
          result = service.pause_sandbox(instance: @sandbox)

          if result[:success]
            render_success(data: serialize_sandbox(@sandbox.reload))
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/container_sandboxes/:id/resume
        def resume
          service = ::Ai::Runtime::SandboxManagerService.new(account: current_account)
          result = service.resume_sandbox(instance: @sandbox)

          if result[:success]
            render_success(data: serialize_sandbox(@sandbox.reload))
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/container_sandboxes/:id/metrics
        def metrics
          service = ::Ai::Runtime::SandboxManagerService.new(account: current_account)
          metrics_data = service.get_metrics(instance: @sandbox)

          render_success(data: metrics_data)
        end

        private

        def set_sandbox
          @sandbox = ::Devops::ContainerInstance
            .where(account_id: current_account.id)
            .where("input_parameters->>'sandbox_mode' = ?", "true")
            .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Container sandbox")
        end

        def sandbox_params
          params.permit(:image_name, :image_tag, environment: {}, volumes: [], labels: {}).to_h.symbolize_keys
        end

        def validate_permissions
          return if current_worker || current_service

          permission_map = {
            %w[index show stats metrics] => "ai.agents.read",
            %w[create] => "ai.agents.create",
            %w[destroy] => "ai.agents.delete",
            %w[pause resume] => "ai.agents.execute"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        def serialize_sandbox(instance)
          {
            id: instance.id,
            execution_id: instance.execution_id,
            agent_id: instance.input_parameters&.dig("agent_id"),
            agent_name: instance.input_parameters&.dig("agent_name"),
            status: instance.status,
            trust_level: instance.input_parameters&.dig("trust_level"),
            template_name: instance.try(:template)&.try(:name),
            image_name: instance.image_name,
            image_tag: instance.image_tag,
            sandbox_mode: true,
            memory_used_mb: instance.try(:memory_used_mb),
            cpu_used_millicores: instance.try(:cpu_used_millicores),
            started_at: instance.started_at,
            completed_at: instance.completed_at,
            created_at: instance.created_at,
            updated_at: instance.updated_at
          }
        end
      end
    end
  end
end
