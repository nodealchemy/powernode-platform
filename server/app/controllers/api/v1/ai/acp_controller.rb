# frozen_string_literal: true

module Api
  module V1
    module Ai
      class AcpController < ApplicationController
        before_action :validate_permissions

        # GET /api/v1/ai/acp
        # Protocol information endpoint
        def info
          service = acp_service
          result = service.protocol_info

          render_success(result.except(:success))
        end

        # GET /api/v1/ai/acp/agents
        # List available agents with ACP profile format
        def list_agents
          result = acp_service.list_agents(filter: agent_filter_params)

          if result[:success]
            render_success(result.except(:success))
          else
            render_error(result[:error])
          end
        end

        # GET /api/v1/ai/acp/agents/:id
        # Get single agent ACP profile
        def show_agent
          result = acp_service.get_agent_profile(agent_id: params[:id])

          if result[:success]
            render_success(result.except(:success))
          else
            render_error(result[:error], status: result[:http_status] || :not_found)
          end
        end

        # POST /api/v1/ai/acp/agents/:id/negotiate
        # Capability negotiation
        def negotiate
          result = acp_service.negotiate_capabilities(
            agent_id: params[:id],
            offered_capabilities: params[:offered_capabilities],
            required_capabilities: params[:required_capabilities]
          )

          if result[:success]
            render_success(result.except(:success))
          else
            render_error(result[:error], status: result[:http_status] || :bad_request)
          end
        end

        # POST /api/v1/ai/acp/agents/:id/messages
        # Send message to agent
        def send_message
          result = acp_service.send_message(
            to_agent_id: params[:id],
            from_agent_id: params[:from_agent_id],
            message: message_params,
            metadata: params[:metadata]&.to_unsafe_h || {}
          )

          if result[:success]
            render_success(result.except(:success))
          else
            render_error(result[:error], status: result[:http_status] || :bad_request)
          end
        end

        # GET /api/v1/ai/acp/messages/:id
        # Get message status
        def show_message
          result = acp_service.get_message(message_id: params[:id])

          if result[:success]
            render_success(result.except(:success))
          else
            render_error(result[:error], status: result[:http_status] || :not_found)
          end
        end

        # POST /api/v1/ai/acp/messages/:id/cancel
        # Cancel a message
        def cancel_message
          result = acp_service.cancel_message(
            message_id: params[:id],
            reason: params[:reason]
          )

          if result[:success]
            render_success(result.except(:success))
          else
            render_error(result[:error], status: result[:http_status] || :bad_request)
          end
        end

        # GET /api/v1/ai/acp/agents/:id/events
        # Get event stream for agent
        def events
          result = acp_service.get_agent_events(
            agent_id: params[:id],
            since: params[:since],
            limit: (params[:limit] || 50).to_i
          )

          if result[:success]
            render_success(result.except(:success))
          else
            render_error(result[:error], status: result[:http_status] || :bad_request)
          end
        end

        private

        def acp_service
          ::Ai::Acp::ProtocolService.new(account: current_account)
        end

        def current_account
          current_user&.account
        end

        def agent_filter_params
          params.permit(:query, capabilities: []).to_h.symbolize_keys
        end

        def message_params
          params.require(:message).permit(:type, :content, data: {}).to_h.symbolize_keys
        end

        def validate_permissions
          return if current_worker || current_service

          permission_map = {
            %w[info list_agents show_agent events] => "ai.agents.read",
            %w[negotiate send_message cancel_message show_message] => "ai.agents.execute"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end
      end
    end
  end
end
