# frozen_string_literal: true

module Chat
  module Adapters
    class SlackAdapter < Chat::BaseAdapter
      API_BASE_URL = "https://slack.com/api"

      def platform_name
        "slack"
      end

      def verify_webhook(request)
        slack_signature = request.headers["X-Slack-Signature"]
        slack_timestamp = request.headers["X-Slack-Request-Timestamp"]

        return false if slack_signature.blank? || slack_timestamp.blank?

        # Check timestamp to prevent replay attacks
        timestamp = slack_timestamp.to_i
        return false if (Time.current.to_i - timestamp).abs > 300

        signing_secret = credentials[:signing_secret]
        return false if signing_secret.blank?

        body = request.raw_post
        sig_basestring = "v0:#{slack_timestamp}:#{body}"
        expected_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)

        ActiveSupport::SecurityUtils.secure_compare(slack_signature, expected_signature)
      end

      def parse_webhook(payload)
        data = JSON.parse(payload)
        events = []

        # URL verification challenge
        if data["type"] == "url_verification"
          return [{ type: "url_verification", challenge: data["challenge"] }]
        end

        # Event callback
        if data["type"] == "event_callback"
          event = data["event"]

          case event["type"]
          when "message"
            events << parse_message(event) unless event["subtype"]  # Ignore subtypes like bot_message
          when "app_mention"
            events << parse_mention(event)
          when "reaction_added"
            events << parse_reaction(event, added: true)
          when "reaction_removed"
            events << parse_reaction(event, added: false)
          end
        end

        # Interactive components (buttons, select menus)
        if data["type"] == "block_actions"
          events << parse_block_action(data)
        end

        # Slash commands
        if data["command"].present?
          events << parse_slash_command(data)
        end

        events.compact
      end

      def send_message(session, content, **options)
        channel = extract_channel(session)

        response = with_retry do
          http_client.headers(auth_headers).post(
            "#{API_BASE_URL}/chat.postMessage",
            json: build_message_payload(channel, content, options)
          )
        end

        handle_slack_response(response, "chat.postMessage")

        result = JSON.parse(response.body)
        result["ts"]  # Slack uses timestamp as message ID
      end

      def send_media(session, attachment_type, file_url, **options)
        channel = extract_channel(session)

        # Upload file to Slack
        response = with_retry do
          http_client.headers(auth_headers).post(
            "#{API_BASE_URL}/files.upload",
            form: {
              channels: channel,
              file: HTTP::FormData::File.new(file_url),
              initial_comment: options[:caption]
            }
          )
        end

        handle_slack_response(response, "files.upload")

        result = JSON.parse(response.body)
        result.dig("file", "id")
      end

      def download_media(platform_file_id)
        # Get file info
        response = http_client.headers(auth_headers).get(
          "#{API_BASE_URL}/files.info",
          params: { file: platform_file_id }
        )

        return nil unless response.status.success?

        file_info = JSON.parse(response.body)
        return nil unless file_info["ok"]

        file_url = file_info.dig("file", "url_private_download")
        return nil unless file_url

        # Download with auth
        file_response = http_client.headers(auth_headers).get(file_url)

        return nil unless file_response.status.success?

        {
          content: file_response.body,
          size: file_response.body.bytesize,
          mime_type: file_info.dig("file", "mimetype")
        }
      end

      def send_typing_indicator(session, typing: true)
        # Slack doesn't have a typing indicator API for bots
        # Use a different approach if needed
      end

      def mark_read(session, platform_message_id)
        channel = extract_channel(session)

        http_client.headers(auth_headers).post(
          "#{API_BASE_URL}/conversations.mark",
          json: { channel: channel, ts: platform_message_id }
        )
      end

      def get_user_profile(platform_user_id)
        response = http_client.headers(auth_headers).get(
          "#{API_BASE_URL}/users.info",
          params: { user: platform_user_id }
        )

        return nil unless response.status.success?

        data = JSON.parse(response.body)
        return nil unless data["ok"]

        user = data["user"]
        profile = user["profile"]

        {
          id: user["id"],
          username: user["name"],
          display_name: profile["display_name"] || profile["real_name"],
          email: profile["email"],
          avatar_url: profile["image_192"],
          is_bot: user["is_bot"]
        }
      end

      def test_connection
        response = http_client.headers(auth_headers).get("#{API_BASE_URL}/auth.test")

        return false unless response.status.success?

        data = JSON.parse(response.body)
        data["ok"] == true
      end

      def setup_webhook(webhook_url)
        # Slack webhooks are configured in the Slack app settings
        Rails.logger.info "Slack Event Subscriptions should be configured in Slack App settings: #{webhook_url}"
        true
      end

      private

      def auth_headers
        { "Authorization" => "Bearer #{credentials[:bot_token]}" }
      end

      def extract_channel(session)
        session.user_metadata["channel"] || session.platform_user_id
      end

      def handle_slack_response(response, method)
        unless response.status.success?
          handle_api_error(response, method)
        end

        data = JSON.parse(response.body)
        unless data["ok"]
          raise AdapterError, "Slack API error: #{data['error']}"
        end

        log_api_call("POST", method, response.status)
      end

      def parse_message(event)
        return nil if event["bot_id"].present?  # Ignore bot messages

        {
          type: "message",
          message_id: event["ts"],
          from: {
            id: event["user"],
            username: nil  # Would need additional API call
          },
          chat_id: event["channel"],
          content: event["text"],
          message_type: determine_message_type(event),
          timestamp: Time.at(event["ts"].to_f),
          attachments: parse_files(event["files"]),
          metadata: {
            channel: event["channel"],
            thread_ts: event["thread_ts"],
            team: event["team"]
          }
        }
      end

      def parse_mention(event)
        {
          type: "mention",
          message_id: event["ts"],
          from: { id: event["user"] },
          chat_id: event["channel"],
          content: event["text"],
          message_type: "text",
          timestamp: Time.at(event["ts"].to_f)
        }
      end

      def parse_reaction(event, added:)
        {
          type: added ? "reaction_added" : "reaction_removed",
          from: { id: event["user"] },
          message_id: event["item"]["ts"],
          reaction: event["reaction"],
          timestamp: Time.at(event["event_ts"].to_f)
        }
      end

      def parse_block_action(data)
        action = data["actions"]&.first

        {
          type: "block_action",
          action_id: action&.dig("action_id"),
          value: action&.dig("value") || action&.dig("selected_option", "value"),
          from: {
            id: data.dig("user", "id"),
            username: data.dig("user", "name")
          },
          message_id: data.dig("message", "ts"),
          response_url: data["response_url"],
          content: action&.dig("value")
        }
      end

      def parse_slash_command(data)
        {
          type: "slash_command",
          command: data["command"],
          content: data["text"],
          from: {
            id: data["user_id"],
            username: data["user_name"]
          },
          chat_id: data["channel_id"],
          response_url: data["response_url"]
        }
      end

      def determine_message_type(event)
        if event["files"].present?
          file = event["files"].first
          mimetype = file["mimetype"] || ""

          case mimetype
          when /^image\// then "image"
          when /^video\// then "video"
          when /^audio\// then "audio"
          else "document"
          end
        else
          "text"
        end
      end

      def parse_files(files)
        return [] if files.blank?

        files.map do |file|
          {
            type: determine_file_type(file["mimetype"]),
            file_id: file["id"],
            filename: file["name"],
            mime_type: file["mimetype"],
            size: file["size"]
          }
        end
      end

      def determine_file_type(mimetype)
        return "document" if mimetype.blank?

        case mimetype
        when /^image\// then "image"
        when /^video\// then "video"
        when /^audio\// then "audio"
        else "document"
        end
      end

      def build_message_payload(channel, content, options)
        payload = {
          channel: channel,
          text: content
        }

        if options[:blocks].present?
          payload[:blocks] = options[:blocks]
        end

        if options[:attachments].present?
          payload[:attachments] = options[:attachments]
        end

        if options[:thread_ts].present?
          payload[:thread_ts] = options[:thread_ts]
        end

        if options[:reply_broadcast]
          payload[:reply_broadcast] = true
        end

        payload
      end
    end
  end
end
