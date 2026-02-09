# frozen_string_literal: true

module Api
  module V1
    module Ai
      # AgentContainersController - REST API for containerized agent lifecycle + callback
      #
      # Manages Docker container sessions for AI agents, including:
      # - Launching containers for agent conversations
      # - Terminating running containers
      # - Querying container status and health
      # - Receiving callback messages from containers
      class AgentContainersController < ApplicationController
        include AuditLogging

        before_action :validate_permissions
        before_action :set_container_instance, only: [:show, :destroy, :launch, :status]

        # POST /api/v1/ai/agent_containers/callback
        # Container sends messages back to platform
        def callback
          bridge = ::Ai::ContainerChatBridgeService.new(account: current_account)
          result = bridge.handle_container_response(
            conversation_id: params[:conversation_id],
            response: callback_params
          )

          if result[:success]
            render_success(message: "received", message_id: result[:message_id])
          else
            render_error(result[:error] || "Failed to process callback", status: :unprocessable_content)
          end
        rescue StandardError => e
          Rails.logger.error "[AgentContainers] Callback error: #{e.message}"
          render_internal_error("Failed to process container callback", exception: e)
        end

        # POST /api/v1/ai/agent_containers/:id/launch
        # Manually launch a container for an agent
        def launch
          if @container_instance.active?
            return render_error("Container is already active", status: :conflict)
          end

          deployment = ::Ai::ContainerAgentDeploymentService.new(account: current_account)

          agent_id = @container_instance.input_parameters&.dig("agent_id")
          agent = current_account.ai_agents.find(agent_id) if agent_id

          unless agent
            return render_error("Agent not found for this container", status: :not_found)
          end

          conversation_id = @container_instance.input_parameters&.dig("conversation_id")

          instance = deployment.deploy_agent_session(
            agent: agent,
            conversation_id: conversation_id,
            user: current_user
          )

          render_success(
            container: serialize_container(instance),
            message: "Container deployment initiated"
          )

          log_audit_event("ai.agent_containers.launch", instance)
        rescue ::Ai::ContainerAgentDeploymentService::DeploymentError => e
          render_error("Deployment failed: #{e.message}", status: :unprocessable_content)
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        end

        # DELETE /api/v1/ai/agent_containers/:id
        # Terminate a running container
        def destroy
          deployment = ::Ai::ContainerAgentDeploymentService.new(account: current_account)

          success = deployment.terminate_agent_session(
            container_instance: @container_instance,
            reason: params[:reason] || "Terminated by user"
          )

          if success
            render_success(
              container: serialize_container(@container_instance.reload),
              message: "Container terminated successfully"
            )

            log_audit_event("ai.agent_containers.terminate", @container_instance)
          else
            render_error("Failed to terminate container", status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/agent_containers/:id
        def show
          render_success(container: serialize_container(@container_instance))
        end

        # GET /api/v1/ai/agent_containers/:id/status
        def status
          deployment = ::Ai::ContainerAgentDeploymentService.new(account: current_account)
          status_data = deployment.get_session_status(container_instance: @container_instance)

          render_success(status: status_data)
        end

        private

        def set_container_instance
          @container_instance = current_account.container_instances.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Container instance not found", status: :not_found)
        end

        def validate_permissions
          case action_name
          when "show", "status"
            require_permission("ai.agents.read")
          when "launch", "callback"
            require_permission("ai.agents.execute")
          when "destroy"
            require_permission("ai.agents.delete")
          end
        end

        def callback_params
          {
            content: params[:content],
            message_type: params[:message_type] || "text",
            execution_id: params[:execution_id],
            metadata: params[:metadata]&.permit!&.to_h || {}
          }
        end

        def serialize_container(instance)
          {
            id: instance.id,
            execution_id: instance.execution_id,
            status: instance.status,
            image: "#{instance.image_name}:#{instance.image_tag}",
            agent_id: instance.input_parameters&.dig("agent_id"),
            agent_name: instance.input_parameters&.dig("agent_name"),
            conversation_id: instance.input_parameters&.dig("conversation_id"),
            cluster_name: instance.input_parameters&.dig("cluster_name"),
            template_name: instance.input_parameters&.dig("template_name"),
            chat_enabled: instance.input_parameters&.dig("chat_enabled"),
            started_at: instance.started_at&.iso8601,
            completed_at: instance.completed_at&.iso8601,
            duration_ms: instance.duration_ms,
            resource_usage: {
              memory_mb: instance.memory_used_mb,
              cpu_millicores: instance.cpu_used_millicores
            },
            created_at: instance.created_at.iso8601
          }
        end

        def current_account
          current_user.account
        end
      end
    end
  end
end
