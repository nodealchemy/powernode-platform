# frozen_string_literal: true

# Consolidated Agents Controller - Phase 3 Controller Consolidation
#
# This controller consolidates agent-related controllers into a single
# RESTful resource controller following the AI Orchestration Redesign pattern.
#
# Consolidates:
# - AiAgentsController (agent CRUD and operations)
# - ::Ai::AgentExecutionsController (execution management)
# - Partial AiMessagesController (agent-scoped messages)
#
# Architecture:
# - Primary resource: Agents
# - Nested resources: Executions, Conversations
# - Delegates to Ai::Agents::* services for business logic
#
module Api
  module V1
    module Ai
      class AgentsController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering
        include ::Ai::AgentSerialization
        include ::Ai::AgentExecutionActions
        include ::Ai::AgentConversationActions
        include ::Ai::AgentSkillActions

        before_action :set_agent, only: %i[
          show update destroy execute clone test validate
          pause resume archive stats analytics connections
          skills assign_skill remove_skill
          conversations_index conversation_show conversation_create
          conversation_update conversation_destroy send_message
          pause_conversation resume_conversation complete_conversation
          archive_conversation conversation_messages export_conversation
        ]

        before_action :set_agent_execution, only: %i[
          execution_show execution_update execution_destroy
          execution_cancel execution_retry execution_logs
        ]

        before_action :validate_permissions

        # =============================================================================
        # AGENTS - PRIMARY RESOURCE CRUD
        # =============================================================================

        # GET /api/v1/ai/agents
        def index
          agents = current_user.account.ai_agents.includes(:creator, :provider, agent_skills: :skill)
          agents = apply_agent_filters(agents, current_user: current_user)
          agents = apply_agent_sorting(agents)
          agents = apply_pagination(agents)

          render_success({ items: agents.map { |agent| serialize_agent(agent) }, pagination: pagination_data(agents) })
          log_audit_event("ai.agents.read", current_user.account)
        end

        # GET /api/v1/ai/agents/:id
        def show
          render_success(agent: serialize_agent_detail(@agent))
          log_audit_event("ai.agents.read", @agent)
        end

        # POST /api/v1/ai/agents
        def create
          @agent = current_user.account.ai_agents.build(agent_params)
          @agent.creator = current_user
          @agent.status = "inactive"
          @agent.version = "1.0.0"
          @agent.metadata ||= {}

          if @agent.save
            render_success({ agent: serialize_agent_detail(@agent) }, status: :created)
            log_audit_event("ai.agents.create", @agent, agent_type: @agent.agent_type)
          else
            render_validation_error(@agent.errors)
          end
        end

        # PATCH /api/v1/ai/agents/:id
        def update
          if @agent.update(agent_update_params)
            render_success(agent: serialize_agent_detail(@agent))
            log_audit_event("ai.agents.update", @agent, changes: @agent.previous_changes.except("updated_at"))
          else
            render_validation_error(@agent.errors)
          end
        end

        # DELETE /api/v1/ai/agents/:id
        def destroy
          agent_name = @agent.name
          @agent.destroy

          render_success(message: "AI agent deleted successfully")
          log_audit_event("ai.agents.delete", current_user.account, agent_name: agent_name)
        end

        # =============================================================================
        # AGENTS - CUSTOM ACTIONS (delegated to ManagementService)
        # =============================================================================

        # POST /api/v1/ai/agents/:id/execute
        def execute
          # Convert ActionController::Parameters to Hash for JSON schema validation
          input_params = params[:input_parameters]&.to_unsafe_h || {}
          result = management_service.execute(
            input_parameters: input_params,
            provider_id: params[:ai_provider_id]
          )

          if result.success?
            render_success({ execution: serialize_execution(result.data[:execution]), agent: serialize_agent(result.data[:agent]) }, status: :created)
            log_audit_event("ai.agents.execute", @agent, execution_id: result.data[:execution].execution_id, provider_id: result.data[:execution].ai_provider_id)
          else
            render_error(result.error, status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:id/clone
        def clone
          result = management_service.clone

          if result.success?
            render_success({ agent: serialize_agent_detail(result.data[:agent]) }, status: :created)
            log_audit_event("ai.agents.clone", result.data[:agent], original_agent_id: result.data[:original_agent_id])
          else
            render_error(result.error, status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:id/test
        def test
          result = management_service.test(test_input: params[:test_input]&.to_unsafe_h || {})

          if result.success?
            render_success(test_result: result.data[:test_result], message: "Test execution completed")
            log_audit_event("ai.agents.test", @agent)
          else
            render_error(result.error, status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/agents/:id/validate
        def validate
          result = management_service.validate
          data = result.data

          if data[:valid]
            render_success(valid: true, message: "Agent configuration is valid")
          else
            render_success(valid: false, errors: data[:errors], warnings: data[:warnings])
          end
        end

        # POST /api/v1/ai/agents/:id/pause
        def pause
          result = management_service.pause

          if result.success?
            render_success(agent: serialize_agent(result.data[:agent]), message: "Agent paused successfully")
            log_audit_event("ai.agents.pause", @agent)
          else
            render_error(result.error, status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:id/resume
        def resume
          result = management_service.resume

          if result.success?
            render_success(agent: serialize_agent(result.data[:agent]), message: "Agent resumed successfully")
            log_audit_event("ai.agents.resume", @agent)
          else
            render_error(result.error, status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:id/archive
        def archive
          result = management_service.archive

          render_success(agent: serialize_agent(result.data[:agent]), message: "Agent archived successfully")
          log_audit_event("ai.agents.archive", @agent)
        end

        # GET /api/v1/ai/agents/:id/stats
        def stats
          render_success(stats: management_service.stats)
        end

        # GET /api/v1/ai/agents/:id/analytics
        def analytics
          date_range = params[:date_range]&.to_i || 30
          render_success(analytics: management_service.analytics(date_range: date_range))
        end

        # GET /api/v1/ai/agents/:id/connections
        def connections
          service = ::Ai::Agents::ConnectionsService.new(agent: @agent, account: current_user.account)
          render_success(service.call)
        end

        # GET /api/v1/ai/agents/my_agents
        def my_agents
          agents = current_user.account.ai_agents.where(creator: current_user).includes(:provider)
          agents = apply_pagination(agents.order(updated_at: :desc))

          render_success({ items: agents.map { |agent| serialize_agent(agent) }, pagination: pagination_data(agents) })
        end

        # GET /api/v1/ai/agents/public_agents
        def public_agents
          agents = current_user.account.ai_agents.where(is_public: true).includes(:creator, :provider)
          agents = apply_pagination(agents.order(updated_at: :desc))

          render_success({ items: agents.map { |agent| serialize_agent(agent) }, pagination: pagination_data(agents) })
        end

        # GET /api/v1/ai/agents/agent_types
        def agent_types
          types = %w[conversational workflow automation content_generator code_assistant data_analyzer creative specialist]

          render_success(agent_types: types.map { |type| { value: type, label: type.humanize, description: agent_type_description(type) } })
        end

        # GET /api/v1/ai/agents/statistics
        def statistics
          service = ::Ai::Agents::ManagementService.new(agent: nil, user: current_user)
          render_success(statistics: service.account_statistics)
        end

        private

        # =============================================================================
        # SERVICE ACCESSORS
        # =============================================================================

        def management_service
          @management_service ||= ::Ai::Agents::ManagementService.new(agent: @agent, user: current_user)
        end

        def execution_service
          @execution_service ||= ::Ai::Agents::ExecutionService.new(execution: @execution, user: current_user)
        end

        def conversation_service
          @conversation_service ||= ::Ai::Agents::ConversationService.new(agent: @agent, user: current_user)
        end

        # =============================================================================
        # RESOURCE LOADING
        # =============================================================================

        def set_agent
          @agent = current_user.account.ai_agents.find(params[:id] || params[:agent_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        end

        def set_agent_execution
          execution_id = params[:execution_id] || params[:id]

          if current_user
            @execution = ::Ai::AgentExecution.joins(:agent)
                                             .where(ai_agents: { account_id: current_user.account_id })
                                             .find_by!(execution_id: execution_id)
          elsif current_worker || current_service
            @execution = ::Ai::AgentExecution.find_by!(execution_id: execution_id)
          else
            render_unauthorized("Authentication required")
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Execution not found", status: :not_found)
        end

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          return if current_worker || current_service

          permission_map = {
            %w[index show my_agents public_agents agent_types statistics skills executions_index execution_show execution_logs conversations_index conversation_show conversation_messages stats analytics connections] => "ai.agents.read",
            %w[create clone assign_skill] => "ai.agents.create",
            %w[update validate] => "ai.agents.update",
            %w[destroy execution_destroy remove_skill] => "ai.agents.delete",
            %w[execute test pause resume archive execution_cancel execution_retry] => "ai.agents.execute",
            %w[conversation_create send_message] => "ai.conversations.create",
            %w[conversation_update pause_conversation resume_conversation complete_conversation regenerate] => "ai.conversations.update",
            %w[conversation_destroy] => "ai.conversations.delete",
            %w[archive_conversation export_conversation] => "ai.conversations.manage",
            %w[rate message_thread edit_history] => "ai.conversations.read",
            %w[edit_content reply_to_message] => "ai.conversations.update",
            %w[destroy_message restore_message] => "ai.conversations.delete"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def agent_params
          params.require(:agent).permit(
            :name, :description, :agent_type, :status, :system_prompt, :model_identifier,
            :temperature, :max_tokens, :top_p, :frequency_penalty, :presence_penalty,
            :is_public, :ai_provider_id,
            metadata: {}, mcp_tool_manifest: {}, mcp_input_schema: {}, mcp_output_schema: {}
          )
        end

        def agent_update_params
          params.require(:agent).permit(
            :name, :description, :status, :is_public, :ai_provider_id, :agent_type,
            # Model config - single source of truth via accessors
            :model, :temperature, :max_tokens, :system_prompt,
            :top_p, :frequency_penalty, :presence_penalty,
            metadata: {}, mcp_tool_manifest: {}, mcp_input_schema: {}, mcp_output_schema: {}, mcp_metadata: {}
          )
        end

        # =============================================================================
        # SORTING (agent-specific sorting logic)
        # =============================================================================

        def apply_agent_sorting(collection)
          case params[:sort] || "updated_at"
          when "name" then collection.order(:name)
          when "created_at" then collection.order(created_at: :desc)
          when "last_executed" then collection.order(last_executed_at: :desc, created_at: :desc)
          when "agent_type" then collection.order(:agent_type, :name)
          else collection.order(updated_at: :desc)
          end
        end

        # =============================================================================
        # HELPERS
        # =============================================================================

        def agent_type_description(type)
          {
            "conversational" => "Interactive chat agents for natural conversations",
            "workflow" => "Agents designed for multi-step workflow execution",
            "automation" => "Task automation and process management agents",
            "content_generator" => "Content creation and generation agents",
            "code_assistant" => "Programming and code-related assistance",
            "data_analyzer" => "Data analysis and insights generation",
            "creative" => "Creative content and ideation agents",
            "specialist" => "Domain-specific specialist agents"
          }[type] || "Custom agent type"
        end

      end
    end
  end
end
