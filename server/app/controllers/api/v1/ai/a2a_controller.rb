# frozen_string_literal: true

module Api
  module V1
    module Ai
      class A2aController < ApplicationController
        before_action :validate_permissions

        # GET /api/v1/ai/agents/:agent_id/.well-known/agent.json
        # Public endpoint for A2A agent discovery
        def agent_card
          service = ::Ai::A2a::ProtocolService.new(account: current_account)
          result = service.agent_card(agent_id: params[:agent_id])

          if result[:success]
            render_success(result[:agent_card])
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # POST /api/v1/ai/a2a/discover
        def discover
          service = ::Ai::A2a::ProtocolService.new(account: current_account)
          result = service.discover_agents(
            task_description: params[:task_description],
            capabilities: params[:capabilities],
            visibility: params[:visibility]&.to_sym || :internal
          )

          if result[:success]
            render_success(agents: result[:agents], total: result[:total])
          else
            render_error(result[:error])
          end
        end

        # POST /api/v1/ai/a2a/tasks
        # JSON-RPC 2.0 endpoint for A2A protocol
        def jsonrpc
          service = ::Ai::A2a::ProtocolService.new(account: current_account)
          result = service.handle_jsonrpc(request_params)

          render json: result
        end

        # GET /api/v1/ai/a2a/tasks/:id
        def show_task
          service = ::Ai::A2a::ProtocolService.new(account: current_account)
          result = service.get_task(
            task_id: params[:id],
            history_length: params[:history_length]&.to_i
          )

          if result[:success]
            render_success(result[:task])
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # POST /api/v1/ai/a2a/tasks/:id/cancel
        def cancel_task
          service = ::Ai::A2a::ProtocolService.new(account: current_account)
          result = service.cancel_task(
            task_id: params[:id],
            reason: params[:reason]
          )

          if result[:success]
            render_success(result[:task])
          else
            render_error(result[:error])
          end
        end

        private

        def current_account
          current_user&.account
        end

        def request_params
          params.permit(:jsonrpc, :method, :id, params: {}).to_h
        end

        def validate_permissions
          return if current_worker

          permission_map = {
            %w[agent_card discover show_task] => "ai.agents.read",
            %w[jsonrpc cancel_task] => "ai.agents.execute"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end
      end
    end
  end
end
