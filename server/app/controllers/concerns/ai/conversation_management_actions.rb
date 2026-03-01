# frozen_string_literal: true

# Conversation management actions: pin/unpin, bulk ops, search, worker callbacks
#
# Extracted from ConversationsController to keep it under 300 lines.
module Ai
  module ConversationManagementActions
    extend ActiveSupport::Concern

    # POST /api/v1/ai/conversations/:id/pin
    def pin
      @conversation.pin!

      render_success({
        conversation: serialize_conversation(@conversation),
        message: "Conversation pinned successfully"
      })

      log_audit_event("ai.conversations.pin", @conversation)
    rescue ActiveRecord::RecordInvalid => e
      render_error("Failed to pin conversation: #{e.message}", status: :unprocessable_content)
    end

    # DELETE /api/v1/ai/conversations/:id/unpin
    def unpin
      @conversation.unpin!

      render_success({
        conversation: serialize_conversation(@conversation),
        message: "Conversation unpinned successfully"
      })

      log_audit_event("ai.conversations.unpin", @conversation)
    rescue ActiveRecord::RecordInvalid => e
      render_error("Failed to unpin conversation: #{e.message}", status: :unprocessable_content)
    end

    # PATCH /api/v1/ai/conversations/bulk
    def bulk
      ids = params[:conversation_ids]
      return render_error("conversation_ids required", status: :bad_request) if ids.blank?

      conversations = current_user.account.ai_conversations.where(id: ids)
      return render_error("No conversations found", status: :not_found) if conversations.empty?

      action = params[:action_type]
      case action
      when "archive"
        conversations.update_all(status: "archived", updated_at: Time.current)
      when "delete"
        conversations.destroy_all
      when "tag"
        tag = params[:tag]&.strip&.downcase
        return render_error("tag required", status: :bad_request) if tag.blank?

        conversations.find_each { |c| c.add_tag(tag) }
      when "untag"
        tag = params[:tag]&.strip&.downcase
        return render_error("tag required", status: :bad_request) if tag.blank?

        conversations.find_each { |c| c.remove_tag(tag) }
      when "pin"
        conversations.update_all(pinned_at: Time.current, updated_at: Time.current)
      when "unpin"
        conversations.update_all(pinned_at: nil, updated_at: Time.current)
      else
        return render_error("Invalid action_type. Must be: archive, delete, tag, untag, pin, unpin", status: :bad_request)
      end

      render_success({
        affected_count: conversations.count,
        action: action,
        message: "Bulk #{action} completed successfully"
      })

      log_audit_event("ai.conversations.bulk_#{action}", nil, conversation_ids: ids)
    rescue StandardError => e
      render_error("Bulk operation failed: #{e.message}", status: :unprocessable_content)
    end

    # GET /api/v1/ai/conversations/search
    def search
      query = params[:q]
      return render_error("Search query required", status: :bad_request) if query.blank?

      conversations = ::Ai::Conversation
                        .search_messages(query, account_id: current_user.account_id)
                        .includes(:user, :agent, :provider)

      conversations = apply_pagination(conversations)

      render_success({
        conversations: conversations.map { |c| serialize_conversation(c) },
        pagination: pagination_data(conversations),
        query: query
      })
    rescue StandardError => e
      render_error("Search failed: #{e.message}", status: :unprocessable_content)
    end

    # POST /api/v1/ai/conversations/:id/worker_complete
    # Internal endpoint for worker to broadcast completed chat response
    # Accepts optional agent_id param for workspace responses (message attribution)
    def worker_complete
      conversation = current_account_conversations.find_by(id: params[:id]) ||
                     current_account_conversations.find_by(conversation_id: params[:id])
      return render_error("Conversation not found", status: :not_found) unless conversation

      content = params[:content]
      return render_error("Content required", status: :bad_request) if content.blank?

      # Resolve agent for message attribution (workspace responses specify their own agent)
      responding_agent = nil
      if params[:agent_id].present?
        responding_agent = conversation.account.ai_agents.find_by(id: params[:agent_id])
      end

      # For workspace conversations, split @mention messages into separate entries:
      # narration ("I'll ask Claude...") and @mention ("@Claude Code, please...")
      narration, mention_content, mentioned_ids = split_workspace_mention(conversation, content, responding_agent)

      assistant_message = conversation.add_assistant_message(
        narration || content,
        broadcast: false,
        agent: responding_agent,
        message_type: "text",
        token_count: params[:token_count]&.to_i || 0,
        cost_usd: params[:cost_usd]&.to_f || 0.0,
        processing_metadata: {
          model: params[:model],
          duration_ms: params[:duration_ms],
          source: "worker"
        }
      )

      conversation.broadcast_ai_complete(assistant_message)

      if mention_content.present?
        # Narration was split out — create a second message for the @mention and dispatch
        mention_message = conversation.add_assistant_message(
          mention_content,
          broadcast: false,
          agent: responding_agent,
          message_type: "text",
          token_count: 0,
          cost_usd: 0.0,
          processing_metadata: { source: "worker", split_from: assistant_message.message_id }
        )

        conversation.broadcast_ai_complete(mention_message)

        if mentioned_ids.present?
          dispatch_workspace_responses(conversation, mention_message, mentioned_agent_ids: mentioned_ids)
          notify_mentioned_mcp_clients(conversation, mention_message, mentioned_ids)
        end
      elsif conversation.workspace_conversation?
        # No split needed — but still dispatch if the full message contains @mentions.
        # This handles the case where the entire response IS an @mention (no narration prefix).
        unsplit_ids = detect_workspace_mentions(conversation, content, responding_agent)
        if unsplit_ids.present?
          dispatch_workspace_responses(conversation, assistant_message, mentioned_agent_ids: unsplit_ids)
          notify_mentioned_mcp_clients(conversation, assistant_message, unsplit_ids)
        end
      end

      render_success({ message_id: assistant_message.message_id })
    rescue StandardError => e
      render_error("Failed to complete: #{e.message}", status: :unprocessable_content)
    end

    # POST /api/v1/ai/conversations/:id/worker_stream_chunk
    # Internal endpoint for worker to broadcast streaming token chunks
    # No database write — chunks are transient, only worker_complete persists
    def worker_stream_chunk
      conversation = current_account_conversations.find_by(id: params[:id]) ||
                     current_account_conversations.find_by(conversation_id: params[:id])
      return render_error("Conversation not found", status: :not_found) unless conversation

      ActionCable.server.broadcast(
        conversation.websocket_channel,
        {
          type: "ai_response_streaming",
          conversation_id: conversation.conversation_id,
          message: {
            id: params[:message_id] || "streaming-#{conversation.id}",
            content: params[:accumulated_content] || "",
            sender_type: "ai",
            sender_info: { name: params[:agent_name] || "AI Assistant" },
            created_at: Time.current.iso8601,
            metadata: {
              streaming: true,
              tokens_used: params[:token_count]&.to_i || 0,
              model: params[:model],
              sequence: params[:sequence]&.to_i || 0
            }
          }
        }
      )

      render_success({ broadcast: true })
    rescue StandardError => e
      render_error("Failed to broadcast chunk: #{e.message}", status: :unprocessable_content)
    end

    # POST /api/v1/ai/conversations/:id/worker_error
    # Internal endpoint for worker to broadcast error
    def worker_error
      conversation = current_account_conversations.find_by(id: params[:id]) ||
                     current_account_conversations.find_by(conversation_id: params[:id])
      return render_error("Conversation not found", status: :not_found) unless conversation

      ActionCable.server.broadcast(
        conversation.websocket_channel,
        {
          type: "error",
          conversation_id: conversation.conversation_id,
          error: params[:error] || "Unknown error"
        }
      )

      render_success({ broadcast: true })
    rescue StandardError => e
      render_error("Failed to broadcast error: #{e.message}", status: :unprocessable_content)
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
      Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
      render_error("Failed to duplicate conversation: #{e.message}", status: :unprocessable_content)
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

    # =========================================================================
    # Scheduled Messages CRUD
    # =========================================================================

    # GET /api/v1/ai/conversations/:id/scheduled_messages
    def scheduled_messages_index
      conversation = current_account_conversations.find(params[:conversation_id] || params[:id])
      scheduled = conversation.scheduled_messages.order(created_at: :desc)

      render_success({
        scheduled_messages: scheduled.map { |sm| serialize_scheduled_message(sm) }
      })
    rescue ActiveRecord::RecordNotFound
      render_error("Conversation not found", status: :not_found)
    end

    # POST /api/v1/ai/conversations/:id/scheduled_messages
    def scheduled_messages_create
      conversation = current_account_conversations.find(params[:conversation_id] || params[:id])

      sm = conversation.scheduled_messages.build(
        scheduled_message_params.merge(
          account: current_user.account,
          user: current_user
        )
      )

      if sm.save
        render_success({ scheduled_message: serialize_scheduled_message(sm) }, status: :created)
      else
        render_validation_error(sm.errors)
      end
    rescue ActiveRecord::RecordNotFound
      render_error("Conversation not found", status: :not_found)
    end

    # PATCH /api/v1/ai/conversations/:conversation_id/scheduled_messages/:id
    def scheduled_messages_update
      conversation = current_account_conversations.find(params[:conversation_id])
      sm = conversation.scheduled_messages.find(params[:id])

      if sm.update(scheduled_message_params)
        render_success({ scheduled_message: serialize_scheduled_message(sm) })
      else
        render_validation_error(sm.errors)
      end
    rescue ActiveRecord::RecordNotFound
      render_error("Resource not found", status: :not_found)
    end

    # DELETE /api/v1/ai/conversations/:conversation_id/scheduled_messages/:id
    def scheduled_messages_destroy
      conversation = current_account_conversations.find(params[:conversation_id])
      sm = conversation.scheduled_messages.find(params[:id])
      sm.destroy!

      render_success({ message: "Scheduled message deleted successfully" })
    rescue ActiveRecord::RecordNotFound
      render_error("Resource not found", status: :not_found)
    end

    private

    def scheduled_message_params
      params.require(:scheduled_message).permit(
        :scheduling_mode, :message_template, :status,
        :next_scheduled_at, :max_executions,
        schedule_config: {}, template_variables: {}
      )
    end

    def serialize_scheduled_message(sm)
      {
        id: sm.id,
        scheduling_mode: sm.scheduling_mode,
        message_template: sm.message_template,
        template_variables: sm.template_variables,
        schedule_config: sm.schedule_config,
        status: sm.status,
        next_scheduled_at: sm.next_scheduled_at&.iso8601,
        last_executed_at: sm.last_executed_at&.iso8601,
        execution_count: sm.execution_count,
        max_executions: sm.max_executions,
        created_at: sm.created_at.iso8601,
        updated_at: sm.updated_at.iso8601
      }
    end

    def current_account_conversations
      account = current_user&.account || current_account
      account&.ai_conversations || ::Ai::Conversation.none
    end

    # Detect @mentions in message content without splitting.
    # Returns array of mentioned agent IDs, excluding the responding agent.
    def detect_workspace_mentions(conversation, content, responding_agent)
      team = conversation.agent_team
      return [] unless team

      members = team.members.includes(:agent).to_a
      members.sort_by! { |m| -(m.agent&.name&.length || 0) }

      mentioned_ids = []
      members.each do |member|
        name = member.agent&.name
        next if name.blank?
        next if responding_agent && member.ai_agent_id == responding_agent.id

        mentioned_ids << member.ai_agent_id if content.include?("@#{name}")
      end

      mentioned_ids.uniq
    end

    # Split a workspace agent's response into narration + @mention if the response
    # contains an @mention of another workspace member. Returns [narration, mention_content, mentioned_ids].
    # If no split is needed, returns [nil, nil, nil].
    def split_workspace_mention(conversation, content, responding_agent)
      return [nil, nil, nil] unless conversation.workspace_conversation?

      team = conversation.agent_team
      return [nil, nil, nil] unless team

      # Find @mentions of workspace members in the content
      members = team.members.includes(:agent).to_a
      # Sort by name length descending so longer names match first
      members.sort_by! { |m| -(m.agent&.name&.length || 0) }

      first_mention_pos = nil
      mentioned_ids = []

      members.each do |member|
        name = member.agent&.name
        next if name.blank?
        next if responding_agent && member.ai_agent_id == responding_agent.id # Skip self-mentions

        pos = content.index("@#{name}")
        next unless pos

        mentioned_ids << member.ai_agent_id
        first_mention_pos = pos if first_mention_pos.nil? || pos < first_mention_pos
      end

      return [nil, nil, nil] if mentioned_ids.empty? || first_mention_pos.nil?

      # Split at the first @mention position
      narration = content[0...first_mention_pos].strip
      mention_content = content[first_mention_pos..].strip

      # Only split if there's meaningful narration before the @mention
      return [nil, nil, nil] if narration.blank?

      [narration, mention_content, mentioned_ids]
    end
  end
end
