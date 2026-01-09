# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Notification node executor - sends notifications via various channels
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

        notification_context = {
          channel: channel,
          webhook_url: webhook_url,
          channel_id: channel_id,
          message: message,
          format: format,
          title: title,
          mentions: mentions,
          thread_id: thread_id,
          priority: priority,
          started_at: Time.current
        }

        log_info "Sending #{channel} notification"

        # Send the notification
        result = send_notification(notification_context)

        build_output(notification_context, result)
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

      def send_notification(context)
        # NOTE: This is a simulation. In production, this would:
        # 1. Select the appropriate notification provider
        # 2. Format the message appropriately
        # 3. Send via the provider's API
        # 4. Return delivery status

        notification_id = "notif_#{SecureRandom.hex(16)}"

        case context[:channel]
        when "slack"
          send_slack_notification(context, notification_id)
        when "teams"
          send_teams_notification(context, notification_id)
        when "discord"
          send_discord_notification(context, notification_id)
        when "sms"
          send_sms_notification(context, notification_id)
        when "push"
          send_push_notification(context, notification_id)
        when "in_app"
          send_in_app_notification(context, notification_id)
        end
      end

      def send_slack_notification(context, notification_id)
        {
          notification_id: notification_id,
          channel: "slack",
          status: "delivered",
          timestamp: Time.current.to_f.to_s,
          thread_ts: context[:thread_id]
        }
      end

      def send_teams_notification(context, notification_id)
        {
          notification_id: notification_id,
          channel: "teams",
          status: "delivered",
          message_id: SecureRandom.uuid
        }
      end

      def send_discord_notification(context, notification_id)
        {
          notification_id: notification_id,
          channel: "discord",
          status: "delivered",
          message_id: SecureRandom.hex(18)
        }
      end

      def send_sms_notification(context, notification_id)
        {
          notification_id: notification_id,
          channel: "sms",
          status: "queued",
          segments: 1
        }
      end

      def send_push_notification(context, notification_id)
        {
          notification_id: notification_id,
          channel: "push",
          status: "delivered",
          devices_targeted: 1
        }
      end

      def send_in_app_notification(context, notification_id)
        {
          notification_id: notification_id,
          channel: "in_app",
          status: "created",
          read: false
        }
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

      def build_output(context, result)
        {
          output: {
            notification_sent: true,
            notification_id: result[:notification_id],
            channel: context[:channel]
          },
          data: result.merge(
            message_preview: context[:message].truncate(100),
            format: context[:format],
            priority: context[:priority],
            mentions_count: context[:mentions].length,
            duration_ms: ((Time.current - context[:started_at]) * 1000).round
          ),
          metadata: {
            node_id: @node.node_id,
            node_type: "notification",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
