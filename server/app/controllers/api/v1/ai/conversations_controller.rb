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

        before_action :set_conversation, only: [ :show, :update, :destroy, :archive, :unarchive, :duplicate, :stats, :pin, :unpin ]
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

        # POST /api/v1/ai/conversations/:id/duplicate
        def duplicate
          new_title = params[:title] || "Copy of #{@conversation.title}"
          include_messages = params[:include_messages] == "true" || params[:include_messages] == true

          new_conversation = current_user.account.ai_conversations.build(
            user: current_user, agent: @conversation.agent, provider: @conversation.provider,
            title: new_title, status: "active",
            is_collaborative: @conversation.is_collaborative?, participants: @conversation.participants
          )

          if new_conversation.save
            if include_messages
              @conversation.messages.ordered.each do |message|
                new_conversation.messages.create!(
                  role: message.role, content: message.content, message_type: message.message_type,
                  user: message.user, agent: message.agent, sequence_number: message.sequence_number
                )
              end
            end

            render_success({ conversation: serialize_conversation_detail(new_conversation), message: "Conversation duplicated successfully" }, status: :created)
            log_audit_event("ai.conversations.duplicate", new_conversation, original_conversation_id: @conversation.conversation_id, included_messages: include_messages)
          else
            render_validation_error(new_conversation.errors)
          end
        rescue StandardError => e
          render_error("Failed to duplicate conversation: #{e.message}", status: :unprocessable_content)
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
          conversation = agent.conversations.includes(messages: :user).find(params[:id])
          msgs = conversation.messages.not_deleted.ordered.page(params[:page] || 1).per(params[:per_page] || 50)

          render_success({
            messages: msgs.map { |m| serialize_message(m) },
            pagination: { current_page: msgs.current_page, per_page: msgs.limit_value, total_pages: msgs.total_pages, total_count: msgs.total_count }
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Agent or conversation not found", status: :not_found)
        end

        # GET /api/v1/ai/conversations/:id/stats
        def stats
          msgs = @conversation.messages.not_deleted

          response_times = []
          msgs.ordered.each_cons(2) do |msg1, msg2|
            response_times << (msg2.created_at - msg1.created_at) if msg1.role == "user" && msg2.role == "assistant"
          end

          first_message = msgs.ordered.first
          last_message = msgs.ordered.last
          duration = (first_message && last_message && first_message != last_message) ? (last_message.created_at - first_message.created_at) : 0

          render_success({ stats: {
            message_count: @conversation.message_count, token_usage: @conversation.total_tokens,
            avg_response_time: (response_times.any? ? response_times.sum / response_times.size : 0).round(2),
            duration: duration.round(2), total_cost: @conversation.total_cost&.to_f || 0.0,
            user_message_count: msgs.user_messages.count, assistant_message_count: msgs.assistant_messages.count,
            system_message_count: msgs.system_messages.count,
            first_message_at: first_message&.created_at&.iso8601, last_message_at: last_message&.created_at&.iso8601,
            status: @conversation.status, is_collaborative: @conversation.is_collaborative?, participant_count: @conversation.participants.size
          } })
        rescue StandardError => e
          render_internal_error("Failed to retrieve conversation stats", exception: e)
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

        def validate_permissions
          case action_name
          when "index", "show", "stats", "messages", "active", "search"
            require_permission("ai.conversations.read")
          when "create", "duplicate", "send_message"
            require_permission("ai.conversations.create")
          when "update", "archive", "unarchive", "pin", "unpin", "bulk"
            require_permission("ai.conversations.update")
          when "destroy"
            require_permission("ai.conversations.delete")
          when "worker_complete", "worker_error"
            return if current_worker || current_service
            require_permission("ai.conversations.update")
          end
        end

        def conversation_params
          params.require(:conversation).permit(:title, :status, :is_collaborative, participants: [], metadata: {})
        end

        def message_params
          params.require(:message).permit(:content, :message_type, metadata: {})
        end

        def apply_filters(conversations)
          conversations = conversations.where(status: params[:status]) if params[:status].present?
          conversations = conversations.where(ai_agent_id: params[:agent_id]) if params[:agent_id].present?
          conversations = conversations.where(user_id: params[:user_id]) if params[:user_id].present?
          conversations = conversations.pinned if params[:pinned] == "true"

          if params[:tags].present?
            tag_list = params[:tags].is_a?(Array) ? params[:tags] : params[:tags].split(",").map(&:strip)
            conversations = conversations.tagged_with_any(tag_list)
          end

          if params[:search].present?
            conversations = conversations.where("ai_conversations.title ILIKE ?", "%#{params[:search]}%")
          end

          case params[:sort_by]
          when "pinned" then conversations = conversations.reorder(nil).pinned_first
          when "last_activity" then conversations = conversations.reorder(last_activity_at: :desc)
          when "created" then conversations = conversations.reorder(created_at: :desc)
          when "message_count" then conversations = conversations.reorder(message_count: :desc)
          end

          conversations
        end

        def apply_pagination(collection)
          collection.page(params[:page]&.to_i || 1).per([ params[:per_page]&.to_i || 25, 100 ].min)
        end

        def pagination_data(collection)
          { current_page: collection.current_page, per_page: collection.limit_value, total_pages: collection.total_pages, total_count: collection.total_count }
        end

        def serialize_conversation(conversation)
          {
            id: conversation.id, conversation_id: conversation.conversation_id,
            title: conversation.title || "Conversation with #{conversation.provider.name}",
            status: conversation.status, message_count: conversation.message_count,
            total_tokens: conversation.total_tokens, total_cost: conversation.total_cost&.to_f,
            is_collaborative: conversation.is_collaborative?, participant_count: conversation.participants.size,
            pinned: conversation.pinned?, pinned_at: conversation.pinned_at&.iso8601, tags: conversation.tags,
            created_at: conversation.created_at.iso8601, last_activity_at: conversation.last_activity_at&.iso8601,
            ai_agent: conversation.agent ? { id: conversation.agent.id, name: conversation.agent.name, agent_type: conversation.agent.agent_type } : nil,
            provider: { id: conversation.provider.id, name: conversation.provider.name, provider_type: conversation.provider.provider_type },
            user: { id: conversation.user.id, name: conversation.user.full_name, email: conversation.user.email }
          }
        end

        def serialize_conversation_detail(conversation)
          serialize_conversation(conversation).merge(
            summary: conversation.summary, websocket_channel: conversation.websocket_channel,
            websocket_session_id: conversation.websocket_session_id,
            participants: conversation.is_collaborative? ? (conversation.participants || []) : [],
            recent_messages: conversation.messages.not_deleted.recent.limit(10).map { |m| serialize_message(m) },
            metadata: { can_send_message: conversation.can_send_message?, active_session: conversation.websocket_session_id.present? }
          )
        end

        def serialize_message(message)
          message.message_data
        end
      end
    end
  end
end
