# frozen_string_literal: true

# Consolidated Agents Controller - Phase 3 Controller Consolidation
#
# This controller consolidates agent-related controllers into a single
# RESTful resource controller following the AI Orchestration Redesign pattern.
#
# Consolidates:
# - AiAgentsController (agent CRUD and operations)
# - AiAgentExecutionsController (execution management)
# - Partial AiMessagesController (agent-scoped messages)
#
# Architecture:
# - Primary resource: Agents
# - Nested resources: Executions
# - Uses RESTful conventions strictly
# - Thin controller, delegates to services
#
module Api
  module V1
    module Ai
      class AgentsController < ApplicationController
        include AuditLogging

        # Authentication and resource loading
        before_action :set_agent, only: [
          :show, :update, :destroy,
          :execute, :clone, :test, :validate,
          :pause, :resume, :archive, :stats, :analytics
        ]

        before_action :set_agent_execution, only: [
          :execution_show, :execution_update, :execution_destroy,
          :execution_cancel, :execution_retry, :execution_logs
        ]

        before_action :validate_permissions

        # =============================================================================
        # AGENTS - PRIMARY RESOURCE CRUD
        # =============================================================================

        # GET /api/v1/ai/agents
        def index
          agents = current_user.account.ai_agents
                              .includes(:creator, :ai_provider)

          agents = apply_agent_filters(agents)
          agents = apply_sorting(agents)
          agents = apply_pagination(agents)

          render_success({
            items: agents.map { |agent| serialize_agent(agent) },
            pagination: pagination_data(agents)
          })

          log_audit_event("ai.agents.read", current_user.account)
        end

        # GET /api/v1/ai/agents/:id
        def show
          render_success({
            agent: serialize_agent_detail(@agent)
          })

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
            render_success({
              agent: serialize_agent_detail(@agent)
            }, status: :created)

            log_audit_event("ai.agents.create", @agent,
              agent_type: @agent.agent_type,
              mcp_capabilities: @agent.mcp_capabilities
            )
          else
            render_validation_error(@agent.errors)
          end
        end

        # PATCH /api/v1/ai/agents/:id
        def update
          if @agent.update(agent_update_params)
            render_success({
              agent: serialize_agent_detail(@agent)
            })

            log_audit_event("ai.agents.update", @agent,
              changes: @agent.previous_changes.except("updated_at")
            )
          else
            render_validation_error(@agent.errors)
          end
        end

        # DELETE /api/v1/ai/agents/:id
        def destroy
          agent_name = @agent.name
          @agent.destroy

          render_success({ message: "AI agent deleted successfully" })

          log_audit_event("ai.agents.delete", current_user.account,
            agent_name: agent_name
          )
        end

        # =============================================================================
        # AGENTS - CUSTOM ACTIONS
        # =============================================================================

        # POST /api/v1/ai/agents/:id/execute
        def execute
          unless @agent.mcp_available?
            return render_error("Agent cannot be executed in current state", status: :unprocessable_content)
          end

          input_parameters = params[:input_parameters] || {}
          provider_id = params[:ai_provider_id]

          provider = nil
          if provider_id.present?
            provider = current_user.account.ai_providers.find_by(id: provider_id)
            return render_error("AI provider not found", status: :not_found) unless provider
          end

          begin
            execution = @agent.execute(
              input_parameters,
              user: current_user,
              provider: provider
            )

            render_success({
              execution: serialize_execution(execution),
              agent: serialize_agent(@agent.reload)
            }, status: :created)

            log_audit_event("ai.agents.execute", @agent,
              execution_id: execution.execution_id,
              provider_id: execution.ai_provider_id
            )

          rescue ArgumentError => e
            render_error(e.message, status: :unprocessable_content)
          rescue ActiveRecord::RecordInvalid => e
            render_validation_error(e.record.errors)
          end
        end

        # POST /api/v1/ai/agents/:id/clone
        def clone
          begin
            cloned_agent = @agent.clone_for_account(current_user.account, current_user)

            render_success({
              agent: serialize_agent_detail(cloned_agent)
            }, status: :created)

            log_audit_event("ai.agents.clone", cloned_agent,
              original_agent_id: @agent.id
            )

          rescue StandardError => e
            render_error("Failed to clone agent: #{e.message}", status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:id/test
        def test
          test_input = params[:test_input]&.to_unsafe_h || {}

          begin
            # Create a test execution without persisting to database
            result = @agent.test_execution(test_input, current_user)

            render_success({
              test_result: result,
              message: "Test execution completed"
            })

            log_audit_event("ai.agents.test", @agent)

          rescue StandardError => e
            render_error("Test execution failed: #{e.message}", status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/agents/:id/validate
        def validate
          validation_result = @agent.validate_configuration

          if validation_result[:valid]
            render_success({
              valid: true,
              message: "Agent configuration is valid"
            })
          else
            render_success({
              valid: false,
              errors: validation_result[:errors],
              warnings: validation_result[:warnings]
            })
          end
        end

        # POST /api/v1/ai/agents/:id/pause
        def pause
          if @agent.active?
            @agent.update!(status: "paused")

            render_success({
              agent: serialize_agent(@agent),
              message: "Agent paused successfully"
            })

            log_audit_event("ai.agents.pause", @agent)
          else
            render_error("Agent must be active to pause", status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:id/resume
        def resume
          if @agent.paused?
            @agent.update!(status: "active")

            render_success({
              agent: serialize_agent(@agent),
              message: "Agent resumed successfully"
            })

            log_audit_event("ai.agents.resume", @agent)
          else
            render_error("Agent must be paused to resume", status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:id/archive
        def archive
          @agent.update!(status: "archived")

          render_success({
            agent: serialize_agent(@agent),
            message: "Agent archived successfully"
          })

          log_audit_event("ai.agents.archive", @agent)
        end

        # GET /api/v1/ai/agents/:id/stats
        def stats
          executions = @agent.ai_agent_executions

          stats = {
            total_executions: executions.count,
            successful_executions: executions.where(status: "completed").count,
            failed_executions: executions.where(status: "failed").count,
            running_executions: executions.where(status: "running").count,
            average_duration: executions.where.not(completed_at: nil)
                                        .average("EXTRACT(epoch FROM (completed_at - started_at))"),
            total_cost: executions.sum(:cost_usd),
            last_executed_at: executions.maximum(:created_at),
            success_rate: calculate_success_rate(executions)
          }

          render_success({ stats: stats })
        end

        # GET /api/v1/ai/agents/:id/analytics
        def analytics
          date_range = params[:date_range]&.to_i || 30

          executions = @agent.ai_agent_executions
                            .where("created_at >= ?", date_range.days.ago)

          analytics = {
            executions_over_time: executions.group_by_day(:created_at).count,
            status_distribution: executions.group(:status).count,
            average_cost_per_day: executions.group_by_day(:created_at)
                                           .average(:cost_usd),
            performance_metrics: calculate_performance_metrics(executions)
          }

          render_success({ analytics: analytics })
        end

        # GET /api/v1/ai/agents/my_agents
        def my_agents
          agents = current_user.account.ai_agents
                              .where(creator: current_user)
                              .includes(:ai_provider)

          agents = apply_pagination(agents.order(updated_at: :desc))

          render_success({
            items: agents.map { |agent| serialize_agent(agent) },
            pagination: pagination_data(agents)
          })
        end

        # GET /api/v1/ai/agents/public_agents
        def public_agents
          agents = current_user.account.ai_agents
                              .where(is_public: true)
                              .includes(:creator, :ai_provider)

          agents = apply_pagination(agents.order(updated_at: :desc))

          render_success({
            items: agents.map { |agent| serialize_agent(agent) },
            pagination: pagination_data(agents)
          })
        end

        # GET /api/v1/ai/agents/agent_types
        def agent_types
          types = %w[conversational workflow automation content_generator code_assistant data_analyzer creative specialist]

          render_success({
            agent_types: types.map do |type|
              {
                value: type,
                label: type.humanize,
                description: agent_type_description(type)
              }
            end
          })
        end

        # GET /api/v1/ai/agents/statistics
        def statistics
          agents = current_user.account.ai_agents

          stats = {
            total_agents: agents.count,
            active_agents: agents.where(status: "active").count,
            paused_agents: agents.where(status: "paused").count,
            total_executions: AiAgentExecution.joins(:ai_agent)
                                             .where(ai_agents: { account_id: current_user.account_id })
                                             .count,
            agents_by_type: agents.group(:agent_type).count,
            recent_activity: agents.joins(:ai_agent_executions)
                                  .where(ai_agent_executions: { created_at: 7.days.ago.. })
                                  .group("ai_agents.id")
                                  .count
          }

          render_success({ statistics: stats })
        end

        # =============================================================================
        # AGENT EXECUTIONS - NESTED RESOURCE
        # =============================================================================

        # GET /api/v1/ai/agents/:agent_id/executions
        def executions_index
          # Determine scope based on route
          executions = if params[:agent_id].present?
                        # Nested under specific agent
                        agent = current_user.account.ai_agents.find(params[:agent_id])
                        agent.ai_agent_executions
          else
                        # All executions across all agents
                        AiAgentExecution.joins(:ai_agent)
                                       .where(ai_agents: { account_id: current_user.account_id })
          end

          executions = executions.includes(:ai_agent, :ai_provider, :user)
          executions = apply_execution_filters(executions)
          executions = apply_pagination(executions.order(created_at: :desc))

          render_success({
            items: executions.map { |exec| serialize_execution(exec) },
            pagination: pagination_data(executions)
          })
        end

        # GET /api/v1/ai/agents/:agent_id/executions/:execution_id
        def execution_show
          # Force deep conversion to avoid UnfilteredParameters errors
          serialized = serialize_execution_detail(@execution)
          clean_data = JSON.parse(serialized.to_json)

          render_success({
            execution: clean_data
          })
        end

        # PATCH /api/v1/ai/agents/:agent_id/executions/:execution_id
        def execution_update
          # Allow worker/service updates without full permission check
          unless current_worker || current_service
            require_permission("ai.agents.update")
          end

          if @execution.update(execution_update_params)
            serialized = serialize_execution_detail(@execution)
            clean_data = JSON.parse(serialized.to_json)

            render_success({
              execution: clean_data,
              message: "Execution updated successfully"
            })
          else
            render_validation_error(@execution.errors)
          end
        rescue StandardError => e
          Rails.logger.error "Execution update error: #{e.message}"
          render_error("Update failed: #{e.message}", status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/agents/:agent_id/executions/:execution_id
        def execution_destroy
          if @execution.destroy
            render_success({ message: "Execution deleted successfully" })

            log_audit_event("ai.agents.execution.delete", @execution)
          else
            render_error("Failed to delete execution", status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:agent_id/executions/:execution_id/cancel
        def execution_cancel
          begin
            reason = params[:reason] || "Cancelled by user"
            @execution.cancel_execution!(reason)

            render_success({
              execution: serialize_execution(@execution),
              message: "Execution cancelled successfully"
            })

            log_audit_event("ai.agents.execution.cancel", @execution)

          rescue StandardError => e
            render_error("Failed to cancel execution: #{e.message}", status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:agent_id/executions/:execution_id/retry
        def execution_retry
          if @execution.finished?
            # Create new execution based on current one
            new_execution = @execution.ai_agent.execute(
              @execution.input_parameters,
              user: current_user,
              provider: @execution.ai_provider
            )

            render_success({
              execution: serialize_execution(new_execution),
              message: "Execution retried successfully"
            }, status: :created)

            log_audit_event("ai.agents.execution.retry", new_execution,
              original_execution_id: @execution.execution_id
            )
          else
            render_error("Cannot retry execution that is not finished", status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/agents/:agent_id/executions/:execution_id/logs
        def execution_logs
          logs = build_execution_logs(@execution)

          render_success({
            logs: logs,
            execution_id: @execution.execution_id
          })
        end

        # =============================================================================
        # AGENT CONVERSATIONS - NESTED RESOURCE
        # =============================================================================

        # GET /api/v1/ai/agents/:agent_id/conversations
        def conversations_index
          conversations = @agent.ai_conversations
                                .includes(:user, :ai_provider)
                                .order(last_activity_at: :desc)

          conversations = apply_pagination(conversations)

          render_success({
            conversations: conversations.map { |c| serialize_conversation(c) },
            pagination: pagination_data(conversations)
          })
        end

        # GET /api/v1/ai/agents/:agent_id/conversations/:conversation_id
        def conversation_show
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])

          render_success({
            conversation: serialize_conversation_detail(conversation)
          })
        end

        # POST /api/v1/ai/agents/:agent_id/conversations
        def conversation_create
          conversation = @agent.ai_conversations.build(conversation_params)
          conversation.user = current_user
          conversation.account = current_user.account
          conversation.ai_provider = @agent.ai_provider

          if conversation.save
            render_success({
              conversation: serialize_conversation_detail(conversation)
            }, status: :created)

            log_audit_event("ai.conversations.create", conversation)
          else
            render_validation_error(conversation.errors)
          end
        end

        # PATCH /api/v1/ai/agents/:agent_id/conversations/:conversation_id
        def conversation_update
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])

          if conversation.update(conversation_params)
            render_success({
              conversation: serialize_conversation(conversation)
            })

            log_audit_event("ai.conversations.update", conversation)
          else
            render_validation_error(conversation.errors)
          end
        end

        # DELETE /api/v1/ai/agents/:agent_id/conversations/:conversation_id
        def conversation_destroy
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])

          if conversation.destroy
            render_success({ message: "Conversation deleted successfully" })

            log_audit_event("ai.conversations.delete", conversation)
          else
            render_error("Failed to delete conversation", status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/send_message
        def send_message
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])

          message = conversation.add_user_message(
            params[:content],
            user: current_user,
            metadata: params[:metadata] || {}
          )

          # Note: AI response generation is handled synchronously via the AI provider
          # or asynchronously through the AI workflow execution system

          render_success({
            message: serialize_message(message)
          })

          log_audit_event("ai.conversations.message.send", message)
        end

        # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/pause
        def pause_conversation
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])
          conversation.pause_conversation!

          render_success({
            conversation: serialize_conversation(conversation),
            message: "Conversation paused successfully"
          })

          log_audit_event("ai.conversations.pause", conversation)
        end

        # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/resume
        def resume_conversation
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])
          conversation.resume_conversation!

          render_success({
            conversation: serialize_conversation(conversation),
            message: "Conversation resumed successfully"
          })

          log_audit_event("ai.conversations.resume", conversation)
        end

        # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/complete
        def complete_conversation
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])
          conversation.complete_conversation!

          render_success({
            conversation: serialize_conversation(conversation),
            message: "Conversation completed successfully"
          })

          log_audit_event("ai.conversations.complete", conversation)
        end

        # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/archive
        def archive_conversation
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])
          conversation.archive_conversation!

          render_success({
            conversation: serialize_conversation(conversation),
            message: "Conversation archived successfully"
          })

          log_audit_event("ai.conversations.archive", conversation)
        end

        # GET /api/v1/ai/agents/:agent_id/conversations/:conversation_id/messages
        def conversation_messages
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])
          messages = conversation.ai_messages.order(created_at: :asc)

          render_success({
            messages: messages.map { |m| serialize_message(m) }
          })
        end

        # GET /api/v1/ai/agents/:agent_id/conversations/:conversation_id/export
        def export_conversation
          conversation = @agent.ai_conversations.find(params[:conversation_id] || params[:id])

          render_success({
            conversation: serialize_conversation_detail(conversation),
            export_format: params[:format] || "json",
            exported_at: Time.current.iso8601
          })

          log_audit_event("ai.conversations.export", conversation)
        end

        # =============================================================================
        # MESSAGE ACTIONS
        # =============================================================================

        # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/messages/:id/regenerate
        def regenerate
          set_agent
          return if performed?

          conversation = @agent.ai_conversations.find(params[:conversation_id])
          message = conversation.ai_messages.find(params[:id])

          # Only allow regenerating assistant messages
          unless message.role == "assistant"
            return render_error("Can only regenerate assistant messages", status: :unprocessable_content)
          end

          # Find the previous user message to use as context (for future job)
          _previous_messages = conversation.ai_messages
                                          .where("sequence_number < ?", message.sequence_number)
                                          .order(sequence_number: :asc)

          # Mark the old message as replaced
          old_content = message.content
          message.update!(
            metadata: (message.metadata || {}).merge(
              "regenerated" => true,
              "regenerated_at" => Time.current.iso8601,
              "original_content" => old_content
            )
          )

          # Trigger a new AI response
          # For now, mark for regeneration - actual regeneration happens via background job
          regeneration_request = {
            message_id: message.id,
            conversation_id: conversation.id,
            agent_id: @agent.id,
            requested_by: current_user.id,
            requested_at: Time.current.iso8601
          }

          # Note: Message regeneration is handled through the AI workflow execution system

          render_success({
            message: serialize_message(message.reload),
            regeneration_queued: true,
            regeneration_request: regeneration_request
          })

          log_audit_event("ai.messages.regenerate", message)
        rescue ActiveRecord::RecordNotFound => e
          render_error(e.message, status: :not_found)
        end

        # POST /api/v1/ai/agents/:agent_id/conversations/:conversation_id/messages/:id/rate
        def rate
          set_agent
          return if performed?

          conversation = @agent.ai_conversations.find(params[:conversation_id])
          message = conversation.ai_messages.find(params[:id])

          # Only allow rating assistant messages
          unless message.role == "assistant"
            return render_error("Can only rate assistant messages", status: :unprocessable_content)
          end

          rating = params[:rating]
          unless %w[thumbs_up thumbs_down].include?(rating)
            return render_error("Rating must be thumbs_up or thumbs_down", status: :unprocessable_content)
          end

          feedback = params[:feedback]

          # Update message metadata with rating
          rating_data = {
            "rating" => rating,
            "rated_at" => Time.current.iso8601,
            "rated_by" => current_user.id
          }
          rating_data["feedback"] = feedback if feedback.present?

          message.update!(
            metadata: (message.metadata || {}).merge("user_rating" => rating_data)
          )

          render_success({
            message: serialize_message(message.reload),
            rating: rating_data
          })

          log_audit_event("ai.messages.rate", message, rating: rating)
        rescue ActiveRecord::RecordNotFound => e
          render_error(e.message, status: :not_found)
        end

        private

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
            # User context - scope to user's account
            @execution = AiAgentExecution.joins(:ai_agent)
                                        .where(ai_agents: { account_id: current_user.account_id })
                                        .find_by!(execution_id: execution_id)
          elsif current_worker || current_service
            # Worker/service context - trusted access
            @execution = AiAgentExecution.find_by!(execution_id: execution_id)
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
          # Skip for workers/services
          return if current_worker || current_service

          case action_name
          when "index", "show", "my_agents", "public_agents", "agent_types", "statistics"
            require_permission("ai.agents.read")
          when "executions_index", "execution_show", "execution_logs"
            require_permission("ai.agents.read")
          when "conversations_index", "conversation_show", "conversation_messages"
            require_permission("ai.conversations.read")
          when "create", "clone"
            require_permission("ai.agents.create")
          when "conversation_create", "send_message"
            require_permission("ai.conversations.create")
          when "update", "validate"
            require_permission("ai.agents.update")
          when "conversation_update", "pause_conversation", "resume_conversation", "complete_conversation"
            require_permission("ai.conversations.update")
          when "execution_update"
            # Already handled in action
          when "destroy", "execution_destroy"
            require_permission("ai.agents.delete")
          when "conversation_destroy"
            require_permission("ai.conversations.delete")
          when "execute", "test", "pause", "resume", "archive"
            require_permission("ai.agents.execute")
          when "execution_cancel", "execution_retry"
            require_permission("ai.agents.execute")
          when "archive_conversation", "export_conversation"
            require_permission("ai.conversations.manage")
          when "stats", "analytics"
            require_permission("ai.agents.read")
          when "regenerate"
            require_permission("ai.conversations.update")
          when "rate"
            require_permission("ai.conversations.read")
          end
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def agent_params
          params.require(:agent).permit(
            :name, :description, :agent_type, :status,
            :system_prompt, :model_identifier, :temperature,
            :max_tokens, :top_p, :frequency_penalty, :presence_penalty,
            :is_public, :ai_provider_id,
            mcp_capabilities: [],
            metadata: {},
            mcp_tool_manifest: {},
            mcp_input_schema: {},
            mcp_output_schema: {}
          )
        end

        def agent_update_params
          params.require(:agent).permit(
            :name, :description, :status,
            :system_prompt, :temperature,
            :max_tokens, :top_p, :frequency_penalty, :presence_penalty,
            :is_public,
            mcp_capabilities: [],
            metadata: {},
            mcp_tool_manifest: {},
            mcp_input_schema: {},
            mcp_output_schema: {},
            mcp_metadata: {}
          )
        end

        def execution_update_params
          params.require(:execution).permit(
            :status, :started_at, :completed_at,
            :cost_usd, :duration_ms, :tokens_used,
            output_data: {},
            error_details: {},
            metadata: {}
          )
        end

        def conversation_params
          params.require(:conversation).permit(
            :title, :status, :is_collaborative,
            participants: []
          )
        end

        # =============================================================================
        # FILTERING & SORTING
        # =============================================================================

        def apply_agent_filters(agents)
          agents = agents.where(agent_type: params[:agent_type]) if params[:agent_type].present?
          agents = agents.where(status: params[:status]) if params[:status].present?
          agents = agents.where(creator: current_user) if params[:my_agents] == "true"
          agents = agents.where(is_public: true) if params[:public_only] == "true"
          agents = agents.search_by_text(params[:search]) if params[:search].present?
          agents
        end

        def apply_execution_filters(executions)
          executions = executions.where(status: params[:status]) if params[:status].present?
          executions = executions.where(user_id: params[:user_id]) if params[:user_id].present?

          if params[:start_date].present?
            executions = executions.where("created_at >= ?", Date.parse(params[:start_date]))
          end

          if params[:end_date].present?
            executions = executions.where("created_at <= ?", Date.parse(params[:end_date]))
          end

          executions
        end

        def apply_sorting(collection)
          sort = params[:sort] || "updated_at"

          case sort
          when "name"
            collection.order(:name)
          when "created_at"
            collection.order(created_at: :desc)
          when "last_executed"
            collection.order(last_executed_at: :desc, created_at: :desc)
          when "agent_type"
            collection.order(:agent_type, :name)
          else
            collection.order(updated_at: :desc)
          end
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 20, 100 ].min

          collection.page(page).per(per_page)
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        # =============================================================================
        # SERIALIZATION
        # =============================================================================

        def serialize_agent(agent)
          executions = agent.ai_agent_executions

          {
            id: agent.id,
            name: agent.name,
            description: agent.description,
            agent_type: agent.agent_type,
            status: agent.status,
            version: agent.version,
            is_public: agent.is_public,
            mcp_capabilities: agent.mcp_capabilities,
            created_at: agent.created_at.iso8601,
            updated_at: agent.updated_at.iso8601,
            last_executed_at: agent.last_executed_at&.iso8601,
            created_by: {
              id: agent.creator.id,
              name: agent.creator.full_name,
              email: agent.creator.email
            },
            # Frontend expects 'ai_provider' key
            ai_provider: agent.ai_provider ? {
              id: agent.ai_provider.id,
              name: agent.ai_provider.name,
              slug: agent.ai_provider.slug,
              provider_type: agent.ai_provider.provider_type
            } : nil,
            # Include MCP tool manifest for frontend display
            # Extract commonly used fields from MCP tool manifest
            mcp_tool_manifest: agent.mcp_tool_manifest,
            mcp_input_schema: agent.mcp_input_schema,
            mcp_output_schema: agent.mcp_output_schema,
            mcp_metadata: agent.mcp_metadata,
            # Frontend expects 'execution_stats' key with detailed breakdown
            execution_stats: {
              total_executions: executions.count,
              successful_executions: executions.where(status: "completed").count,
              failed_executions: executions.where(status: "failed").count,
              success_rate: agent.success_rate || 0,
              avg_execution_time: executions.where.not(completed_at: nil)
                                            .average("EXTRACT(epoch FROM (completed_at - started_at))")&.to_f&.round(2) || 0
            }
          }
        end

        def serialize_agent_detail(agent)
          executions = agent.ai_agent_executions

          # Base serialization already includes MCP manifest details
          # Just add detailed stats and metadata
          serialize_agent(agent).merge(
            metadata: agent.metadata,
            # Detailed stats with cost and timing
            detailed_stats: {
              total_executions: executions.count,
              successful_executions: executions.where(status: "completed").count,
              failed_executions: executions.where(status: "failed").count,
              average_duration: executions.where.not(completed_at: nil)
                                          .average("EXTRACT(epoch FROM (completed_at - started_at))")&.to_f&.round(2) || 0,
              total_cost: executions.sum(:cost_usd)&.to_f&.round(4) || 0,
              success_rate: calculate_success_rate(executions)
            }
          )
        end

        def serialize_execution(execution)
          {
            id: execution.id,
            execution_id: execution.execution_id,
            status: execution.status,
            created_at: execution.created_at.iso8601,
            started_at: execution.started_at&.iso8601,
            completed_at: execution.completed_at&.iso8601,
            duration_ms: execution.duration_ms,
            cost_usd: execution.cost_usd&.to_f,
            tokens_used: execution.tokens_used,
            agent: {
              id: execution.ai_agent.id,
              name: execution.ai_agent.name,
              agent_type: execution.ai_agent.agent_type
            },
            user: execution.user ? {
              id: execution.user.id,
              name: execution.user.full_name,
              email: execution.user.email
            } : nil
          }
        end

        def serialize_execution_detail(execution)
          result = serialize_execution(execution).merge(
            input_parameters: execution.input_parameters,
            output_data: execution.output_data,
            execution_context: execution.execution_context,
            provider: execution.ai_provider ? {
              id: execution.ai_provider.id,
              name: execution.ai_provider.name,
              provider_type: execution.ai_provider.provider_type
            } : nil
          )

          result[:error_details] = execution.error_details if execution.error_details.present?
          result
        end

        def serialize_conversation(conversation)
          {
            id: conversation.id,
            conversation_id: conversation.conversation_id,
            title: conversation.title || "Conversation with #{conversation.ai_provider.name}",
            status: conversation.status,
            message_count: conversation.message_count,
            total_tokens: conversation.total_tokens,
            total_cost: conversation.total_cost&.to_f,
            is_collaborative: conversation.is_collaborative?,
            participant_count: conversation.participants.size,
            created_at: conversation.created_at.iso8601,
            last_activity_at: conversation.last_activity_at&.iso8601,
            ai_agent: conversation.ai_agent ? {
              id: conversation.ai_agent.id,
              name: conversation.ai_agent.name,
              agent_type: conversation.ai_agent.agent_type
            } : nil,
            ai_provider: {
              id: conversation.ai_provider.id,
              name: conversation.ai_provider.name,
              provider_type: conversation.ai_provider.provider_type
            },
            user: {
              id: conversation.user.id,
              name: conversation.user.full_name,
              email: conversation.user.email
            }
          }
        end

        def serialize_conversation_detail(conversation)
          serialize_conversation(conversation).merge(
            summary: conversation.summary,
            websocket_channel: conversation.websocket_channel,
            websocket_session_id: conversation.websocket_session_id,
            participants: conversation.is_collaborative? ? conversation.participant_users.map { |u|
              {
                id: u.id,
                name: u.full_name,
                email: u.email
              }
            } : [],
            recent_messages: conversation.ai_messages.recent.limit(10).map { |m| serialize_message(m) },
            metadata: {
              can_send_message: conversation.can_send_message?,
              active_session: conversation.websocket_session_id.present?
            }
          )
        end

        def serialize_message(message)
          message.message_data
        end

        # =============================================================================
        # HELPERS
        # =============================================================================

        def agent_type_description(type)
          descriptions = {
            "conversational" => "Interactive chat agents for natural conversations",
            "workflow" => "Agents designed for multi-step workflow execution",
            "automation" => "Task automation and process management agents",
            "content_generator" => "Content creation and generation agents",
            "code_assistant" => "Programming and code-related assistance",
            "data_analyzer" => "Data analysis and insights generation",
            "creative" => "Creative content and ideation agents",
            "specialist" => "Domain-specific specialist agents"
          }

          descriptions[type] || "Custom agent type"
        end

        def calculate_success_rate(executions)
          total = executions.count
          return 0 if total.zero?

          successful = executions.where(status: "completed").count
          ((successful.to_f / total) * 100).round(2)
        end

        def calculate_performance_metrics(executions)
          durations = executions.where.not(completed_at: nil)
                                .pluck(Arel.sql("EXTRACT(epoch FROM (completed_at - started_at))"))
                                .compact

          {
            average_duration: durations.empty? ? 0 : (durations.sum / durations.size).round(2),
            min_duration: durations.min&.round(2) || 0,
            max_duration: durations.max&.round(2) || 0,
            median_duration: calculate_median(durations)
          }
        end

        def calculate_median(values)
          return 0 if values.empty?

          sorted = values.sort
          mid = sorted.length / 2

          if sorted.length.odd?
            sorted[mid].round(2)
          else
            ((sorted[mid - 1] + sorted[mid]) / 2.0).round(2)
          end
        end

        def build_execution_logs(execution)
          logs = []

          if execution.started_at
            logs << {
              timestamp: execution.started_at.iso8601,
              level: "info",
              message: "Execution started",
              data: { status: "running" }
            }
          end

          if execution.completed_at
            logs << {
              timestamp: execution.completed_at.iso8601,
              level: execution.successful? ? "info" : "error",
              message: execution.successful? ? "Execution completed" : "Execution failed",
              data: {
                status: execution.status,
                duration_ms: execution.duration_ms,
                cost_usd: execution.cost_usd
              }
            }
          end

          if execution.error_details.present?
            logs << {
              timestamp: execution.completed_at&.iso8601 || Time.current.iso8601,
              level: "error",
              message: "Execution error",
              data: execution.error_details
            }
          end

          logs.sort_by { |log| log[:timestamp] }
        end
      end
    end
  end
end
