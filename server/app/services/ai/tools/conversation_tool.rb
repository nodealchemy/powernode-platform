# frozen_string_literal: true

module Ai
  module Tools
    # Unified conversation tool — handles workspaces, agent conversations, and concierge interactions.
    # Merges the former WorkspaceTool and ConciergeTool into a single entry point.
    class ConversationTool < BaseTool
      include ::Ai::ConversationAiGeneration

      REQUIRED_PERMISSION = "ai.conversations.create"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "active_sessions", mutating: false
      declare_action "confirm_concierge_action", mutating: true
      declare_action "create_workspace", mutating: true
      declare_action "get_conversation_messages", mutating: false
      declare_action "invite_agent", mutating: true
      declare_action "list_conversations", mutating: false
      declare_action "list_messages", mutating: false
      declare_action "list_workspaces", mutating: false
      declare_action "pin_conversation", mutating: true
      declare_action "send_concierge_message", mutating: true
      declare_action "send_message", mutating: true
      declare_action "tag_conversation", mutating: true
      declare_action "unpin_conversation", mutating: true

      def self.definition
        {
          name: "conversation",
          description: "Manage all conversations — workspaces, agent chats, and concierge interactions",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            conversation_id: { type: "string", required: false, description: "Conversation ID (any type)" },
            message: { type: "string", required: false, description: "Message content" },
            mentions: { type: "array", required: false, description: "Agent mentions [{\"id\": \"...\", \"name\": \"...\"}]" },
            name: { type: "string", required: false, description: "Workspace name (for create_workspace)" },
            agent_ids: { type: "array", required: false, description: "Agent IDs (for create_workspace)" },
            agent_id: { type: "string", required: false, description: "Agent ID (for invite_agent)" },
            include_concierge: { type: "boolean", required: false, description: "Auto-add concierge (for create_workspace)" },
            action_type: { type: "string", required: false, description: "Concierge action type (for confirm_concierge_action)" },
            action_params: { type: "object", required: false, description: "Concierge action params (for confirm_concierge_action)" },
            status: { type: "string", required: false, description: "Filter by status (for list_conversations)" },
            limit: { type: "integer", required: false, description: "Max results" }
          }
        }
      end

      def self.action_definitions
        {
          # --- Messaging (works for any conversation type) ---
          "send_message" => {
            description: "Send a message to any conversation (workspace or agent). " \
                         "The conversation's agent will auto-respond (async for regular agents, sync for concierge). " \
                         "Include @mentions to notify specific agents in workspaces.",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Conversation ID (workspace or agent)" },
              message: { type: "string", required: true, description: "Message content (include @AgentName to mention)" },
              mentions: { type: "array", required: false, description: "Structured agent mentions [{\"id\": \"...\", \"name\": \"...\"}]" }
            }
          },
          "list_messages" => {
            description: "Retrieve messages from any conversation (workspace or agent)",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Conversation ID" },
              limit: { type: "integer", required: false, description: "Max messages (default 20, max 100)" }
            }
          },
          "get_conversation_messages" => {
            description: "Retrieve message history for a conversation including role, content, metadata, and timestamps",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Conversation ID to retrieve messages from" },
              limit: { type: "integer", required: false, description: "Max messages to return (default 20, max 100)" }
            }
          },
          # --- Listing ---
          "list_conversations" => {
            description: "List all conversations — workspaces, agent conversations, and concierge chats",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status: active, paused, completed, archived (default: all)" },
              limit: { type: "integer", required: false, description: "Max results (default 10, max 50)" }
            }
          },
          # --- Concierge ---
          "send_concierge_message" => {
            description: "Send a message to the Powernode concierge and get an AI response. Creates or reuses an active concierge conversation.",
            parameters: {
              message: { type: "string", required: true, description: "Message to send to the concierge" }
            }
          },
          "confirm_concierge_action" => {
            description: "Confirm a pending concierge action (create_mission, delegate_to_team, code_review, deploy).",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Conversation ID containing the pending action" },
              action_type: { type: "string", required: true, description: "Action type: create_mission, delegate_to_team, code_review, deploy" },
              action_params: { type: "object", required: false, description: "Optional parameters (overrides original params)" }
            }
          },
          # --- Workspaces ---
          "create_workspace" => {
            description: "Create a workspace conversation with selected agents for multi-agent collaboration.",
            parameters: {
              name: { type: "string", required: true, description: "Workspace name" },
              agent_ids: { type: "array", required: false, description: "Agent IDs to include" },
              include_concierge: { type: "boolean", required: false, description: "Auto-add concierge (default: false)" }
            }
          },
          "invite_agent" => {
            description: "Invite an agent to a workspace conversation",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Workspace conversation ID" },
              agent_id: { type: "string", required: true, description: "Agent ID (or 'concierge')" }
            }
          },
          "active_sessions" => {
            description: "List active MCP client sessions that can be invited to workspaces",
            parameters: {}
          },
          "list_workspaces" => {
            description: "List workspace conversations (alias for list_conversations filtered to workspaces)",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status: active, paused, completed, archived (default: all)" },
              limit: { type: "integer", required: false, description: "Max results (default 10, max 50)" }
            }
          },
          "pin_conversation" => {
            description: "Pin a conversation to the top of the sidebar list. Sets pinned_at to now.",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Conversation UUID or conversation_id" }
            }
          },
          "unpin_conversation" => {
            description: "Unpin a conversation (clears pinned_at).",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Conversation UUID or conversation_id" }
            }
          },
          "tag_conversation" => {
            description: "Set, add, or remove tags on a conversation. Pass `tags:` to replace, `add_tag:` to append, or `remove_tag:` to remove.",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Conversation UUID or conversation_id" },
              tags: { type: "array", required: false, description: "Replace the conversation's tag list with this array" },
              add_tag: { type: "string", required: false, description: "Append a single tag (idempotent — won't dup)" },
              remove_tag: { type: "string", required: false, description: "Remove a single tag" }
            }
          }
        }
      end

      protected

      def call(params)
        return { success: false, error: "User context required" } unless user

        case params[:action]
        # Messaging
        when "send_message" then send_conversation_message(params)
        when "list_messages", "get_conversation_messages" then list_messages(params)
        # Listing
        when "list_conversations", "list_workspaces" then list_conversations(params)
        # Concierge
        when "send_concierge_message" then send_concierge_message(params)
        when "confirm_concierge_action" then confirm_concierge_action(params)
        # Workspaces
        when "create_workspace" then create_workspace(params)
        when "invite_agent" then invite_agent(params)
        when "active_sessions" then list_active_sessions(params)
        # Pin / tag (HIGH-tier additions)
        when "pin_conversation" then pin_conversation(params)
        when "unpin_conversation" then unpin_conversation(params)
        when "tag_conversation" then tag_conversation(params)
        else
          { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def resolve_conversation(conv_id)
        account.ai_conversations.find_by(id: conv_id) ||
          account.ai_conversations.find_by(conversation_id: conv_id)
      end

      def pin_conversation(params)
        conv = resolve_conversation(params[:conversation_id])
        return { success: false, error: "Conversation not found" } unless conv
        conv.update!(pinned_at: Time.current)
        { success: true, conversation_id: conv.id, pinned_at: conv.pinned_at.iso8601 }
      end

      def unpin_conversation(params)
        conv = resolve_conversation(params[:conversation_id])
        return { success: false, error: "Conversation not found" } unless conv
        conv.update!(pinned_at: nil)
        { success: true, conversation_id: conv.id, pinned: false }
      end

      def tag_conversation(params)
        conv = resolve_conversation(params[:conversation_id])
        return { success: false, error: "Conversation not found" } unless conv
        tags = params[:tags]
        if tags.is_a?(Array)
          conv.update!(tags: tags.map { |t| t.to_s.strip.downcase }.reject(&:blank?).uniq)
        elsif params[:add_tag].present?
          new_tags = ((conv.tags || []) + [params[:add_tag].to_s.strip.downcase]).uniq
          conv.update!(tags: new_tags)
        elsif params[:remove_tag].present?
          conv.update!(tags: (conv.tags || []) - [params[:remove_tag].to_s.strip.downcase])
        else
          return { success: false, error: "Specify tags: (replace), add_tag:, or remove_tag:" }
        end
        { success: true, conversation_id: conv.id, tags: conv.reload.tags }
      end

      private

      # =====================================================================
      # Messaging (any conversation type)
      # =====================================================================

      def send_conversation_message(params)
        return { success: false, error: "conversation_id is required" } if params[:conversation_id].blank?
        return { success: false, error: "message is required" } if params[:message].blank?

        conversation = find_conversation(params[:conversation_id])
        return { success: false, error: "Conversation not found" } unless conversation

        metadata = build_mention_metadata(params, conversation)

        # Send as user message so the conversation's agent will respond
        # (mirrors conversations_controller#send_message behavior)
        message = conversation.add_user_message(
          params[:message],
          user: user,
          content_metadata: metadata.presence
        )

        # Dispatch agent response based on conversation type
        dispatched_agents = []
        response_message = nil

        if conversation.workspace_conversation?
          # Workspace: dispatch @mentioned agents (including concierge if present)
          dispatched_agents = dispatch_mentioned_responses(conversation, message, metadata)
        elsif conversation.agent&.respond_to?(:is_concierge?) && conversation.agent.is_concierge?
          # Concierge: process synchronously via ConciergeService
          concierge = Ai::ConciergeService.new(conversation: conversation, user: user)
          concierge.process_message(params[:message])
          response_message = conversation.messages.not_deleted.where(role: "assistant").order(created_at: :desc).first
          dispatched_agents = [{ id: conversation.agent.id, name: conversation.agent.name, type: "concierge" }]
        elsif conversation.agent&.provider&.is_active?
          # Regular agent conversation: generate response synchronously
          # (mirrors conversations_controller#send_message behavior — the async
          # worker path has a 404 bug in AiChatResponseJob's agent lookup)
          agent = conversation.agent
          messages_for_ai = build_messages_for_ai(conversation, agent)
          ai_response = generate_ai_response(agent, messages_for_ai)

          if ai_response[:success]
            response_message = conversation.add_assistant_message(
              ai_response[:content],
              message_type: "text",
              token_count: ai_response[:usage]&.dig(:total_tokens) || 0,
              cost_usd: calculate_cost(ai_response[:usage], agent.provider),
              processing_metadata: {
                model: ai_response[:model],
                finish_reason: ai_response[:finish_reason],
                usage: ai_response[:usage]
              }.compact
            )
          end
          dispatched_agents = [{ id: agent.id, name: agent.name, type: agent.agent_type }]
        end

        result = {
          success: true,
          conversation_id: conversation.conversation_id,
          message_id: message.message_id,
          sender: user.name || user.email,
          dispatched_to: dispatched_agents
        }
        result[:response] = response_message.content if response_message
        result
      rescue StandardError => e
        Rails.logger.error("[ConversationTool] send_message error: #{e.message}")
        { success: false, error: "Failed to send message: #{e.message}" }
      end

      def list_messages(params)
        return { success: false, error: "conversation_id is required" } if params[:conversation_id].blank?

        conversation = find_conversation(params[:conversation_id])
        return { success: false, error: "Conversation not found" } unless conversation

        limit = (params[:limit] || 20).to_i.clamp(1, 100)
        messages = conversation.messages.not_deleted.ordered.includes(:user, :agent).last(limit)

        {
          success: true,
          conversation_id: conversation.conversation_id,
          agent: conversation.agent&.name,
          count: messages.size,
          messages: messages.map { |m| serialize_message(m) }
        }
      end

      # =====================================================================
      # Listing
      # =====================================================================

      def list_conversations(params)
        scope = Ai::Conversation.where(account: account)
        scope = scope.where(status: params[:status]) if params[:status].present?

        limit = (params[:limit] || 10).to_i.clamp(1, 50)
        conversations = scope.includes(:agent, :provider, :agent_team)
          .order(last_activity_at: :desc)
          .limit(limit)

        {
          success: true,
          count: conversations.size,
          conversations: conversations.map { |c| serialize_conversation(c) }
        }
      end

      # =====================================================================
      # Concierge
      # =====================================================================

      def send_concierge_message(params)
        return { success: false, error: "message is required" } if params[:message].blank?

        concierge_agent = ::Ai::Agent.resolve_concierge_for(account.id)
        return { success: false, error: "No concierge agent configured for this account" } unless concierge_agent

        conversation = find_or_create_concierge_conversation(concierge_agent)
        conversation.add_user_message(params[:message], user: user)

        service = Ai::ConciergeService.new(conversation: conversation, user: user)
        service.process_message(params[:message])

        last_message = conversation.messages.not_deleted.where(role: "assistant").order(created_at: :desc).first
        notify_user_of_response(conversation, concierge_agent, last_message) if last_message

        response = {
          success: true,
          conversation_id: conversation.conversation_id,
          response: last_message&.content,
          message_id: last_message&.message_id
        }

        if last_message&.content_metadata&.dig("concierge_action")
          response[:pending_action] = {
            action_type: last_message.content_metadata.dig("action_context", "action_type"),
            status: last_message.content_metadata.dig("action_context", "status"),
            actions: last_message.content_metadata["actions"]
          }
        end

        response
      rescue StandardError => e
        Rails.logger.error("[ConversationTool] send_concierge_message error: #{e.message}")
        { success: false, error: "Failed to process message: #{e.message}" }
      end

      def confirm_concierge_action(params)
        return { success: false, error: "conversation_id is required" } if params[:conversation_id].blank?
        return { success: false, error: "action_type is required" } if params[:action_type].blank?

        conversation = find_conversation(params[:conversation_id])
        return { success: false, error: "Conversation not found" } unless conversation
        return { success: false, error: "Not a concierge conversation" } unless conversation.agent&.is_concierge?

        action_params = params[:action_params] || {}
        action_params = action_params.to_h if action_params.respond_to?(:to_h)

        if action_params.empty?
          pending = find_pending_action(conversation, params[:action_type])
          action_params = pending&.dig("action_params") || {}
        end

        service = Ai::ConciergeService.new(conversation: conversation, user: user)
        service.handle_confirmed_action(params[:action_type], action_params)

        last_message = conversation.messages.not_deleted.order(created_at: :desc).first

        {
          success: true,
          conversation_id: conversation.conversation_id,
          action_type: params[:action_type],
          result: last_message&.content
        }
      rescue StandardError => e
        Rails.logger.error("[ConversationTool] confirm_concierge_action error: #{e.message}")
        { success: false, error: "Failed to confirm action: #{e.message}" }
      end

      # =====================================================================
      # Workspaces
      # =====================================================================

      def workspace_service
        @workspace_service ||= Ai::WorkspaceService.new(account: account, user: user)
      end

      def create_workspace(params)
        return { success: false, error: "name is required" } if params[:name].blank?

        agent_ids = Array(params[:agent_ids])
        if params[:include_concierge]
          concierge = ::Ai::Agent.resolve_concierge_for(account.id)
          agent_ids << concierge.id if concierge && !agent_ids.include?(concierge.id)
        end

        result = workspace_service.create_workspace(name: params[:name], agent_ids: agent_ids)

        {
          success: true,
          workspace: {
            team_id: result[:team].id,
            team_name: result[:team].name,
            conversation_id: result[:conversation].conversation_id,
            conversation_db_id: result[:conversation].id,
            members: result[:team].members.includes(:agent).map { |m|
              { agent_id: m.ai_agent_id, name: m.agent_name, role: m.role, agent_type: m.agent_agent_type }
            }
          }
        }
      rescue StandardError => e
        Rails.logger.error("[ConversationTool] create_workspace error: #{e.message}")
        { success: false, error: "Failed to create workspace: #{e.message}" }
      end

      def invite_agent(params)
        return { success: false, error: "conversation_id is required" } if params[:conversation_id].blank?
        return { success: false, error: "agent_id is required" } if params[:agent_id].blank?

        conversation = find_conversation(params[:conversation_id])
        return { success: false, error: "Conversation not found" } unless conversation

        target_agent = if params[:agent_id] == "concierge"
                         ::Ai::Agent.resolve_concierge_for(account.id)
        else
                         ::Ai::Agent.for_account(account.id).find_by(id: params[:agent_id])
        end
        return { success: false, error: "Agent not found" } unless target_agent

        workspace_service.invite_agent(workspace_conversation: conversation, agent: target_agent)

        {
          success: true,
          conversation_id: conversation.conversation_id,
          invited_agent: { id: target_agent.id, name: target_agent.name, agent_type: target_agent.agent_type }
        }
      rescue StandardError => e
        Rails.logger.error("[ConversationTool] invite_agent error: #{e.message}")
        { success: false, error: "Failed to invite agent: #{e.message}" }
      end

      def list_active_sessions(_params)
        sessions = workspace_service.active_mcp_sessions

        {
          success: true,
          count: sessions.size,
          sessions: sessions.map { |s| serialize_session(s) }
        }
      end

      # =====================================================================
      # Mention dispatch
      # =====================================================================

      def build_mention_metadata(params, conversation)
        metadata = {}
        if params[:mentions].present? && params[:mentions].is_a?(Array)
          metadata["mentions"] = params[:mentions].map { |m|
            { "id" => m["id"] || m[:id], "name" => m["name"] || m[:name] }
          }.select { |m| m["id"].present? && m["name"].present? }
        end

        if metadata["mentions"].blank? && conversation.agent_team
          fuzzy = resolve_fuzzy_mentions(params[:message], conversation.agent_team)
          metadata["mentions"] = fuzzy if fuzzy.present?
        end

        mention_segments = conversation.parse_mention_segments(params[:message])
        metadata["mention_segments"] = mention_segments if mention_segments.present?

        metadata
      end

      def dispatch_mentioned_responses(conversation, trigger_message, metadata)
        team = conversation.agent_team
        return [] unless team&.team_type == "workspace"

        mentions = metadata.dig("mentions")
        mentioned_ids = if mentions.present?
          mentioned_names = mentions.map { |m| m["name"] }.compact
          team.members.by_agent_names(mentioned_names).pluck(:ai_agent_id)
        else
          resolve_text_mentions(trigger_message.content, team)
        end

        return [] if mentioned_ids.empty?

        if agent&.id == conversation.ai_agent_id
          mentioned_ids -= [conversation.ai_agent_id].compact
        end

        return [] if mentioned_ids.empty?

        dispatched = []
        team.members.includes(:agent).each do |member|
          a = member.agent
          next unless mentioned_ids.include?(a.id)
          next if a.id == agent&.id
          next unless a.status == "active"

          if a.agent_type == "mcp_client"
            notify_mcp_client(conversation, trigger_message, a, team)
          else
            next unless a.provider&.is_active?
            WorkerJobService.enqueue_workspace_response(
              conversation.id, trigger_message.message_id, a.id, conversation.account_id
            )
          end
          dispatched << { id: a.id, name: a.name, type: a.agent_type }
        rescue WorkerJobService::WorkerServiceError => e
          Rails.logger.warn("[ConversationTool] Failed to dispatch response for agent #{a.id}: #{e.message}")
        end

        dispatched
      end

      def notify_mcp_client(conversation, message, target_agent, team)
        sessions = McpSession.active.where(ai_agent_id: target_agent.id)
        return if sessions.empty?

        notification = {
          type: "mention",
          conversation_id: conversation.conversation_id,
          workspace: team.name,
          mentioned_agent_id: target_agent.id,
          message: {
            id: message.message_id,
            role: message.role,
            content: message.content.to_s.truncate(500),
            sender: message.agent&.name || message.user&.name || "Unknown",
            created_at: message.created_at&.iso8601
          }
        }

        mention_segments = message.content_metadata&.dig("mention_segments")
        if mention_segments
          agent_segment = mention_segments.dig("segments", target_agent.id)
          notification[:segment] = agent_segment if agent_segment.present?
          notification[:preamble] = mention_segments["preamble"]
        end

        notification = notification.to_json
        sessions.find_each do |session|
          ActionCable.server.pubsub.broadcast("mcp_session:#{session.session_token}", notification)
        end
      rescue StandardError => e
        Rails.logger.warn("[ConversationTool] Failed to notify MCP client #{target_agent.id}: #{e.message}")
      end

      def resolve_text_mentions(content, team)
        return [] if content.blank?

        members = team.members.includes(:agent).to_a
        members.sort_by! { |m| -(m.agent&.name&.length || 0) }

        mentioned_ids = []
        members.each do |member|
          name = member.agent&.name
          next if name.blank?
          mentioned_ids << member.ai_agent_id if content.include?("@#{name}")
        end

        mentioned_ids.uniq
      end

      def resolve_fuzzy_mentions(content, team)
        return [] if content.blank?

        downcased = content.downcase
        members = team.members.includes(:agent).where.not(ai_agent_id: agent&.id).to_a
        mentions = []

        members.each do |member|
          name = member.agent&.name
          next if name.blank?

          candidates = [name]
          candidates << name.sub(/\s*\(.*$/, "").strip if name.include?("(")
          candidates << name.split(/\s+/).first(2).join(" ") if name.split(/\s+/).length > 2

          matched = candidates.any? { |c| downcased.include?(c.downcase) }
          mentions << { "id" => member.ai_agent_id, "name" => name } if matched
        end

        mentions.uniq { |m| m["id"] }
      end

      # =====================================================================
      # Helpers
      # =====================================================================

      def find_conversation(conversation_id)
        base = Ai::Conversation.where(account: account)

        result = base.find_by(id: conversation_id) ||
                 base.find_by(conversation_id: conversation_id)
        return result if result

        sanitized = conversation_id.to_s.strip
        if sanitized.length >= 3 && !sanitized.match?(/\A[0-9a-f-]{36}\z/i)
          base.joins(:agent_team).where("ai_agent_teams.name ILIKE ?", "%#{sanitized}%")
              .order(last_activity_at: :desc).first ||
            base.joins(:agent).where("ai_agents.name ILIKE ?", "%#{sanitized}%")
              .order(last_activity_at: :desc).first
        end
      end

      def find_or_create_concierge_conversation(concierge_agent)
        existing = concierge_agent.conversations.active
          .where(user_id: user.id)
          .order(last_activity_at: :desc).first

        return existing if existing

        concierge_agent.conversations.create!(
          conversation_id: SecureRandom.uuid,
          user_id: user.id,
          account_id: account.id,
          ai_provider_id: concierge_agent.ai_provider_id,
          title: "Chat with #{concierge_agent.name}",
          status: "active",
          conversation_type: "agent",
          last_activity_at: Time.current
        )
      end

      def find_pending_action(conversation, action_type)
        message = conversation.messages
          .where(role: "assistant")
          .order(created_at: :desc)
          .find { |m|
            m.content_metadata&.dig("concierge_action") &&
              m.content_metadata&.dig("action_context", "status") == "pending" &&
              m.content_metadata&.dig("action_context", "action_type") == action_type
          }

        message&.content_metadata
      end

      def notify_user_of_response(conversation, concierge_agent, last_message)
        return if conversation.websocket_session_id.present?

        recent = Notification.where(
          user: user,
          notification_type: "ai_concierge_message"
        ).where("created_at > ?", 60.seconds.ago).find do |n|
          n.metadata&.dig("conversation_id") == conversation.conversation_id
        end
        return if recent

        Notification.create_for_user(
          user,
          type: "ai_concierge_message",
          title: "Message from #{concierge_agent.name}",
          message: "**#{concierge_agent.name}:** #{last_message.content.to_s.truncate(120)}",
          severity: "info",
          category: "ai",
          action_url: "/app/ai/chat",
          action_label: "Open Chat",
          metadata: {
            conversation_id: conversation.conversation_id,
            agent_id: concierge_agent.id,
            message_id: last_message.message_id
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[ConversationTool] Failed to create notification: #{e.message}")
      end

      # =====================================================================
      # Serializers
      # =====================================================================

      def serialize_message(message)
        {
          id: message.message_id,
          role: message.role,
          content: message.content.to_s.truncate(2000),
          sender: message.user&.name || message.agent&.name || "Unknown",
          sender_type: message.user.present? ? "user" : "agent",
          agent_type: message.agent&.agent_type,
          status: message.status,
          is_edited: message.respond_to?(:is_edited?) ? message.is_edited? : false,
          content_metadata: message.content_metadata.presence,
          created_at: message.created_at&.iso8601
        }
      end

      def serialize_conversation(conversation)
        team = conversation.agent_team
        conv_agent = conversation.agent
        {
          id: conversation.id,
          conversation_id: conversation.conversation_id,
          title: conversation.title,
          status: conversation.status,
          type: conversation.workspace_conversation? ? "workspace" : conversation.conversation_type,
          agent: conv_agent&.name,
          provider: conversation.provider&.name,
          team_name: team&.name,
          is_concierge: conv_agent&.respond_to?(:is_concierge?) ? conv_agent.is_concierge? : false,
          is_collaborative: conversation.is_collaborative,
          pinned: conversation.respond_to?(:pinned?) ? conversation.pinned? : false,
          tags: conversation.respond_to?(:tags) ? conversation.tags : [],
          message_count: conversation.message_count,
          last_activity_at: conversation.last_activity_at&.iso8601,
          created_at: conversation.created_at&.iso8601
        }
      end

      def serialize_session(session)
        {
          id: session.id,
          display_name: session.display_name || session.ai_agent&.name,
          agent: session.ai_agent ? {
            id: session.ai_agent.id,
            name: session.ai_agent.name,
            agent_type: session.ai_agent.agent_type,
            status: session.ai_agent.status
          } : nil,
          oauth_application: session.oauth_application ? {
            id: session.oauth_application.id,
            name: session.oauth_application.name
          } : nil,
          user: {
            id: session.user.id,
            name: session.user.name || session.user.email
          },
          last_activity_at: session.last_activity_at&.iso8601,
          created_at: session.created_at&.iso8601
        }
      end
    end
  end
end
