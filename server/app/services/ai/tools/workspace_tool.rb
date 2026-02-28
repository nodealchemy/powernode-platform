# frozen_string_literal: true

module Ai
  module Tools
    class WorkspaceTool < BaseTool
      REQUIRED_PERMISSION = "ai.conversations.create"

      def self.definition
        {
          name: "workspace",
          description: "Create and manage workspace conversations for multi-agent collaboration (user + MCP clients + concierge)",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_workspace, send_message, invite_agent, list_messages, list_workspaces, active_sessions" },
            name: { type: "string", required: false, description: "Workspace name (for create_workspace)" },
            agent_ids: { type: "array", required: false, description: "Agent IDs to include (for create_workspace)" },
            include_concierge: { type: "boolean", required: false, description: "Auto-add concierge agent (for create_workspace, default: false)" },
            conversation_id: { type: "string", required: false, description: "Workspace conversation ID (for send_message, invite_agent, list_messages)" },
            message: { type: "string", required: false, description: "Message content (for send_message)" },
            mentions: { type: "array", required: false, description: "Agent mentions for send_message — [{\"id\": \"...\", \"name\": \"...\"}]" },
            agent_id: { type: "string", required: false, description: "Agent ID (for invite_agent)" },
            limit: { type: "integer", required: false, description: "Max results (default 20)" }
          }
        }
      end

      def self.action_definitions
        {
          "create_workspace" => {
            description: "Create a workspace conversation with selected agents. The calling MCP client is automatically added.",
            parameters: {
              name: { type: "string", required: true, description: "Workspace name" },
              agent_ids: { type: "array", required: false, description: "Additional agent IDs to include" },
              include_concierge: { type: "boolean", required: false, description: "Auto-add concierge agent (default: false)" }
            }
          },
          "send_message" => {
            description: "Send a message to a workspace conversation attributed to this MCP client agent. " \
                         "Include mentions to @mention and notify specific agents in the workspace.",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Workspace conversation ID" },
              message: { type: "string", required: true, description: "Message content (include @AgentName in the text to mention them)" },
              mentions: { type: "array", required: false, description: "Array of agent mentions, each with 'id' and 'name' keys (e.g. [{\"id\": \"agent-uuid\", \"name\": \"Agent Name\"}])" }
            }
          },
          "invite_agent" => {
            description: "Invite an agent to a workspace conversation",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Workspace conversation ID" },
              agent_id: { type: "string", required: true, description: "Agent ID to invite (or 'concierge' for default concierge)" }
            }
          },
          "list_messages" => {
            description: "Retrieve messages from a workspace conversation",
            parameters: {
              conversation_id: { type: "string", required: true, description: "Workspace conversation ID" },
              limit: { type: "integer", required: false, description: "Max messages (default 20, max 100)" }
            }
          },
          "list_workspaces" => {
            description: "List workspace conversations the current user participates in",
            parameters: {
              limit: { type: "integer", required: false, description: "Max results (default 10)" }
            }
          },
          "active_sessions" => {
            description: "List active MCP client sessions that can be invited to workspaces",
            parameters: {}
          }
        }
      end

      protected

      def call(params)
        return { success: false, error: "User context required for workspace tools" } unless user

        case params[:action]
        when "create_workspace" then create_workspace(params)
        when "send_message" then send_workspace_message(params)
        when "invite_agent" then invite_agent(params)
        when "list_messages" then list_messages(params)
        when "list_workspaces" then list_workspaces(params)
        when "active_sessions" then list_active_sessions(params)
        else
          { success: false, error: "Unknown action: #{params[:action]}. Valid: create_workspace, send_message, invite_agent, list_messages, list_workspaces, active_sessions" }
        end
      end

      private

      def workspace_service
        @workspace_service ||= Ai::WorkspaceService.new(account: account, user: user)
      end

      def create_workspace(params)
        return { success: false, error: "name is required" } if params[:name].blank?

        agent_ids = Array(params[:agent_ids])

        # Auto-add the calling MCP client agent if present
        agent_ids.unshift(agent.id) if agent&.agent_type == "mcp_client" && !agent_ids.include?(agent.id)

        # Optionally add concierge
        if params[:include_concierge]
          concierge = account.ai_agents.default_concierge.first
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
        Rails.logger.error("[WorkspaceTool] create_workspace error: #{e.message}")
        { success: false, error: "Failed to create workspace: #{e.message}" }
      end

      def send_workspace_message(params)
        return { success: false, error: "conversation_id is required" } if params[:conversation_id].blank?
        return { success: false, error: "message is required" } if params[:message].blank?

        conversation = find_workspace_conversation(params[:conversation_id])
        return { success: false, error: "Workspace conversation not found" } unless conversation

        # Build content_metadata with structured mentions if provided
        metadata = {}
        if params[:mentions].present? && params[:mentions].is_a?(Array)
          metadata["mentions"] = params[:mentions].map { |m|
            { "id" => m["id"] || m[:id], "name" => m["name"] || m[:name] }
          }.select { |m| m["id"].present? && m["name"].present? }
        end

        # Auto-resolve fuzzy agent references when no structured mentions provided
        # Handles cases where LLMs write "to Claude Code" instead of "@Claude Code (powernode) #1"
        if metadata["mentions"].blank? && conversation.agent_team
          fuzzy = resolve_fuzzy_mentions(params[:message], conversation.agent_team)
          metadata["mentions"] = fuzzy if fuzzy.present?
        end

        # Send message attributed to this MCP client agent (not the user)
        sending_agent = agent&.agent_type == "mcp_client" ? agent : nil
        message = conversation.add_message(
          "assistant",
          params[:message],
          agent: sending_agent,
          content_metadata: metadata.presence
        )

        # Dispatch responses from @mentioned workspace agents (mirrors conversations_controller logic)
        dispatched_agents = dispatch_mentioned_responses(conversation, message, metadata)

        {
          success: true,
          conversation_id: conversation.conversation_id,
          message_id: message.message_id,
          sender: sending_agent&.name || "Unknown",
          dispatched_to: dispatched_agents
        }
      rescue StandardError => e
        Rails.logger.error("[WorkspaceTool] send_message error: #{e.message}")
        { success: false, error: "Failed to send message: #{e.message}" }
      end

      def invite_agent(params)
        return { success: false, error: "conversation_id is required" } if params[:conversation_id].blank?
        return { success: false, error: "agent_id is required" } if params[:agent_id].blank?

        conversation = find_workspace_conversation(params[:conversation_id])
        return { success: false, error: "Workspace conversation not found" } unless conversation

        target_agent = if params[:agent_id] == "concierge"
                         account.ai_agents.default_concierge.first
        else
                         account.ai_agents.find_by(id: params[:agent_id])
        end
        return { success: false, error: "Agent not found" } unless target_agent

        workspace_service.invite_agent(workspace_conversation: conversation, agent: target_agent)

        {
          success: true,
          conversation_id: conversation.conversation_id,
          invited_agent: { id: target_agent.id, name: target_agent.name, agent_type: target_agent.agent_type }
        }
      rescue StandardError => e
        Rails.logger.error("[WorkspaceTool] invite_agent error: #{e.message}")
        { success: false, error: "Failed to invite agent: #{e.message}" }
      end

      def list_messages(params)
        return { success: false, error: "conversation_id is required" } if params[:conversation_id].blank?

        conversation = find_workspace_conversation(params[:conversation_id])
        return { success: false, error: "Workspace conversation not found" } unless conversation

        limit = (params[:limit] || 20).to_i.clamp(1, 100)
        messages = conversation.messages.not_deleted.ordered.includes(:user, :agent).last(limit)

        {
          success: true,
          conversation_id: conversation.conversation_id,
          count: messages.size,
          messages: messages.map { |m| serialize_message(m) }
        }
      end

      def list_workspaces(params)
        limit = (params[:limit] || 10).to_i.clamp(1, 50)
        workspaces = workspace_service.list_workspaces.limit(limit)

        {
          success: true,
          count: workspaces.size,
          workspaces: workspaces.map { |c| serialize_workspace(c) }
        }
      end

      def list_active_sessions(_params)
        sessions = workspace_service.active_mcp_sessions

        {
          success: true,
          count: sessions.size,
          sessions: sessions.map { |s| serialize_session(s) }
        }
      end

      # --- Dispatch ---

      # Resolve @mentions from metadata or message text and dispatch workspace agent responses.
      # For non-MCP agents (including the concierge), enqueues AiWorkspaceResponseJob.
      # For MCP client agents, broadcasts SSE notifications.
      #
      # Mention resolution order:
      # 1. Structured metadata mentions (explicit {id, name} pairs)
      # 2. Text-based @mentions parsed from message content (matched against workspace members)
      def dispatch_mentioned_responses(conversation, trigger_message, metadata)
        team = conversation.agent_team
        return [] unless team&.team_type == "workspace"

        # Try structured mentions first, fall back to text parsing
        mentions = metadata.dig("mentions")
        mentioned_ids = if mentions.present?
          mentioned_names = mentions.map { |m| m["name"] }.compact
          team.members.by_agent_names(mentioned_names).pluck(:ai_agent_id)
        else
          resolve_text_mentions(trigger_message.content, team)
        end

        return [] if mentioned_ids.empty?

        # Exclude the primary agent only when it is the sender (avoids self-dispatch).
        # When an MCP client @mentions the primary agent, it must still be dispatched
        # because ConciergeService only runs for user messages via the controller path.
        if agent&.id == conversation.ai_agent_id
          mentioned_ids -= [conversation.ai_agent_id].compact
        end

        return [] if mentioned_ids.empty?

        dispatched = []

        # Dispatch to non-MCP agents via worker jobs
        team.members.includes(:agent).each do |member|
          a = member.agent
          next unless mentioned_ids.include?(a.id)
          next if a.id == agent&.id # Don't dispatch back to the sending agent
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
          Rails.logger.warn("[WorkspaceTool] Failed to dispatch response for agent #{a.id}: #{e.message}")
        end

        dispatched
      end

      # Send SSE notification to an MCP client agent
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
        }.to_json

        sessions.find_each do |session|
          ActionCable.server.pubsub.broadcast("mcp_session:#{session.session_token}", notification)
        end
      rescue StandardError => e
        Rails.logger.warn("[WorkspaceTool] Failed to notify MCP client #{target_agent.id}: #{e.message}")
      end

      # Parse @mentions from message text by matching against workspace team member names.
      # Returns an array of agent IDs for members whose names appear after @ in the text.
      # Handles multi-word names like "@Claude Code (powernode) #1" by checking longest match first.
      def resolve_text_mentions(content, team)
        return [] if content.blank?

        members = team.members.includes(:agent).to_a
        # Sort by name length descending so longer names match first (prevents partial matches)
        members.sort_by! { |m| -(m.agent&.name&.length || 0) }

        mentioned_ids = []
        members.each do |member|
          name = member.agent&.name
          next if name.blank?
          # Check for @AgentName in the text (case-sensitive, as required by concierge prompt)
          mentioned_ids << member.ai_agent_id if content.include?("@#{name}")
        end

        mentioned_ids.uniq
      end

      # Fuzzy match agent names in message content without requiring @ prefix.
      # Matches against the first word(s) of each member's agent name (case-insensitive).
      # E.g. "Claude Code" matches "Claude Code (powernode) #1", "Powernode Assistant" matches exactly.
      # Returns structured mention array [{id:, name:}] suitable for content_metadata.
      def resolve_fuzzy_mentions(content, team)
        return [] if content.blank?

        downcased = content.downcase
        members = team.members.includes(:agent).where.not(ai_agent_id: agent&.id).to_a
        mentions = []

        members.each do |member|
          name = member.agent&.name
          next if name.blank?

          # Try exact name first, then base name (before parentheses/hash), then first two words
          candidates = [name]
          candidates << name.sub(/\s*\(.*$/, "").strip if name.include?("(")
          candidates << name.split(/\s+/).first(2).join(" ") if name.split(/\s+/).length > 2

          matched = candidates.any? { |c| downcased.include?(c.downcase) }
          mentions << { "id" => member.ai_agent_id, "name" => name } if matched
        end

        mentions.uniq { |m| m["id"] }
      end

      # --- Helpers ---

      def find_workspace_conversation(conversation_id)
        base = Ai::Conversation.where(account: account)
          .joins(:agent_team)
          .where(ai_agent_teams: { team_type: "workspace" })

        # Try by DB id, then by conversation_id UUID
        result = base.find_by(id: conversation_id) ||
                 base.find_by(conversation_id: conversation_id)
        return result if result

        # Fallback: LLMs sometimes pass the workspace team name (or a substring)
        # instead of the UUID. Use partial case-insensitive match to recover
        # (e.g. "powernode" matches "Powernode Workspace").
        # Only attempt for non-empty, non-UUID strings with 3+ chars.
        sanitized = conversation_id.to_s.strip
        if sanitized.length >= 3 && !sanitized.match?(/\A[0-9a-f-]{36}\z/i)
          base.where("ai_agent_teams.name ILIKE ?", "%#{sanitized}%")
              .order(created_at: :desc).first
        end
      end

      def serialize_message(message)
        {
          id: message.message_id,
          role: message.role,
          content: message.content.to_s.truncate(2000),
          sender: message.user&.name || message.agent&.name || "Unknown",
          sender_type: message.user.present? ? "user" : "agent",
          agent_type: message.agent&.agent_type,
          created_at: message.created_at&.iso8601
        }
      end

      def serialize_workspace(conversation)
        team = conversation.agent_team
        {
          conversation_id: conversation.conversation_id,
          title: conversation.title,
          status: conversation.status,
          team_name: team&.name,
          member_count: team&.members&.count || 0,
          message_count: conversation.message_count,
          last_activity_at: conversation.last_activity_at&.iso8601
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
