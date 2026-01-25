# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Global conversations controller - manages conversations across all agents
      # Provides cross-agent conversation listing, filtering, and management
      class ConversationsController < ApplicationController
        include AuditLogging

        before_action :set_conversation, only: [ :show, :update, :destroy, :archive, :unarchive, :duplicate, :stats ]
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

        # POST /api/v1/ai/agents/:agent_id/conversations
        def create
          agent = current_user.account.ai_agents.find(params[:agent_id])

          # Validate provider availability before creating conversation
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
            render_success({
              conversation: serialize_conversation_detail(conversation)
            }, status: :created)

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
          render_success({
            conversation: serialize_conversation_detail(@conversation)
          })
        end

        # PATCH /api/v1/ai/conversations/:id
        def update
          if @conversation.update(conversation_params)
            render_success({
              conversation: serialize_conversation_detail(@conversation)
            })

            log_audit_event("ai.conversations.update", @conversation)
          else
            render_validation_error(@conversation.errors)
          end
        end

        # DELETE /api/v1/ai/conversations/:id
        def destroy
          @conversation.destroy!

          render_success({
            message: "Conversation deleted successfully"
          })

          log_audit_event("ai.conversations.delete", @conversation)
        rescue ActiveRecord::RecordNotDestroyed => e
          render_error("Failed to delete conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/conversations/:id/archive
        def archive
          @conversation.archive_conversation!

          render_success({
            conversation: serialize_conversation(@conversation),
            message: "Conversation archived successfully"
          })

          log_audit_event("ai.conversations.archive", @conversation)
        rescue ActiveRecord::RecordInvalid => e
          render_error("Failed to archive conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/conversations/:id/unarchive
        def unarchive
          @conversation.update!(status: "completed")

          render_success({
            conversation: serialize_conversation(@conversation),
            message: "Conversation restored successfully"
          })

          log_audit_event("ai.conversations.unarchive", @conversation)
        rescue ActiveRecord::RecordInvalid => e
          render_error("Failed to restore conversation: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/conversations/:id/duplicate
        def duplicate
          new_title = params[:title] || "Copy of #{@conversation.title}"
          include_messages = params[:include_messages] == "true" || params[:include_messages] == true

          # Create new conversation with same settings
          new_conversation = current_user.account.ai_conversations.build(
            user: current_user,
            agent: @conversation.agent,
            provider: @conversation.provider,
            title: new_title,
            status: "active",
            is_collaborative: @conversation.is_collaborative?,
            participants: @conversation.participants
          )

          if new_conversation.save
            # Copy messages if requested
            if include_messages
              @conversation.messages.ordered.each do |message|
                new_conversation.messages.create!(
                  role: message.role,
                  content: message.content,
                  message_type: message.message_type,
                  user: message.user,
                  agent: message.agent,
                  sequence_number: message.sequence_number
                )
              end
            end

            render_success({
              conversation: serialize_conversation_detail(new_conversation),
              message: "Conversation duplicated successfully"
            }, status: :created)

            log_audit_event("ai.conversations.duplicate", new_conversation,
              original_conversation_id: @conversation.conversation_id,
              included_messages: include_messages
            )
          else
            render_validation_error(new_conversation.errors)
          end
        rescue StandardError => e
          render_error("Failed to duplicate conversation: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/ai/conversations/:id/stats
        def stats
          # Calculate statistics from messages
          messages = @conversation.messages

          # Calculate average response time (time between user message and next assistant message)
          response_times = []
          messages.ordered.each_cons(2) do |msg1, msg2|
            if msg1.role == "user" && msg2.role == "assistant"
              response_times << (msg2.created_at - msg1.created_at)
            end
          end

          avg_response_time = response_times.any? ? (response_times.sum / response_times.size) : 0

          # Calculate conversation duration
          first_message = messages.ordered.first
          last_message = messages.ordered.last
          duration = if first_message && last_message && first_message != last_message
                      (last_message.created_at - first_message.created_at)
          else
                      0
          end

          stats = {
            message_count: @conversation.message_count,
            token_usage: @conversation.total_tokens,
            avg_response_time: avg_response_time.round(2),
            duration: duration.round(2),
            total_cost: @conversation.total_cost&.to_f || 0.0,
            user_message_count: messages.user_messages.count,
            assistant_message_count: messages.assistant_messages.count,
            system_message_count: messages.system_messages.count,
            first_message_at: first_message&.created_at&.iso8601,
            last_message_at: last_message&.created_at&.iso8601,
            status: @conversation.status,
            is_collaborative: @conversation.is_collaborative?,
            participant_count: @conversation.participants.size
          }

          render_success({ stats: stats })
        rescue StandardError => e
          render_internal_error("Failed to retrieve conversation stats", exception: e)
        end

        private

        # =============================================================================
        # RESOURCE LOADING
        # =============================================================================

        def set_conversation
          @conversation = current_user.account.ai_conversations.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Conversation not found", status: :not_found)
        end

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          case action_name
          when "index", "show", "stats"
            require_permission("ai.conversations.read")
          when "create", "duplicate"
            require_permission("ai.conversations.create")
          when "update", "archive", "unarchive"
            require_permission("ai.conversations.update")
          when "destroy"
            require_permission("ai.conversations.delete")
          end
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def conversation_params
          params.require(:conversation).permit(
            :title, :status, :is_collaborative,
            participants: [],
            metadata: {}
          )
        end

        # =============================================================================
        # FILTERING & SORTING
        # =============================================================================

        def apply_filters(conversations)
          # Filter by status
          conversations = conversations.where(status: params[:status]) if params[:status].present?

          # Filter by agent
          conversations = conversations.where(ai_agent_id: params[:agent_id]) if params[:agent_id].present?

          # Filter by user
          conversations = conversations.where(user_id: params[:user_id]) if params[:user_id].present?

          # Search by title
          if params[:search].present?
            search_term = "%#{params[:search]}%"
            conversations = conversations.where("title ILIKE ?", search_term)
          end

          conversations
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 25, 100 ].min

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

        def serialize_conversation(conversation)
          {
            id: conversation.id,
            conversation_id: conversation.conversation_id,
            title: conversation.title || "Conversation with #{conversation.provider.name}",
            status: conversation.status,
            message_count: conversation.message_count,
            total_tokens: conversation.total_tokens,
            total_cost: conversation.total_cost&.to_f,
            is_collaborative: conversation.is_collaborative?,
            participant_count: conversation.participants.size,
            created_at: conversation.created_at.iso8601,
            last_activity_at: conversation.last_activity_at&.iso8601,
            ai_agent: conversation.agent ? {
              id: conversation.agent.id,
              name: conversation.agent.name,
              agent_type: conversation.agent.agent_type
            } : nil,
            provider: {
              id: conversation.provider.id,
              name: conversation.provider.name,
              provider_type: conversation.provider.provider_type
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
            recent_messages: conversation.messages.recent.limit(10).map { |m| serialize_message(m) },
            metadata: {
              can_send_message: conversation.can_send_message?,
              active_session: conversation.websocket_session_id.present?
            }
          )
        end

        def serialize_message(message)
          message.message_data
        end
      end
    end
  end
end
