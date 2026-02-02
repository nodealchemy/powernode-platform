# frozen_string_literal: true

module Chat
  module Adapters
    class MattermostAdapter < Chat::BaseAdapter
      def platform_name
        "mattermost"
      end

      def api_base_url
        credentials[:server_url]&.chomp("/")
      end

      def verify_webhook(request)
        # Mattermost can use either token-based verification or HMAC
        token = request.headers["Authorization"]&.sub(/^Bearer\s+/i, "")
        expected_token = credentials[:webhook_token] || channel.webhook_token

        if token.present?
          ActiveSupport::SecurityUtils.secure_compare(token, expected_token)
        else
          # Check for token in payload (outgoing webhook)
          payload = JSON.parse(request.raw_post) rescue {}
          payload_token = payload["token"]

          if payload_token.present?
            ActiveSupport::SecurityUtils.secure_compare(payload_token, expected_token)
          else
            true  # Allow if no token configured (relies on URL secrecy)
          end
        end
      end

      def parse_webhook(payload)
        data = JSON.parse(payload)
        events = []

        # Outgoing webhook format
        if data["post_id"].present?
          events << parse_outgoing_webhook(data)
        end

        # Slash command format
        if data["command"].present?
          events << parse_slash_command(data)
        end

        # Interactive dialog submission
        if data["type"] == "dialog_submission"
          events << parse_dialog_submission(data)
        end

        # Interactive message action
        if data["context"].present? && data["type"] == "interactive_dialog"
          events << parse_interactive_action(data)
        end

        events.compact
      end

      def send_message(session, content, **options)
        channel_id = extract_channel_id(session)

        response = with_retry do
          http_client.headers(auth_headers).post(
            "#{api_base_url}/api/v4/posts",
            json: build_post_payload(channel_id, content, options)
          )
        end

        handle_api_error(response, "createPost")
        log_api_call("POST", "posts", response.status)

        result = JSON.parse(response.body)
        result["id"]
      end

      def send_media(session, attachment_type, file_url, **options)
        channel_id = extract_channel_id(session)

        # First upload the file
        file_id = upload_file(channel_id, file_url, options[:filename])

        return nil unless file_id

        # Then create post with file attachment
        response = http_client.headers(auth_headers).post(
          "#{api_base_url}/api/v4/posts",
          json: {
            channel_id: channel_id,
            message: options[:caption] || "",
            file_ids: [ file_id ]
          }
        )

        handle_api_error(response, "createPost")

        result = JSON.parse(response.body)
        result["id"]
      end

      def download_media(platform_file_id)
        response = http_client.headers(auth_headers).get(
          "#{api_base_url}/api/v4/files/#{platform_file_id}"
        )

        return nil unless response.status.success?

        {
          content: response.body,
          size: response.body.bytesize,
          mime_type: response.content_type.mime_type
        }
      end

      def send_typing_indicator(session, typing: true)
        return unless typing

        channel_id = extract_channel_id(session)

        # Mattermost WebSocket typing notification
        # This is typically done via WebSocket, not REST API
        # For REST API, we'd need to use the Actions API
        nil
      end

      def get_user_profile(platform_user_id)
        response = http_client.headers(auth_headers).get(
          "#{api_base_url}/api/v4/users/#{platform_user_id}"
        )

        return nil unless response.status.success?

        data = JSON.parse(response.body)

        {
          id: data["id"],
          username: data["username"],
          display_name: "#{data['first_name']} #{data['last_name']}".strip,
          email: data["email"],
          avatar_url: "#{api_base_url}/api/v4/users/#{platform_user_id}/image"
        }
      end

      def test_connection
        response = http_client.headers(auth_headers).get("#{api_base_url}/api/v4/users/me")
        response.status.success?
      end

      def setup_webhook(webhook_url)
        # Create outgoing webhook in Mattermost
        # This typically requires admin permissions
        Rails.logger.info "Mattermost outgoing webhook should be configured: #{webhook_url}"
        true
      end

      private

      def auth_headers
        if credentials[:personal_access_token].present?
          { "Authorization" => "Bearer #{credentials[:personal_access_token]}" }
        else
          { "Authorization" => "Bearer #{credentials[:bot_token]}" }
        end
      end

      def extract_channel_id(session)
        session.user_metadata["channel_id"] || session.platform_user_id
      end

      def parse_outgoing_webhook(data)
        {
          type: "message",
          message_id: data["post_id"],
          from: {
            id: data["user_id"],
            username: data["user_name"]
          },
          chat_id: data["channel_id"],
          content: data["text"],
          message_type: determine_message_type(data),
          timestamp: Time.at(data["timestamp"].to_i / 1000),
          attachments: parse_file_ids(data["file_ids"]),
          metadata: {
            channel_id: data["channel_id"],
            channel_name: data["channel_name"],
            team_id: data["team_id"],
            team_domain: data["team_domain"],
            trigger_word: data["trigger_word"]
          }
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
          response_url: data["response_url"],
          trigger_id: data["trigger_id"]
        }
      end

      def parse_dialog_submission(data)
        {
          type: "dialog_submission",
          callback_id: data["callback_id"],
          from: {
            id: data["user_id"]
          },
          chat_id: data["channel_id"],
          submission: data["submission"],
          content: data["submission"]&.values&.join(" ")
        }
      end

      def parse_interactive_action(data)
        {
          type: "interactive_action",
          action_id: data["context"]["action"],
          from: {
            id: data["user_id"]
          },
          chat_id: data["channel_id"],
          post_id: data["post_id"],
          content: data["context"]["value"] || data["context"]["action"]
        }
      end

      def determine_message_type(data)
        if data["file_ids"].present?
          "document"  # Mattermost doesn't distinguish media types in webhooks
        else
          "text"
        end
      end

      def parse_file_ids(file_ids)
        return [] if file_ids.blank?

        file_ids.map do |file_id|
          {
            type: "document",
            file_id: file_id
          }
        end
      end

      def build_post_payload(channel_id, content, options)
        payload = {
          channel_id: channel_id,
          message: content
        }

        if options[:props].present?
          payload[:props] = options[:props]
        end

        if options[:root_id].present?
          payload[:root_id] = options[:root_id]
        end

        # Attachments (rich message formatting)
        if options[:attachments].present?
          payload[:props] ||= {}
          payload[:props][:attachments] = options[:attachments]
        end

        payload
      end

      def upload_file(channel_id, file_url, filename)
        # Download the file first
        file_response = http_client.get(file_url)
        return nil unless file_response.status.success?

        # Upload to Mattermost
        response = http_client.headers(auth_headers).post(
          "#{api_base_url}/api/v4/files",
          form: {
            channel_id: channel_id,
            files: HTTP::FormData::Part.new(
              file_response.body,
              filename: filename || "file",
              content_type: file_response.content_type.mime_type
            )
          }
        )

        return nil unless response.status.success?

        result = JSON.parse(response.body)
        result.dig("file_infos", 0, "id")
      end
    end
  end
end
