# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Notification node executor - dispatches notifications to worker
    #
    # Configuration:
    # - channel: Target channel type (slack, teams, discord, push, sms)
    # - webhook_url or channel_id: Destination
    # - message: Message content with variable interpolation
    # - format: plain, markdown, blocks (Slack)
    # - mentions: User/group mentions
    # - thread_id: For threaded replies
    #
    class Notification < Base
      include Concerns::WorkerDispatch

      ALLOWED_CHANNELS = %w[slack teams discord push sms in_app].freeze

      protected

      def perform_execution
        log_info "Executing notification operation"

        channel = configuration["channel"] || "slack"
        webhook_url = resolve_value(configuration["webhook_url"])
        channel_id = resolve_value(configuration["channel_id"])
        message = resolve_value(configuration["message"])
        format = configuration["format"] || "plain"
        title = resolve_value(configuration["title"])
        mentions = configuration["mentions"] || []
        thread_id = resolve_value(configuration["thread_id"])
        priority = configuration["priority"] || "normal"

        validate_configuration!(channel, message, webhook_url, channel_id)

        payload = {
          channel: channel,
          webhook_url: webhook_url,
          channel_id: channel_id,
          message: message,
          format: format,
          title: title,
          mentions: mentions,
          thread_id: thread_id,
          priority: priority,
          node_id: @node.node_id
        }

        log_info "Dispatching #{channel} notification"

        dispatch_to_worker("Mcp::McpNotificationExecutionJob", payload)
      end

      private

      def validate_configuration!(channel, message, webhook_url, channel_id)
        unless ALLOWED_CHANNELS.include?(channel)
          raise ArgumentError, "Invalid channel: #{channel}. Allowed: #{ALLOWED_CHANNELS.join(', ')}"
        end

        raise ArgumentError, "message is required" if message.blank?

        if %w[slack teams discord].include?(channel) && webhook_url.blank? && channel_id.blank?
          raise ArgumentError, "webhook_url or channel_id is required for #{channel}"
        end
      end

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\$\{\{(.+?)\}\}|\{\{(.+?)\}\}/)
          variable_name = value.match(/\$?\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end
    end
  end
end
