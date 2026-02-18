# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Global conversations controller - manages conversations across all agents
      # Provides cross-agent conversation listing, filtering, and management
      class ConversationsController < ApplicationController
        include AuditLogging
        include ::Ai::ConversationAiGeneration
        include ::Ai::ConversationManagementActions
        include ::Ai::ConversationSerialization

        before_action :set_conversation, only: [ :show, :update, :destroy, :archive, :unarchive, :duplicate, :stats, :pin, :unpin, :plan_response ]
        before_action :set_agent_for_nested, only: [ :active ]
        before_action :validate_permissions

        # =============================================================================
        # GLOBAL CONVERSATION ACTIONS
        # =============================================================================

        # GET /api/v1/ai/conversations
        def index
          conversations = current_user.account.ai_conversations
                                    .includes(:user, :agent, :provider)
                                    .order(last_activity_at: :desc)

          conversations = apply_filters(conversations)
          conversations = apply_pagination(conversations)

          render_success({
            conversations: conversations.map { |c| serialize_conversation(c) },
            pagination: pagination_data(conversations)
          })
        end

        # GET /api/v1/ai/agents/:agent_id/conversations/active
        def active
          conversations = @agent.conversations
                                .where(status: "active")
                                .where(user_id: current_user.id)
                                .order(last_activity_at: :desc)
                                .limit(1)

          render_success(data: conversations.map { |c| serialize_conversation_detail(c) })
        end

        # POST /api/v1/ai/agents/:agent_id/conversations
        def create
          agent = current_user.account.ai_agents.find(params[:agent_id])
          ProviderAvailabilityService.validate_agent_provider!(agent)

          conversation = agent.conversations.build(
            conversation_params.merge(
              conversation_id: SecureRandom.uuid,
              user_id: current_user.id,
              account_id: current_user.account_id,
              ai_provider_id: agent.ai_provider_id,
              status: "active",
              last_activity_at: Time.current
            )
          )

          if conversation.save
            render_success({ conversation: serialize_conversation_detail(conversation) }, status: :created)
            log_audit_event("ai.conversations.create", conversation)
          else
            render_validation_error(conversation.errors)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        rescue ProviderAvailabilityService::ProviderUnavailableError => e
          render_error(e.message, status: :precondition_failed)
        end

        # POST /api/v1/ai/conversations/team
        def create_team
          team = current_user.account.ai_agent_teams.find(params[:team_id])
          service = ::Ai::TeamConversationService.new(account: current_user.account)
          conversation = service.find_or_create_conversation(team)
          render_success({ conversation: serialize_conversation_detail(conversation) })
        rescue ActiveRecord::RecordNotFound
          render_error("Team not found", status: :not_found)
        end

        # GET /api/v1/ai/conversations/:id
        def show
          render_success({ conversation: serialize_conversation_detail(@conversation) })
        end

        # PATCH /api/v1/ai/conversations/:id
        def update
          if @conversation.update(conversation_params)
            render_success({ conversation: serialize_conversation_detail(@conversation) })
            log_audit_event("ai.conversations.update", @conversation)
          else
            render_validation_error(@conversation.errors)
          end
        end

        # DELETE /api/v1/ai/conversations/:id
        def destroy
          @conversation.destroy!
          render_success({ message: "Conversation deleted successfully" })
          log_audit_event("ai.conversations.delete", @conversation)
        rescue ActiveRecord::RecordNotDestroyed => e
          render_error("Failed to delete conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/conversations/:id/archive
        def archive
          @conversation.archive_conversation!
          render_success({ conversation: serialize_conversation(@conversation), message: "Conversation archived successfully" })
          log_audit_event("ai.conversations.archive", @conversation)
        rescue ActiveRecord::RecordInvalid => e
          render_error("Failed to archive conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/conversations/:id/unarchive
        def unarchive
          @conversation.update!(status: "completed")
          render_success({ conversation: serialize_conversation(@conversation), message: "Conversation restored successfully" })
          log_audit_event("ai.conversations.unarchive", @conversation)
        rescue ActiveRecord::RecordInvalid => e
          render_error("Failed to restore conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/conversations/:id/plan_response
        def plan_response
          unless @conversation.team_conversation?
            return render_error("Plan responses are only available for team conversations", status: :unprocessable_content)
          end

          action_type = params[:action_type]
          execution_id = params[:execution_id]

          unless %w[approve request_changes].include?(action_type)
            return render_error("action_type must be 'approve' or 'request_changes'", status: :bad_request)
          end

          return render_error("execution_id is required", status: :bad_request) if execution_id.blank?

          service = ::Ai::TeamConversationService.new(account: current_user.account)
          service.handle_plan_response(
            @conversation,
            action: action_type,
            execution_id: execution_id,
            feedback: params[:feedback],
            current_user_id: current_user.id
          )

          render_success({ message: "Plan #{action_type == 'approve' ? 'approved' : 'changes requested'} successfully" })
          log_audit_event("ai.conversations.plan_response", @conversation, action_type: action_type, execution_id: execution_id)
        rescue ActiveRecord::RecordNotFound => e
          render_error(e.message, status: :not_found)
        rescue ArgumentError => e
          render_error(e.message, status: :unprocessable_content)
        rescue StandardError => e
          Rails.logger.error "[CONVERSATIONS] plan_response error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          render_internal_error("Failed to process plan response", exception: e)
        end

        # POST /api/v1/ai/agents/:agent_id/conversations/:id/send_message
        def send_message
          agent = current_user.account.ai_agents.find(params[:agent_id])
          conversation = agent.conversations.find(params[:id])

          unless conversation.can_send_message?
            return render_error("Conversation is not active", status: :unprocessable_content)
          end

          content = message_params[:content]
          return render_error("Message content cannot be blank", status: :unprocessable_content) if content.blank?

          user_message = conversation.add_user_message(
            content, user: current_user,
            message_type: message_params[:message_type] || "text",
            content_metadata: message_params[:metadata] || {}
          )

          # Concierge routing — process through ConciergeService
          if conversation.agent&.is_concierge?
            concierge = ::Ai::ConciergeService.new(conversation: conversation, user: current_user)
            concierge.process_message(content)
            assistant_msg = conversation.messages.where.not(role: "user").order(created_at: :desc).first
            return render_success({
              user_message: serialize_message(user_message),
              assistant_message: assistant_msg ? serialize_message(assistant_msg) : nil,
              concierge_routed: true,
              conversation: { id: conversation.id, message_count: conversation.reload.message_count }
            })
          end

          # Auto-classify plan approval intent for team conversations
          if conversation.team_conversation?
            service = ::Ai::TeamConversationService.new(account: current_user.account)
            intent = service.classify_user_intent(conversation, content)
            if intent.in?([:approve, :request_changes])
              return render_success({
                user_message: serialize_message(user_message),
                assistant_message: nil,
                plan_action: intent.to_s,
                conversation: { id: conversation.id, message_count: conversation.reload.message_count }
              })
            end

            # Route through coordinator if enabled
            if conversation.agent_team&.coordinator_enabled?
              coordinator = ::Ai::CoordinatorService.new(conversation: conversation, user: current_user)
              coordinator.process_message(content)
              return render_success({
                user_message: serialize_message(user_message),
                assistant_message: nil,
                coordinator_routed: true,
                conversation: { id: conversation.id, message_count: conversation.reload.message_count }
              })
            end
          end

          # Check for active container instance
          bridge = ::Ai::ContainerChatBridgeService.new(account: current_user.account)
          if bridge.has_active_container?(conversation.id)
            bridge_result = bridge.route_message_to_container(conversation_id: conversation.id, message: { content: content, role: "user" })
            if bridge_result[:routed]
              return render_success({
                user_message: serialize_message(user_message), assistant_message: nil,
                container_routed: true, container_execution_id: bridge_result[:container_execution_id],
                conversation: { id: conversation.id, message_count: conversation.reload.message_count }
              })
            end
          end

          messages_for_ai = build_messages_for_ai(conversation, agent)
          assistant_response = generate_ai_response(agent, messages_for_ai)

          if assistant_response[:success]
            assistant_message = conversation.add_assistant_message(
              assistant_response[:content], message_type: "text",
              token_count: assistant_response[:usage]&.dig(:total_tokens) || 0,
              cost_usd: calculate_cost(assistant_response[:usage], agent.provider),
              processing_metadata: { model: assistant_response[:model], finish_reason: assistant_response[:finish_reason], usage: assistant_response[:usage] }
            )

            render_success({
              user_message: serialize_message(user_message), assistant_message: serialize_message(assistant_message),
              conversation: { id: conversation.id, message_count: conversation.reload.message_count, total_tokens: conversation.total_tokens, total_cost: conversation.total_cost&.to_f }
            })
            log_audit_event("ai.conversations.send_message", conversation, user_message_id: user_message.id, assistant_message_id: assistant_message.id)
          else
            render_success({
              user_message: serialize_message(user_message), assistant_message: nil, error: assistant_response[:error],
              conversation: { id: conversation.id, message_count: conversation.reload.message_count }
            }, status: :partial_content)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Agent or conversation not found", status: :not_found)
        rescue ActiveRecord::RecordInvalid => e
          render_error("Failed to create message: #{e.message}", status: :unprocessable_content)
        rescue StandardError => e
          Rails.logger.error "[CONVERSATIONS] send_message error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          render_internal_error("Failed to send message", exception: e)
        end

        # GET /api/v1/ai/agents/:agent_id/conversations/:id/messages
        def messages
          agent = current_user.account.ai_agents.find(params[:agent_id])
          conversation = agent.conversations.includes(messages: :user).find_by(id: params[:id]) ||
                         agent.conversations.includes(messages: :user).find_by!(conversation_id: params[:id])
          msgs = conversation.messages.not_deleted.ordered.page(params[:page] || 1).per(params[:per_page] || 50)

          render_success({
            messages: msgs.map { |m| serialize_message(m) },
            pagination: { current_page: msgs.current_page, per_page: msgs.limit_value, total_pages: msgs.total_pages, total_count: msgs.total_count }
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Agent or conversation not found", status: :not_found)
        end

        # POST /api/v1/ai/conversations/concierge
        def create_concierge
          agent = current_user.account.ai_agents.default_concierge.first
          return render_error("No concierge agent configured", status: :not_found) unless agent

          conversation = agent.conversations.active
            .where(user_id: current_user.id)
            .order(last_activity_at: :desc).first

          unless conversation
            ProviderAvailabilityService.validate_agent_provider!(agent)
            conversation = agent.conversations.create!(
              conversation_id: SecureRandom.uuid,
              user_id: current_user.id,
              account_id: current_user.account_id,
              ai_provider_id: agent.ai_provider_id,
              title: "Chat with #{agent.name}",
              status: "active",
              conversation_type: "agent",
              last_activity_at: Time.current
            )
          end

          render_success({ conversation: serialize_conversation_detail(conversation) })
        rescue ProviderAvailabilityService::ProviderUnavailableError => e
          render_error(e.message, status: :precondition_failed)
        end

        # POST /api/v1/ai/conversations/:id/confirm_action
        def confirm_action
          @conversation = current_user.account.ai_conversations
            .find_by(id: params[:id]) || current_user.account.ai_conversations.find_by!(conversation_id: params[:id])

          unless @conversation.agent&.is_concierge?
            return render_error("This action is only available for concierge conversations", status: :unprocessable_content)
          end

          concierge = ::Ai::ConciergeService.new(conversation: @conversation, user: current_user)
          concierge.handle_confirmed_action(
            params[:action_type],
            params[:action_params]&.to_unsafe_h || params[:action_params]&.permit!&.to_h || {}
          )

          render_success({ confirmed: true })
        rescue ActiveRecord::RecordNotFound
          render_error("Conversation not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error("[CONVERSATIONS] confirm_action error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
          render_internal_error("Failed to execute action", exception: e)
        end

        private

        def set_agent_for_nested
          @agent = current_user.account.ai_agents.find(params[:agent_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        end

        def set_conversation
          @conversation = current_user.account.ai_conversations
                           .includes(:user, :agent, :provider, messages: [:user])
                           .find_by(id: params[:id]) ||
                         current_user.account.ai_conversations
                           .includes(:user, :agent, :provider, messages: [:user])
                           .find_by(conversation_id: params[:id])
          render_error("Conversation not found", status: :not_found) unless @conversation
        end

      end
    end
  end
end
