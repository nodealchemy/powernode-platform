# frozen_string_literal: true

module Chat
  class MessageRouter
    class RoutingError < StandardError; end
    class ProcessingError < StandardError; end

    def initialize(channel)
      @channel = channel
      @session_manager = SessionManager.new(channel)
    end

    # Route incoming message through the system
    def route_inbound(session:, content:, message_type: "text", platform_message_id: nil, metadata: {})
      # Check rate limiting
      check_rate_limit!

      # Create chat message record
      message = session.add_inbound_message(
        content: content,
        message_type: message_type,
        platform_message_id: platform_message_id,
        metadata: metadata
      )

      # Bridge to team channel if linked
      if @channel.bridged?
        Ai::TeamChannelBridgeService.new.sync_inbound_to_team_channel(message)
      end

      # Route to A2A for processing
      task = submit_to_agent(session, message)

      {
        message: message,
        task: task,
        status: "processing"
      }
    rescue SessionManager::BlockedUserError => e
      Rails.logger.info "Blocked message from user: #{e.message}"
      { status: "blocked", reason: e.message }
    rescue SessionManager::RateLimitError => e
      Rails.logger.warn "Rate limited: #{e.message}"
      { status: "rate_limited", reason: e.message }
    end

    # Route outbound message to platform
    def route_outbound(session:, content:, message_type: "text", ai_message: nil)
      # Create outbound message record
      message = session.add_outbound_message(
        content: content,
        message_type: message_type,
        ai_message: ai_message
      )

      # Send via platform adapter
      begin
        adapter = get_adapter
        platform_message_id = adapter.send_message(session, content)

        message.mark_sent!(platform_message_id)

        {
          message: message,
          status: "sent",
          platform_message_id: platform_message_id
        }
      rescue Chat::BaseAdapter::DeliveryError => e
        message.mark_failed!(e.message)
        raise ProcessingError, "Failed to deliver message: #{e.message}"
      end
    end

    # Handle A2A task completion and send response
    def handle_task_completion(task)
      return unless task.chat_session_id.present?

      session = Chat::Session.find(task.chat_session_id)

      # Extract response content
      response_content = extract_response_content(task)
      return if response_content.blank?

      # Send response through platform
      route_outbound(
        session: session,
        content: response_content,
        ai_message: task.output&.dig("ai_message")
      )
    rescue StandardError => e
      Rails.logger.error "Failed to route task completion: #{e.message}"
    end

    # Process typing indicator
    def send_typing_indicator(session, typing: true)
      adapter = get_adapter
      adapter.send_typing_indicator(session, typing: typing)
    rescue StandardError => e
      Rails.logger.debug "Failed to send typing indicator: #{e.message}"
    end

    # Mark message as read on platform
    def mark_read(session, platform_message_id)
      adapter = get_adapter
      adapter.mark_read(session, platform_message_id)
    rescue StandardError => e
      Rails.logger.debug "Failed to mark read: #{e.message}"
    end

    private

    def check_rate_limit!
      if @channel.rate_limited?
        raise SessionManager::RateLimitError, "Channel rate limit exceeded"
      end

      @channel.increment_rate_counter!
    end

    def submit_to_agent(session, message)
      agent = resolve_agent(session, message)

      return nil unless agent.present?

      # Build A2A task with personality context
      a2a_service = Ai::A2a::Service.new(
        account: @channel.account,
        user: @channel.account.owner
      )

      task = a2a_service.submit_task(
        agent: agent,
        message: build_agent_message(session, message),
        metadata: {
          chat_channel_id: @channel.id,
          chat_session_id: session.id,
          chat_message_id: message.id,
          platform: @channel.platform,
          platform_user_id: session.platform_user_id,
          agent_personality: @channel.configuration&.dig("agent_personality")
        }
      )

      # Link task to message
      message.update_column(:a2a_task_id, task.id) if task.persisted?

      task
    end

    # Resolve agent using skill-based routing or fallback chain
    def resolve_agent(session, message)
      # 1. Session-assigned agent takes priority
      return session.assigned_agent if session.assigned_agent.present?

      # 2. Skill-based routing if configured
      routing_config = @channel.configuration&.dig("routing_config")
      if routing_config && routing_config["routing_strategy"] == "skill_based"
        routed_agent = route_by_skill(message.content_for_ai, routing_config)
        return routed_agent if routed_agent
      end

      # 3. Fall back to default agent
      @channel.default_agent
    end

    # Route to a specific agent based on message content matching skill routes
    def route_by_skill(content, routing_config)
      routes = routing_config["skill_routes"]
      return nil if routes.blank?

      text = content.to_s.downcase

      matched = routes
        .sort_by { |r| -(r["priority"] || 0) }
        .find do |route|
          case route["match_type"]
          when "keyword"
            route["pattern"].to_s.split(",").any? { |kw| text.include?(kw.strip.downcase) }
          when "regex"
            text.match?(Regexp.new(route["pattern"], Regexp::IGNORECASE))
          else
            false
          end
        end

      return nil unless matched

      agent = Ai::Agent.find_by(id: matched["agent_id"], account: @channel.account)
      Rails.logger.debug "[MessageRouter] Skill-routed to agent #{agent&.name} via #{matched['match_type']} pattern"
      agent
    end

    def build_agent_message(session, message)
      {
        role: "user",
        parts: [
          { type: "text", text: message.content_for_ai }
        ],
        context: session.context_for_agent
      }
    end

    def extract_response_content(task)
      return nil unless task.status == "completed"

      # Try different output formats
      output = task.output

      if output.is_a?(Hash)
        output["response"] || output["content"] || output["text"] || output["message"]
      elsif output.is_a?(String)
        output
      else
        task.artifacts&.first&.dig("content")
      end
    end

    def get_adapter
      @adapter ||= AdapterFactory.for_channel(@channel)
    end
  end

  # Factory for creating platform adapters
  class AdapterFactory
    def self.for_channel(channel)
      case channel.platform
      when "telegram"
        Adapters::TelegramAdapter.new(channel)
      when "discord"
        Adapters::DiscordAdapter.new(channel)
      when "slack"
        Adapters::SlackAdapter.new(channel)
      when "whatsapp"
        Adapters::WhatsappAdapter.new(channel)
      when "mattermost"
        Adapters::MattermostAdapter.new(channel)
      else
        raise RoutingError, "No adapter for platform: #{channel.platform}"
      end
    end
  end
end
