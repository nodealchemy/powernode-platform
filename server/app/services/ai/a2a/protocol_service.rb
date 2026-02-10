# frozen_string_literal: true

module Ai
  module A2a
    class ProtocolService
      A2A_VERSION = "0.3"
      SUPPORTED_METHODS = %w[
        tasks/send tasks/get tasks/cancel tasks/sendSubscribe
        tasks/pushNotification/set tasks/pushNotification/get tasks/resubscribe
      ].freeze

      class ProtocolError < StandardError
        attr_reader :code, :http_status

        def initialize(message, code: "PROTOCOL_ERROR", http_status: 400)
          @code = code
          @http_status = http_status
          super(message)
        end
      end

      def initialize(account:)
        @account = account
      end

      # Generate .well-known/agent.json response for an agent
      def agent_card(agent_id:)
        card = find_agent_card(agent_id)
        return error_result("Agent card not found") unless card

        Rails.logger.info "[A2A Protocol] Agent card requested: #{card.name}"
        success_result(agent_card: card.to_a2a_json.merge(protocolVersion: A2A_VERSION))
      rescue StandardError => e
        log_error("agent_card", e)
        error_result(e.message, code: "DISCOVERY_ERROR")
      end

      # Discover agents that can handle a task
      def discover_agents(task_description:, capabilities: nil, visibility: :internal)
        Rails.logger.info "[A2A Protocol] Discovering agents for: #{task_description.truncate(100)}"

        matched_cards = Ai::AgentCard.find_agents_for_task(
          task_description, account_id: @account.id, limit: 20
        )

        if capabilities.present?
          cap_list = Array(capabilities)
          matched_cards = matched_cards.select do |card|
            (cap_list & extract_skill_ids(card)).any?
          end
        end

        ranked = matched_cards.map do |card|
          { agent_card: card.to_a2a_json, id: card.id, name: card.name,
            relevance_score: compute_relevance(card, task_description),
            success_rate: card.success_rate, avg_response_time_ms: card.avg_response_time_ms }
        end.sort_by { |a| -(a[:relevance_score] || 0) }

        if visibility.to_s.in?(%w[public internal])
          ranked.concat(discover_federated_agents(task_description))
        end

        Rails.logger.info "[A2A Protocol] Discovered #{ranked.size} agents"
        success_result(agents: ranked, total: ranked.size, protocol_version: A2A_VERSION)
      rescue StandardError => e
        log_error("discover_agents", e)
        error_result(e.message, code: "DISCOVERY_ERROR")
      end

      # A2A tasks/send
      def send_task(from_agent:, to_agent:, task_params:)
        to_card = resolve_agent_card(to_agent)
        return error_result("Target agent not found: #{to_agent}") unless to_card

        from_card = from_agent.present? ? resolve_agent_card(from_agent) : nil

        auth = validate_agent_communication(from_card, to_card)
        return auth unless auth[:success]

        validation = validate_task_params(task_params)
        return validation unless validation[:success]

        message = normalize_message(task_params[:message] || task_params["message"])
        task = Ai::A2aTask.create!(
          account: @account,
          from_agent_id: from_card&.ai_agent_id, from_agent_card_id: from_card&.id,
          to_agent_id: to_card.ai_agent_id, to_agent_card_id: to_card.id,
          message: message, input: extract_input(task_params),
          metadata: build_task_metadata(task_params),
          is_external: false, max_retries: task_params[:max_retries] || 3
        )

        Rails.logger.info "[A2A Protocol] Task created: #{task.task_id} (#{from_card&.name} -> #{to_card.name})"
        enqueue_task_execution(task)
        success_result(task: task.to_a2a_json)
      rescue Ai::A2aTask::InvalidTransitionError => e
        error_result(e.message, code: "INVALID_TRANSITION")
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.message, code: "INVALID_TASK")
      rescue StandardError => e
        log_error("send_task", e)
        error_result(e.message, code: "TASK_SEND_ERROR")
      end

      # A2A tasks/get
      def get_task(task_id:, history_length: nil)
        task = find_task(task_id)
        return error_result("Task not found: #{task_id}", code: "TASK_NOT_FOUND") unless task

        task_json = task.to_a2a_json
        if history_length.present? && history_length.to_i >= 0
          task_json[:history] = (task_json[:history] || []).last(history_length.to_i)
        end
        success_result(task: task_json)
      rescue StandardError => e
        log_error("get_task", e)
        error_result(e.message, code: "TASK_GET_ERROR")
      end

      # A2A tasks/cancel
      def cancel_task(task_id:, reason: nil)
        task = find_task(task_id)
        return error_result("Task not found: #{task_id}", code: "TASK_NOT_FOUND") unless task
        unless task.can_cancel?
          return error_result("Cannot cancel task in #{task.status} state", code: "INVALID_TRANSITION")
        end

        task.cancel!(reason: reason)
        Rails.logger.info "[A2A Protocol] Task cancelled: #{task.task_id}"
        notify_push_subscribers(task, task.events.last)
        success_result(task: task.to_a2a_json)
      rescue Ai::A2aTask::InvalidTransitionError => e
        error_result(e.message, code: "INVALID_TRANSITION")
      rescue StandardError => e
        log_error("cancel_task", e)
        error_result(e.message, code: "TASK_CANCEL_ERROR")
      end

      # A2A tasks/sendSubscribe - resubscribe to existing task
      def subscribe_to_task(task_id:, &block)
        task = find_task(task_id)
        return error_result("Task not found: #{task_id}", code: "TASK_NOT_FOUND") unless task

        Rails.logger.info "[A2A Protocol] Subscribing to task: #{task.task_id}"
        task.events.chronological.each { |event| block.call(event.to_sse_json) } if block

        success_result(
          task_id: task.task_id, channel: "a2a_task_#{task.task_id}",
          status: task.a2a_status, protocol_version: A2A_VERSION
        )
      rescue StandardError => e
        log_error("subscribe_to_task", e)
        error_result(e.message, code: "SUBSCRIBE_ERROR")
      end

      # A2A tasks/sendSubscribe - create task with streaming
      def send_task_streaming(from_agent:, to_agent:, task_params:, &block)
        result = send_task(from_agent: from_agent, to_agent: to_agent, task_params: task_params)
        return result unless result[:success]

        task = find_task(result[:task][:id])
        return error_result("Task creation failed") unless task

        Rails.logger.info "[A2A Protocol] Streaming task: #{task.task_id}"
        if block
          block.call(id: "evt_stream_start", type: "task.status",
                     data: { taskId: task.task_id, status: task.a2a_status }.to_json)
        end
        success_result(task: task.to_a2a_json, channel: "a2a_task_#{task.task_id}", streaming: true)
      rescue StandardError => e
        log_error("send_task_streaming", e)
        error_result(e.message, code: "STREAMING_ERROR")
      end

      # A2A tasks/pushNotification/set
      def set_push_notification(task_id:, webhook_url:, auth_token: nil)
        task = find_task(task_id)
        return error_result("Task not found: #{task_id}", code: "TASK_NOT_FOUND") unless task
        return error_result("Invalid webhook URL", code: "INVALID_WEBHOOK_URL") unless valid_url?(webhook_url)

        config = { "url" => webhook_url, "enabled" => true, "configured_at" => Time.current.iso8601 }
        config["auth_token_digest"] = Digest::SHA256.hexdigest(auth_token) if auth_token.present?
        task.update!(push_notification_config: config)

        Rails.logger.info "[A2A Protocol] Push notification configured for task: #{task.task_id}"
        success_result(task_id: task.task_id, push_notification: { url: webhook_url, enabled: true })
      rescue StandardError => e
        log_error("set_push_notification", e)
        error_result(e.message, code: "PUSH_NOTIFICATION_ERROR")
      end

      # A2A tasks/pushNotification/get
      def get_push_notification(task_id:)
        task = find_task(task_id)
        return error_result("Task not found: #{task_id}", code: "TASK_NOT_FOUND") unless task

        config = task.push_notification_config || {}
        success_result(task_id: task.task_id, push_notification: {
          url: config["url"], enabled: config["enabled"] || false,
          configured_at: config["configured_at"]
        }.compact)
      rescue StandardError => e
        log_error("get_push_notification", e)
        error_result(e.message, code: "PUSH_NOTIFICATION_ERROR")
      end

      # Register a federation partner
      def register_federation(partner_url:, auth_config:)
        Rails.logger.info "[A2A Protocol] Registering federation partner: #{partner_url}"
        return error_result("Invalid partner URL", code: "INVALID_PARTNER_URL") unless valid_url?(partner_url)

        existing = FederationPartner.find_by(account_id: @account.id, endpoint_url: partner_url)
        if existing&.active?
          return success_result(partner: existing.partner_summary, message: "Already registered")
        end

        partner = existing || FederationPartner.new(
          account: @account, endpoint_url: partner_url,
          name: auth_config[:organization_name] || URI.parse(partner_url).host,
          organization_id: auth_config[:organization_id] || SecureRandom.uuid,
          status: "pending", trust_level: 1,
          max_requests_per_hour: auth_config[:max_requests_per_hour] || 100,
          tls_config: { "verify_mode" => auth_config[:verify_mode] || "peer",
                        "ca_cert" => auth_config[:ca_cert],
                        "contact_email" => auth_config[:contact_email] }.compact
        )
        return error_result(partner.errors.full_messages.join(", "), code: "REGISTRATION_ERROR") unless partner.save

        verification = partner.verify_connection!
        Rails.logger.info "[A2A Protocol] Partner #{partner.name} verified=#{verification[:success]}"

        success_result(partner: partner.partner_summary, verified: verification[:success],
                       federation_token: partner.regenerate_token!)
      rescue StandardError => e
        log_error("register_federation", e)
        error_result(e.message, code: "FEDERATION_ERROR")
      end

      # Sync agent cards with federation partners
      def sync_federation(partner_id: nil)
        partners = if partner_id.present?
                     p = FederationPartner.find_by(id: partner_id, account_id: @account.id)
                     return error_result("Partner not found", code: "PARTNER_NOT_FOUND") unless p
                     [p]
                   else
                     FederationPartner.where(account_id: @account.id).active
                   end
        return success_result(message: "No active federation partners", synced: 0) if partners.empty?

        Rails.logger.info "[A2A Protocol] Syncing #{partners.size} federation partner(s)"
        results = partners.map do |partner|
          r = partner.sync_agents!
          { partner_id: partner.id, partner_name: partner.name,
            success: r[:success], synced: r[:synced] || 0, errors: r[:errors] || r[:error] }
        end

        success_result(results: results, total_synced: results.sum { |r| r[:synced] },
                       total_errors: results.count { |r| !r[:success] })
      rescue StandardError => e
        log_error("sync_federation", e)
        error_result(e.message, code: "FEDERATION_SYNC_ERROR")
      end

      # JSON-RPC 2.0 entry point
      def handle_jsonrpc(request)
        method = request[:method] || request["method"]
        params = (request[:params] || request["params"] || {}).with_indifferent_access
        id = request[:id] || request["id"]

        return jsonrpc_error(id, -32601, "Method not found: #{method}") unless SUPPORTED_METHODS.include?(method)

        result = dispatch_method(method, params)
        result[:success] ? jsonrpc_success(id, result.except(:success)) : jsonrpc_error(id, result[:code] || -32000, result[:error])
      rescue StandardError => e
        log_error("handle_jsonrpc", e)
        jsonrpc_error(id, -32603, "Internal error: #{e.message}")
      end

      private

      def find_agent_card(identifier)
        Ai::AgentCard.for_discovery(@account.id).find_by(id: identifier) ||
          Ai::AgentCard.for_discovery(@account.id).find_by(name: identifier)
      end

      def resolve_agent_card(identifier)
        identifier.is_a?(Ai::AgentCard) ? identifier : find_agent_card(identifier)
      end

      def find_task(task_id)
        Ai::A2aTask.find_by(task_id: task_id, account_id: @account.id) ||
          Ai::A2aTask.find_by(id: task_id, account_id: @account.id)
      end

      def validate_agent_communication(from_card, to_card)
        return success_result(authorized: true) unless to_card.authentication&.dig("schemes")&.any?
        return error_result("Authentication required", code: "AUTH_REQUIRED") if from_card.nil?
        return success_result(authorized: true) if from_card.account_id == to_card.account_id

        fed = FederationPartner.find_by(account_id: to_card.account_id,
                                        organization_id: from_card.account.organization_id, status: "active")
        return success_result(authorized: true, federation_partner_id: fed.id) if fed

        error_result("Not authorized to communicate with this agent", code: "UNAUTHORIZED")
      end

      def validate_task_params(params)
        msg = params[:message] || params["message"]
        return error_result("message is required", code: "INVALID_PARAMS") if msg.blank?
        return error_result("message must be an object", code: "INVALID_PARAMS") unless msg.is_a?(Hash)

        parts = msg[:parts] || msg["parts"]
        return error_result("message.parts must be an array", code: "INVALID_PARAMS") if parts.present? && !parts.is_a?(Array)

        success_result(valid: true)
      end

      def valid_url?(url)
        return false if url.blank?
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end

      def normalize_message(message)
        return {} if message.blank?
        parts = message[:parts] || message["parts"] || [message[:content] || message["content"]].compact
        normalized = parts.map { |p| p.is_a?(String) ? { "type" => "text", "text" => p } : p.deep_stringify_keys }
        { "role" => message[:role] || message["role"] || "user", "parts" => normalized }
      end

      def extract_input(task_params)
        msg = task_params[:message] || task_params["message"]
        return {} if msg.blank?
        parts = msg["parts"] || msg[:parts] || []
        text = parts.select { |p| (p["type"] || p[:type]) == "text" }.map { |p| p["text"] || p[:text] }.compact.join("\n")
        { "text" => text, "raw" => msg }.compact
      end

      def build_task_metadata(task_params)
        (task_params[:metadata] || task_params["metadata"] || {})
          .merge("protocol_version" => A2A_VERSION, "submitted_at" => Time.current.iso8601)
      end

      def enqueue_task_execution(task)
        job_class = task.is_external? ? ::AiA2aExternalTaskJob : ::AiA2aTaskExecutionJob
        job_class.perform_later(task.id)
        Rails.logger.info "[A2A Protocol] Task enqueued: #{task.task_id}"
      end

      def notify_push_subscribers(task, event)
        config = task.push_notification_config
        return unless config.present? && config["enabled"] && config["url"].present?
        send_push_notification(task, event)
      end

      def send_push_notification(task, event)
        uri = URI.parse(task.push_notification_config["url"])
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10

        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["X-A2A-Protocol-Version"] = A2A_VERSION
        token = task.push_notification_config["auth_token_digest"]
        req["Authorization"] = "Bearer #{token}" if token.present?
        req.body = { jsonrpc: "2.0", method: "tasks/pushNotification",
                     params: { taskId: task.task_id, status: task.a2a_status,
                               event: event&.to_a2a_json, timestamp: Time.current.iso8601 } }.to_json

        resp = http.request(req)
        Rails.logger.warn "[A2A Protocol] Push failed for #{task.task_id}: HTTP #{resp.code}" unless resp.code.to_i.between?(200, 299)
      rescue StandardError => e
        Rails.logger.error "[A2A Protocol] Push error for #{task.task_id}: #{e.message}"
      end

      def discover_federated_agents(task_description)
        FederationPartner.where(account_id: @account.id).active.trusted.flat_map do |partner|
          result = partner.fetch_agents(query: task_description)
          next [] unless result[:success]
          (result[:agents] || []).map do |data|
            { agent_card: data, id: data["id"], name: data["name"],
              relevance_score: 0.5, federated: true, federation_partner_id: partner.id }
          end
        end
      rescue StandardError => e
        Rails.logger.warn "[A2A Protocol] Federated discovery error: #{e.message}"
        []
      end

      def compute_relevance(card, description)
        kw = description.downcase.split(/\s+/).reject { |w| w.length < 3 }
        name_lower = card.name.to_s.downcase
        desc_lower = card.description.to_s.downcase
        skills = extract_skill_ids(card)

        score = kw.sum { |w| (name_lower.include?(w) ? 0.2 : 0) + (desc_lower.include?(w) ? 0.1 : 0) +
                              (skills.any? { |s| s.include?(w) } ? 0.3 : 0) }
        score += 0.15 if card.success_rate.to_f > 80
        score += 0.1 if card.task_count.to_i > 10
        [score, 1.0].min.round(3)
      end

      def extract_skill_ids(card)
        (card.capabilities&.dig("skills") || []).map { |s| s.is_a?(Hash) ? (s["id"] || s["name"]) : s.to_s }.compact.map(&:downcase)
      end

      def dispatch_method(method, params) # rubocop:disable Metrics/MethodLength
        case method
        when "tasks/send"
          send_task(from_agent: params[:from_agent_id], to_agent: params[:to_agent_id], task_params: params)
        when "tasks/get"
          get_task(task_id: params[:task_id] || params[:id], history_length: params[:history_length])
        when "tasks/cancel"
          cancel_task(task_id: params[:task_id] || params[:id], reason: params[:reason])
        when "tasks/sendSubscribe"
          send_task_streaming(from_agent: params[:from_agent_id], to_agent: params[:to_agent_id], task_params: params)
        when "tasks/pushNotification/set"
          set_push_notification(task_id: params[:task_id] || params[:id],
                                webhook_url: params[:webhook_url] || params[:url], auth_token: params[:auth_token])
        when "tasks/pushNotification/get"
          get_push_notification(task_id: params[:task_id] || params[:id])
        when "tasks/resubscribe"
          subscribe_to_task(task_id: params[:task_id] || params[:id])
        else
          error_result("Unknown method: #{method}", code: "-32601")
        end
      end

      def jsonrpc_success(id, result)
        { jsonrpc: "2.0", id: id, result: result }
      end

      def jsonrpc_error(id, code, message, data = nil)
        { jsonrpc: "2.0", id: id, error: { code: code.to_i, message: message, data: data }.compact }
      end

      def success_result(data = {})
        { success: true }.merge(data)
      end

      def error_result(message, code: "ERROR", details: {})
        { success: false, error: message, code: code, details: details }.compact
      end

      def log_error(method, error)
        Rails.logger.error "[A2A Protocol] #{method} error: #{error.message}"
      end
    end
  end
end
