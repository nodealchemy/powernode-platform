# frozen_string_literal: true

module Ai
  module Acp
    # ACP (Agent Communication Protocol) adapter
    #
    # Maps ACP REST-based, agent-centric protocol to existing A2A infrastructure.
    # ACP uses agent profiles + message-based communication vs A2A's JSON-RPC + task model.
    #
    # Key differences from A2A:
    #   - REST endpoints (not JSON-RPC)
    #   - Agent profiles (richer than agent cards)
    #   - Message-based (send/receive messages, not tasks)
    #   - Event-driven (SSE event streams)
    #   - Capability negotiation (runtime capability exchange)
    class ProtocolService
      ACP_VERSION = "1.0"

      SUPPORTED_MESSAGE_TYPES = %w[text request response event].freeze

      class ProtocolError < StandardError
        attr_reader :code, :http_status

        def initialize(message, code: "ACP_ERROR", http_status: 400)
          @code = code
          @http_status = http_status
          super(message)
        end
      end

      def initialize(account:)
        @account = account
        @a2a_service = A2a::ProtocolService.new(account: account)
      end

      # ==================== Agent Profiles ====================

      # GET /acp/agents — List available agents with ACP profile format
      def list_agents(filter: {})
        scope = Ai::AgentCard.for_discovery(@account.id)

        scope = scope.where("name ILIKE ?", "%#{filter[:query]}%") if filter[:query].present?

        if filter[:capabilities].present?
          cap_list = Array(filter[:capabilities])
          scope = scope.select do |card|
            agent_capabilities = extract_capabilities(card)
            (cap_list & agent_capabilities).any?
          end
        end

        agents = scope.map { |card| to_acp_profile(card) }

        success_result(
          agents: agents,
          total: agents.size,
          protocol: "acp",
          version: ACP_VERSION
        )
      rescue StandardError => e
        log_error("list_agents", e)
        error_result(e.message, code: "DISCOVERY_ERROR")
      end

      # GET /acp/agents/:id — Get single agent profile
      def get_agent_profile(agent_id:)
        card = find_agent_card(agent_id)
        return error_result("Agent not found", code: "AGENT_NOT_FOUND", http_status: 404) unless card

        success_result(agent: to_acp_profile(card))
      rescue StandardError => e
        log_error("get_agent_profile", e)
        error_result(e.message, code: "PROFILE_ERROR")
      end

      # ==================== Capability Negotiation ====================

      # POST /acp/agents/:id/negotiate — Exchange capabilities at runtime
      def negotiate_capabilities(agent_id:, offered_capabilities:, required_capabilities: [])
        card = find_agent_card(agent_id)
        return error_result("Agent not found", code: "AGENT_NOT_FOUND", http_status: 404) unless card

        agent_caps = extract_capabilities(card)
        offered = Array(offered_capabilities)
        required = Array(required_capabilities)

        # Check which required capabilities the agent supports
        matched = required & agent_caps
        unmatched = required - agent_caps

        # Determine negotiation outcome
        compatible = unmatched.empty?

        Rails.logger.info "[ACP] Capability negotiation for #{card.name}: " \
          "compatible=#{compatible}, matched=#{matched.size}/#{required.size}"

        success_result(
          agent_id: card.id,
          compatible: compatible,
          matched_capabilities: matched,
          unmatched_capabilities: unmatched,
          agent_capabilities: agent_caps,
          offered_capabilities: offered,
          negotiated_at: Time.current.iso8601
        )
      rescue StandardError => e
        log_error("negotiate_capabilities", e)
        error_result(e.message, code: "NEGOTIATION_ERROR")
      end

      # ==================== Messages ====================

      # POST /acp/agents/:id/messages — Send message to agent (maps to A2A task)
      def send_message(to_agent_id:, from_agent_id: nil, message:, metadata: {})
        to_card = find_agent_card(to_agent_id)
        return error_result("Target agent not found", code: "AGENT_NOT_FOUND", http_status: 404) unless to_card

        message_type = message[:type] || message["type"] || "text"
        unless SUPPORTED_MESSAGE_TYPES.include?(message_type)
          return error_result(
            "Unsupported message type: #{message_type}",
            code: "INVALID_MESSAGE_TYPE"
          )
        end

        # Map ACP message to A2A task format
        a2a_params = map_message_to_task(message, metadata)

        result = @a2a_service.send_task(
          from_agent: from_agent_id,
          to_agent: to_agent_id,
          task_params: a2a_params
        )

        if result[:success]
          task_data = result[:task]
          success_result(
            message_id: task_data[:id] || task_data["id"],
            status: map_task_status_to_acp(task_data[:status] || task_data["status"]),
            agent_id: to_card.id,
            sent_at: Time.current.iso8601,
            protocol: "acp"
          )
        else
          error_result(result[:error], code: result[:code] || "SEND_ERROR")
        end
      rescue StandardError => e
        log_error("send_message", e)
        error_result(e.message, code: "MESSAGE_ERROR")
      end

      # GET /acp/messages/:id — Get message status (maps to A2A task status)
      def get_message(message_id:)
        result = @a2a_service.get_task(task_id: message_id)

        if result[:success]
          task_data = result[:task]
          success_result(message: to_acp_message(task_data))
        else
          error_result(result[:error], code: "MESSAGE_NOT_FOUND", http_status: 404)
        end
      rescue StandardError => e
        log_error("get_message", e)
        error_result(e.message, code: "MESSAGE_ERROR")
      end

      # POST /acp/messages/:id/cancel — Cancel a message (maps to A2A task cancel)
      def cancel_message(message_id:, reason: nil)
        result = @a2a_service.cancel_task(task_id: message_id, reason: reason)

        if result[:success]
          success_result(
            message_id: message_id,
            status: "cancelled",
            reason: reason,
            cancelled_at: Time.current.iso8601
          )
        else
          error_result(result[:error], code: result[:code] || "CANCEL_ERROR")
        end
      rescue StandardError => e
        log_error("cancel_message", e)
        error_result(e.message, code: "CANCEL_ERROR")
      end

      # ==================== Events ====================

      # GET /acp/agents/:id/events — Get event stream for agent
      def get_agent_events(agent_id:, since: nil, limit: 50)
        card = find_agent_card(agent_id)
        return error_result("Agent not found", code: "AGENT_NOT_FOUND", http_status: 404) unless card

        # Fetch recent tasks for this agent and map to ACP events
        tasks = Ai::A2aTask.where(account_id: @account.id, to_agent_id: card.ai_agent_id)
                           .order(created_at: :desc)
                           .limit(limit)

        tasks = tasks.where("created_at > ?", Time.parse(since)) if since.present?

        events = tasks.flat_map { |task| task_to_acp_events(task) }
                      .sort_by { |e| e[:timestamp] }
                      .last(limit)

        success_result(
          events: events,
          agent_id: card.id,
          total: events.size,
          has_more: tasks.size >= limit
        )
      rescue StandardError => e
        log_error("get_agent_events", e)
        error_result(e.message, code: "EVENTS_ERROR")
      end

      # ==================== Protocol Info ====================

      # GET /acp — Protocol information endpoint
      def protocol_info
        success_result(
          protocol: "acp",
          version: ACP_VERSION,
          supported_protocols: %w[acp a2a],
          supported_message_types: SUPPORTED_MESSAGE_TYPES,
          endpoints: {
            agents: "/api/v1/ai/acp/agents",
            messages: "/api/v1/ai/acp/messages",
            events: "/api/v1/ai/acp/agents/:id/events",
            negotiate: "/api/v1/ai/acp/agents/:id/negotiate"
          },
          capabilities: {
            discovery: true,
            capability_negotiation: true,
            streaming: true,
            push_notifications: true,
            federation: true
          }
        )
      end

      private

      def find_agent_card(identifier)
        Ai::AgentCard.for_discovery(@account.id).find_by(id: identifier) ||
          Ai::AgentCard.for_discovery(@account.id).find_by(name: identifier)
      end

      # Map an A2A AgentCard to ACP agent profile format
      def to_acp_profile(card)
        capabilities = extract_capabilities(card)

        {
          id: card.id,
          name: card.name,
          description: card.description,
          version: card.version || "1.0",
          protocol: "acp",
          protocol_version: ACP_VERSION,
          status: card.status || "active",
          capabilities: capabilities,
          input_modes: extract_input_modes(card),
          output_modes: extract_output_modes(card),
          authentication: card.authentication || {},
          metadata: {
            created_at: card.created_at&.iso8601,
            updated_at: card.updated_at&.iso8601,
            task_count: card.task_count,
            success_rate: card.success_rate,
            avg_response_time_ms: card.avg_response_time_ms
          },
          # ACP-specific fields
          endpoint: "/api/v1/ai/acp/agents/#{card.id}/messages",
          events_endpoint: "/api/v1/ai/acp/agents/#{card.id}/events",
          negotiate_endpoint: "/api/v1/ai/acp/agents/#{card.id}/negotiate"
        }
      end

      # Map ACP message to A2A task parameters
      def map_message_to_task(message, metadata)
        content = message[:content] || message["content"] || ""
        message_type = message[:type] || message["type"] || "text"

        parts = case message_type
                when "text"
                  [{ "type" => "text", "text" => content }]
                when "request"
                  [{ "type" => "text", "text" => content }]
                when "event"
                  [{ "type" => "text", "text" => content }]
                else
                  [{ "type" => "text", "text" => content }]
                end

        # Add any additional data parts
        if message[:data].present?
          parts << { "type" => "data", "data" => message[:data] }
        end

        {
          message: {
            role: "user",
            parts: parts
          },
          metadata: (metadata || {}).merge(
            "acp_message_type" => message_type,
            "acp_protocol_version" => ACP_VERSION
          )
        }
      end

      # Map A2A task to ACP message format
      def to_acp_message(task_data)
        {
          id: task_data[:id] || task_data["id"],
          type: task_data.dig(:metadata, "acp_message_type") ||
                task_data.dig("metadata", "acp_message_type") || "response",
          status: map_task_status_to_acp(task_data[:status] || task_data["status"]),
          content: extract_task_content(task_data),
          agent_id: task_data[:to_agent_id] || task_data["to_agent_id"],
          created_at: task_data[:created_at] || task_data["created_at"],
          updated_at: task_data[:updated_at] || task_data["updated_at"],
          metadata: task_data[:metadata] || task_data["metadata"] || {}
        }
      end

      # Map A2A task status to ACP status
      def map_task_status_to_acp(status)
        case status.to_s
        when "pending" then "queued"
        when "submitted" then "queued"
        when "working", "active" then "processing"
        when "input_required" then "waiting"
        when "completed" then "delivered"
        when "failed" then "failed"
        when "canceled", "cancelled" then "cancelled"
        else "unknown"
        end
      end

      # Map A2A task to ACP event stream
      def task_to_acp_events(task)
        events = []

        events << {
          id: "evt_#{task.id}_created",
          type: "message.received",
          agent_id: task.to_agent_id,
          message_id: task.task_id || task.id,
          status: map_task_status_to_acp(task.status),
          timestamp: task.created_at&.iso8601,
          data: {
            from_agent_id: task.from_agent_id,
            message_type: task.metadata&.dig("acp_message_type") || "text"
          }
        }

        if task.status.in?(%w[completed failed canceled cancelled])
          events << {
            id: "evt_#{task.id}_completed",
            type: task.status == "completed" ? "message.delivered" : "message.failed",
            agent_id: task.to_agent_id,
            message_id: task.task_id || task.id,
            status: map_task_status_to_acp(task.status),
            timestamp: task.updated_at&.iso8601,
            data: {
              duration_ms: task.duration_ms,
              error: task.error_message
            }.compact
          }
        end

        events
      end

      def extract_capabilities(card)
        skills = card.capabilities&.dig("skills") || []
        skills.map { |s| s.is_a?(Hash) ? (s["id"] || s["name"]) : s.to_s }.compact
      end

      def extract_input_modes(card)
        modes = ["text"]
        capabilities = card.capabilities || {}
        modes << "file" if capabilities["accepts_files"]
        modes << "image" if capabilities["accepts_images"]
        modes << "audio" if capabilities["accepts_audio"]
        modes
      end

      def extract_output_modes(card)
        modes = ["text"]
        capabilities = card.capabilities || {}
        modes << "file" if capabilities["produces_files"]
        modes << "image" if capabilities["produces_images"]
        modes << "structured" if capabilities["structured_output"]
        modes
      end

      def extract_task_content(task_data)
        output = task_data[:output] || task_data["output"]
        return "" unless output

        if output.is_a?(Hash)
          output["text"] || output[:text] || output.to_json
        else
          output.to_s
        end
      end

      def success_result(data = {})
        { success: true }.merge(data)
      end

      def error_result(message, code: "ACP_ERROR", http_status: 400)
        { success: false, error: message, code: code, http_status: http_status }
      end

      def log_error(method, error)
        Rails.logger.error "[ACP Protocol] #{method} error: #{error.message}"
      end
    end
  end
end
