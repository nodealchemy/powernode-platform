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
          conversation = agent.conversations.find_by(id: params[:id]) ||
                           agent.conversations.find_by!(conversation_id: params[:id])

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
            # Resolve mentions early to determine if concierge should respond
            mentioned_ids = nil
            if conversation.workspace_conversation?
              mentioned_ids = resolve_mentioned_agent_ids(conversation, params.dig(:message, :metadata))
            end

            # Concierge responds when: no mentions (broadcast) OR concierge is explicitly mentioned
            concierge_targeted = mentioned_ids.nil? || mentioned_ids.include?(conversation.ai_agent_id)

            if concierge_targeted
              concierge = ::Ai::ConciergeService.new(conversation: conversation, user: current_user)
              concierge.process_message(content)
            end

            assistant_msg = concierge_targeted ?
              conversation.messages.where.not(role: "user").order(created_at: :desc).first : nil

            # Dispatch workspace responses for @mentioned agents
            if conversation.workspace_conversation?
              # Merge mentions from both the user's message AND the concierge's response
              concierge_mentioned_ids = if assistant_msg&.content_metadata&.dig("mentions").present?
                assistant_msg.content_metadata["mentions"].map { |m| m["id"] }.compact
              else
                []
              end

              all_mentioned_ids = ((mentioned_ids || []) + concierge_mentioned_ids).uniq

              # Fuzzy fallback: if no @mentions were found but the concierge's response
              # references agent names without @ prefix (e.g. "to Claude Code"), resolve them
              if all_mentioned_ids.empty? && assistant_msg&.content.present? && conversation.agent_team
                team = conversation.agent_team
                team.members.includes(:agent).where.not(ai_agent_id: conversation.ai_agent_id).each do |member|
                  name = member.agent&.name
                  next if name.blank?
                  base_name = name.sub(/\s*\(.*$/, "").strip
                  if assistant_msg.content.downcase.include?(base_name.downcase)
                    all_mentioned_ids << member.ai_agent_id
                  end
                end
                all_mentioned_ids.uniq!
              end

              # Exclude the concierge itself from dispatch
              all_mentioned_ids -= [conversation.ai_agent_id].compact

              if all_mentioned_ids.present?
                dispatch_workspace_responses(conversation, assistant_msg || user_message, mentioned_agent_ids: all_mentioned_ids)
                notify_mentioned_mcp_clients(conversation, assistant_msg || user_message, all_mentioned_ids)
              end
            end

            return render_success({
              user_message: serialize_message(user_message),
              assistant_message: assistant_msg ? serialize_message(assistant_msg) : nil,
              concierge_routed: concierge_targeted,
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
        # Supports cursor-based pagination via `before` and `after` (sequence_number cursors)
        def messages
          agent = current_user.account.ai_agents.find(params[:agent_id])
          conversation = agent.conversations.includes(messages: :user).find_by(id: params[:id]) ||
                         agent.conversations.includes(messages: :user).find_by(conversation_id: params[:id])

          # Fall back to team membership lookup for workspace conversations
          # (workspace conversations belong to the concierge, not the MCP client)
          if conversation.nil?
            conversation = ::Ai::Conversation
              .joins(agent_team: :members)
              .where(ai_agent_team_members: { ai_agent_id: agent.id })
              .includes(messages: :user)
              .find_by(id: params[:id]) ||
            ::Ai::Conversation
              .joins(agent_team: :members)
              .where(ai_agent_team_members: { ai_agent_id: agent.id })
              .includes(messages: :user)
              .find_by(conversation_id: params[:id])
          end

          raise ActiveRecord::RecordNotFound unless conversation

          limit = (params[:limit] || 50).to_i.clamp(1, 200)
          scope = conversation.messages.not_deleted

          if params[:before].present?
            # Loading older messages (scroll up)
            msgs = scope.where("sequence_number < ?", params[:before].to_i)
                        .order(sequence_number: :desc)
                        .limit(limit)
                        .to_a.reverse
          elsif params[:after].present?
            # Loading newer messages (real-time catch-up)
            msgs = scope.where("sequence_number > ?", params[:after].to_i)
                        .order(sequence_number: :asc)
                        .limit(limit)
                        .to_a
          else
            # Initial load: newest messages first, reversed into chronological order
            msgs = scope.order(sequence_number: :desc).limit(limit).to_a.reverse
          end

          total_count = scope.count
          oldest_seq = scope.minimum(:sequence_number)
          has_older = msgs.any? && msgs.first.sequence_number > (oldest_seq || 0)

          render_success({
            messages: msgs.map { |m| serialize_message(m) },
            pagination: {
              has_older: has_older,
              oldest_cursor: msgs.first&.sequence_number,
              newest_cursor: msgs.last&.sequence_number,
              total_count: total_count
            }
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Agent or conversation not found", status: :not_found)
        end

        # POST /api/v1/ai/agents/:agent_id/conversations/:id/clear_messages
        def clear_messages
          agent = current_user.account.ai_agents.find(params[:agent_id])
          conversation = agent.conversations.find_by(id: params[:id]) ||
                         agent.conversations.find_by(conversation_id: params[:id])

          if conversation.nil?
            conversation = ::Ai::Conversation
              .joins(agent_team: :members)
              .where(ai_agent_team_members: { ai_agent_id: agent.id })
              .find_by(id: params[:id]) ||
            ::Ai::Conversation
              .joins(agent_team: :members)
              .where(ai_agent_team_members: { ai_agent_id: agent.id })
              .find_by(conversation_id: params[:id])
          end

          raise ActiveRecord::RecordNotFound unless conversation

          count = conversation.messages.not_deleted.update_all(deleted_at: Time.current)
          conversation.update!(message_count: 0)

          render_success({ cleared_count: count })
        rescue ActiveRecord::RecordNotFound
          render_error("Agent or conversation not found", status: :not_found)
        end

        # POST /api/v1/ai/conversations/concierge
        def create_concierge
          agent = current_user.account.ai_agents.default_concierge.first
          return render_error("No concierge agent configured", status: :not_found) unless agent

          conversation = agent.conversations.active
            .where(user_id: current_user.id, conversation_type: "agent")
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

        # Dispatch background response jobs for non-primary workspace team members
        # When mentioned_agent_ids is present, only dispatches to those specific agents.
        # When nil, dispatches to all eligible agents (broadcast behavior).
        def dispatch_workspace_responses(conversation, trigger_message, mentioned_agent_ids: nil)
          team = conversation.agent_team
          return unless team&.team_type == "workspace"

          primary_agent_id = conversation.ai_agent_id

          team.members.includes(:agent).each do |member|
            agent = member.agent
            next if agent.id == primary_agent_id
            next if agent.agent_type == "mcp_client" # Notified via SSE; respond through their own mechanisms
            next unless agent.status == "active"
            next unless agent.provider&.is_active?

            # If mentions were specified, only dispatch to mentioned agents
            next if mentioned_agent_ids.present? && !mentioned_agent_ids.include?(agent.id)

            WorkerJobService.enqueue_workspace_response(
              conversation.id,
              trigger_message.id,
              agent.id,
              conversation.account_id
            )
          rescue WorkerJobService::WorkerServiceError => e
            Rails.logger.warn("[WORKSPACE] Failed to dispatch response for agent #{agent.id}: #{e.message}")
          end
        end

        # Resolve @mention names from message metadata to agent IDs
        def resolve_mentioned_agent_ids(conversation, raw_metadata)
          mentions = raw_metadata&.dig("mentions") || raw_metadata&.dig(:mentions)
          return nil if mentions.blank? || !mentions.is_a?(Array)

          team = conversation.agent_team
          return nil unless team

          mentioned_members = team.members.by_agent_names(
            mentions.map { |m| m["name"] || m[:name] }.compact
          )
          agent_ids = mentioned_members.map(&:ai_agent_id)
          agent_ids.presence
        end

        # Send targeted mention notifications to MCP client agents
        def notify_mentioned_mcp_clients(conversation, message, mentioned_agent_ids)
          return if mentioned_agent_ids.blank?

          team = conversation.agent_team
          return unless team

          mcp_members = team.members.includes(:agent)
            .where(ai_agent_id: mentioned_agent_ids)
            .where(ai_agents: { agent_type: "mcp_client" })

          return if mcp_members.empty?

          mcp_members.each do |member|
            sessions = McpSession.active.where(ai_agent_id: member.ai_agent_id)
            next if sessions.empty?

            notification = {
              type: "mention",
              conversation_id: conversation.conversation_id,
              workspace: team.name,
              mentioned_agent_id: member.ai_agent_id,
              message: {
                id: message.message_id,
                role: message.role,
                content: message.content.to_s.truncate(500),
                sender: message.user&.name || "Unknown",
                created_at: message.created_at&.iso8601
              }
            }.to_json

            sessions.find_each do |session|
              ActionCable.server.pubsub.broadcast("mcp_session:#{session.session_token}", notification)
            end
          end
        rescue StandardError => e
          Rails.logger.warn("[WORKSPACE] Failed to notify mentioned MCP clients: #{e.message}")
        end

        def set_conversation
          account = current_user&.account || current_account
          return render_error("Conversation not found", status: :not_found) unless account

          @conversation = account.ai_conversations
                           .includes(:user, :agent, :provider, messages: [:user])
                           .find_by(id: params[:id]) ||
                         account.ai_conversations
                           .includes(:user, :agent, :provider, messages: [:user])
                           .find_by(conversation_id: params[:id])
          render_error("Conversation not found", status: :not_found) unless @conversation
        end

      end
    end
  end
end
