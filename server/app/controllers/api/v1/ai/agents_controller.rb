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
        include ::Ai::AgentHelpers
        # Global (platform-managed) agents vs account-owned copies: clone-to-
        # customize, 3-way update_from_source rebase, and the read-only guard.
        include ::GloballyScopedContent

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
        # A GLOBAL agent is platform-managed/read-only — consumers must clone it
        # to customize (Ai::Agent#clone_to_account). Guard the actions that
        # mutate the agent definition; using a global agent (execute/show) is fine.
        before_action :require_editable_agent!, only: %i[update destroy pause resume archive assign_skill remove_skill]

        # =============================================================================
        # AGENTS - PRIMARY RESOURCE CRUD
        # =============================================================================

        # GET /api/v1/ai/agents
        def index
          # for_account = own + GLOBAL platform agents; ?scope=global|custom|all
          # narrows it (apply_content_scope).
          agents = apply_content_scope(::Ai::Agent.includes(:creator, :provider, :executions, agent_skills: :skill))
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
          if @agent.is_concierge?
            return render_error("Cannot delete the concierge agent", status: :unprocessable_content)
          end

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
          # HIER-P2I. #set_agent resolves through `for_account`, which includes
          # the GLOBAL canonicals so a consumer can VIEW one — but executing one
          # is what ruling 8 forbids: a NULL-account principal has no account
          # role to bound it and its tool calls are refused at the seam. Execute
          # the account's clone of it instead (minted on first use); an
          # account-owned agent passes through untouched, and the response
          # serializes the row that actually ran.
          @agent = ::Ai::Agents::AccountPrincipalResolver.acting(
            @agent, account: current_user.account, user: current_user
          )

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
          # Cloning a GLOBAL platform agent yields a provenance-tracked account
          # copy (cloned_from_id + source_snapshot) that can later be rebased
          # against the global origin via update_from_source. This is how a
          # consumer customizes a platform agent — the global stays read-only.
          if @agent.global?
            # A canonical seeded before any provider existed carries none
            # (ai_provider_id is nullable on a GLOBAL row, IMP-6cda93db7f31)
            # while an ACCOUNT row must have one, so the copy cannot simply
            # inherit it. Same resolution as the other two clone seams —
            # Ai::Agents::AccountPrincipalResolver#mint! and
            # Ai::Tools::AgentManagementTool#clone_canonical_agent.
            provider = current_user.account.ai_providers.where(is_active: true).order(:created_at).first ||
                       @agent.provider
            unless provider
              render_error("This platform agent carries no provider and your account has no active " \
                           "provider to run a copy on — add a provider first.",
                           status: :unprocessable_content)
              return
            end

            copy = @agent.clone_to_account(current_user.account, creator: current_user, provider: provider)
            render_success({ agent: serialize_agent_detail(copy) }, status: :created)
            log_audit_event("ai.agents.clone", copy, original_agent_id: @agent.id, from_global: true)
            return
          end

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
          account = current_user&.account || current_account
          return render_error("Agent not found", status: :not_found) unless account

          # for_account = the account's OWN agents + GLOBAL platform agents, so a
          # consumer can view/execute/clone a global agent (mutations are guarded
          # by require_editable_agent!). #using_account makes a GLOBAL agent
          # resolve its model/provider/credential from THIS account's config.
          @agent = ::Ai::Agent.for_account(account.id).find(params[:agent_id] || params[:id])
          @agent.using_account(account)
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        end

        # content_model for GloballyScopedContent (clone / update_from_source).
        def content_model = ::Ai::Agent

        def require_editable_agent!
          require_editable_content!(@agent)
        end

        def set_agent_execution
          execution_id = params[:execution_id] || params[:id]

          if current_user
            @execution = ::Ai::AgentExecution.joins(:agent)
                                             .where(ai_agents: { account_id: current_user.account_id })
                                             .find_by!(execution_id: execution_id)
          elsif current_worker
            @execution = ::Ai::AgentExecution.find_by!(execution_id: execution_id)
          else
            render_unauthorized("Authentication required")
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Execution not found", status: :not_found)
        end

      end
    end
  end
end
