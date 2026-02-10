# frozen_string_literal: true

module A2a
  # MessageHandler - Handles A2A JSON-RPC 2.0 message processing
  # Implements the A2A protocol message handling specification
  class MessageHandler
    SUPPORTED_METHODS = %w[
      message/send
      message/stream
      tasks/get
      tasks/list
      tasks/cancel
      tasks/subscribe
      tasks/pushNotification/set
      tasks/pushNotification/get
      agent/authenticatedExtendedCard
    ].freeze

    def initialize(account:, user: nil)
      @account = account
      @user = user
      @a2a_service = ::Ai::A2a::Service.new(account: account, user: user)
    end

    # message/send - Execute a skill and return a Task
    def send_message(params)
      validate_message_params!(params)

      skill_id = params["skill"] || extract_skill_from_message(params["message"])
      skill = SkillRegistry.find_skill(skill_id)

      unless skill
        return { error: { code: -32602, message: "Unknown skill: #{skill_id}" } }
      end

      task = create_task_for_skill(skill, params)

      begin
        execute_skill(skill, task, params)
        { result: task.reload.to_a2a_json }
      rescue StandardError => e
        task.fail!(error_message: e.message, error_code: e.class.name)
        { result: task.reload.to_a2a_json }
      end
    end

    # message/stream - Execute with SSE streaming
    def stream_message(params, stream, &block)
      validate_message_params!(params)

      skill_id = params["skill"] || extract_skill_from_message(params["message"])
      skill = SkillRegistry.find_skill(skill_id)

      unless skill
        block.call({ type: "error", error: { code: -32602, message: "Unknown skill: #{skill_id}" } })
        return
      end

      task = create_task_for_skill(skill, params)

      # Send initial task status
      block.call({ type: "task.status", task: task.to_a2a_json })

      begin
        task.start!
        block.call({ type: "task.status", task: task.reload.to_a2a_json })

        # Execute with progress callbacks
        execute_skill_streaming(skill, task, params) do |event|
          block.call(event)
        end

        task.reload
        block.call({ type: "task.complete", task: task.to_a2a_json })
      rescue StandardError => e
        task.fail!(error_message: e.message, error_code: e.class.name)
        block.call({ type: "task.failed", task: task.reload.to_a2a_json })
      end
    end

    # tasks/get - Get task by ID
    def get_task(params)
      task_id = params["id"]
      return { error: { code: -32602, message: "Missing task ID" } } if task_id.blank?

      task = find_task(task_id)
      return { error: { code: -32001, message: "Task not found" } } unless task

      { result: task.to_a2a_json }
    end

    # tasks/list - List tasks with filters
    def list_tasks(params)
      scope = @account.ai_a2a_tasks.order(created_at: :desc)

      scope = scope.where(status: params["status"]) if params["status"].present?
      scope = scope.from_agent(params["fromAgentId"]) if params["fromAgentId"].present?
      scope = scope.to_agent(params["toAgentId"]) if params["toAgentId"].present?

      page = (params["page"] || 1).to_i
      per_page = [ (params["perPage"] || 20).to_i, 100 ].min

      tasks = scope.offset((page - 1) * per_page).limit(per_page)

      {
        result: {
          tasks: tasks.map(&:to_a2a_json),
          total: scope.count,
          page: page,
          perPage: per_page
        }
      }
    end

    # tasks/cancel - Cancel a running task
    def cancel_task(params)
      task_id = params["id"]
      return { error: { code: -32602, message: "Missing task ID" } } if task_id.blank?

      task = find_task(task_id)
      return { error: { code: -32001, message: "Task not found" } } unless task

      unless task.can_cancel?
        return { error: { code: -32002, message: "Task cannot be cancelled" } }
      end

      task.cancel!(reason: params["reason"])
      { result: task.reload.to_a2a_json }
    end

    # tasks/subscribe - Subscribe to task updates
    def subscribe_task(params)
      task_id = params["id"]
      return { error: { code: -32602, message: "Missing task ID" } } if task_id.blank?

      task = find_task(task_id)
      return { error: { code: -32001, message: "Task not found" } } unless task

      # Return subscription info
      {
        result: {
          subscriptionId: SecureRandom.uuid,
          taskId: task.task_id,
          status: task.a2a_status,
          streamUrl: "/api/v1/a2a/stream",
          channelName: "a2a_task_#{task.task_id}"
        }
      }
    end

    # tasks/pushNotification/set - Configure push notifications
    def set_push_notification(params)
      task_id = params["id"]
      return { error: { code: -32602, message: "Missing task ID" } } if task_id.blank?

      task = find_task(task_id)
      return { error: { code: -32001, message: "Task not found" } } unless task

      config = {
        url: params["url"],
        token: params["token"],
        authentication: params["authentication"],
        events: params["events"] || %w[status_change completed failed]
      }

      task.update!(push_notification_config: config)
      { result: { success: true, config: config } }
    end

    # tasks/pushNotification/get - Get push notification config
    def get_push_notification(params)
      task_id = params["id"]
      return { error: { code: -32602, message: "Missing task ID" } } if task_id.blank?

      task = find_task(task_id)
      return { error: { code: -32001, message: "Task not found" } } unless task

      { result: task.push_notification_config || {} }
    end

    # agent/authenticatedExtendedCard - Get extended agent card
    def get_extended_card(params)
      card_id = params["agentCardId"]

      if card_id.present?
        card = @account.ai_agent_cards.find_by(id: card_id)
        return { error: { code: -32001, message: "Agent card not found" } } unless card
        { result: AgentCardService.agent_card(card, base_url) }
      else
        # Return platform card
        { result: AgentCardService.platform_card(base_url) }
      end
    end

    private

    def validate_message_params!(params)
      if params["message"].blank? && params["skill"].blank?
        raise ArgumentError, "Either message or skill is required"
      end
    end

    def extract_skill_from_message(message)
      return nil unless message.is_a?(Hash)

      # Try to extract skill from message content
      parts = message["parts"] || []
      text_part = parts.find { |p| p["type"] == "text" }
      return nil unless text_part

      text = text_part["text"] || ""

      # Match skill invocation patterns like "execute workflows.execute" or "@workflows.list"
      if text =~ /^(?:execute|run|invoke|@)\s*(\w+\.\w+)/i
        return Regexp.last_match(1)
      end

      nil
    end

    def create_task_for_skill(skill, params)
      message = params["message"] || { "parts" => [ { "type" => "text", "text" => "Execute #{skill[:id]}" } ] }

      # Mark as external since skill execution is handled by the platform itself
      ::Ai::A2aTask.create!(
        account: @account,
        message: normalize_message(message),
        input: extract_input(params),
        is_external: true,
        external_endpoint_url: "internal://skill/#{skill[:id]}",
        metadata: {
          skill_id: skill[:id],
          skill_name: skill[:name],
          submitted_at: Time.current.iso8601
        }
      )
    end

    def execute_skill(skill, task, params)
      task.start!

      handler_class, handler_method = skill[:handler].to_s.split(".")
      handler = handler_class.constantize.new(account: @account, user: @user)

      result = handler.public_send(handler_method, extract_input(params), task)

      task.complete!(result: result[:output], artifacts: result[:artifacts] || [])
    end

    def execute_skill_streaming(skill, task, params, &block)
      handler_class, handler_method = skill[:handler].to_s.split(".")
      handler = handler_class.constantize.new(account: @account, user: @user)

      if handler.respond_to?("#{handler_method}_streaming")
        handler.public_send("#{handler_method}_streaming", extract_input(params), task, &block)
      else
        result = handler.public_send(handler_method, extract_input(params), task)
        block.call({ type: "task.output", output: result[:output] })
        task.complete!(result: result[:output], artifacts: result[:artifacts] || [])
      end
    end

    def normalize_message(message)
      return { "role" => "user", "parts" => [] } if message.blank?

      {
        "role" => message["role"] || "user",
        "parts" => message["parts"] || [ { "type" => "text", "text" => message.to_s } ]
      }
    end

    def extract_input(params)
      input = params["input"] || {}

      # Include message content in input
      if params["message"].present?
        parts = params["message"]["parts"] || []
        text = parts.select { |p| p["type"] == "text" }.map { |p| p["text"] }.join("\n")
        input["text"] = text if text.present?
      end

      input
    end

    def find_task(task_id)
      @account.ai_a2a_tasks.find_by(task_id: task_id) ||
        @account.ai_a2a_tasks.find_by(id: task_id)
    end

    def base_url
      @base_url ||= Rails.application.config.action_mailer.default_url_options&.dig(:host) || "http://localhost:3000"
    end
  end
end
