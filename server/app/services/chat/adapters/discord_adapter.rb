# frozen_string_literal: true

module Chat
  module Adapters
    class DiscordAdapter < Chat::BaseAdapter
      API_BASE_URL = "https://discord.com/api/v10"

      def platform_name
        "discord"
      end

      def verify_webhook(request)
        signature = request.headers["X-Signature-Ed25519"]
        timestamp = request.headers["X-Signature-Timestamp"]

        return false if signature.blank? || timestamp.blank?

        public_key = credentials[:public_key]
        return false if public_key.blank?

        body = request.raw_post
        message = timestamp + body

        begin
          verify_key = Ed25519::VerifyKey.new([public_key].pack("H*"))
          verify_key.verify([signature].pack("H*"), message)
          true
        rescue Ed25519::VerifyError, ArgumentError
          false
        end
      end

      def parse_webhook(payload)
        data = JSON.parse(payload)
        events = []

        case data["type"]
        when 1  # PING
          events << { type: "ping", ack: true }
        when 2  # APPLICATION_COMMAND
          events << parse_command(data)
        when 3  # MESSAGE_COMPONENT
          events << parse_component(data)
        when 4  # APPLICATION_COMMAND_AUTOCOMPLETE
          events << parse_autocomplete(data)
        end

        # Handle gateway events if using bot mode
        if data["t"] == "MESSAGE_CREATE"
          events << parse_message(data["d"])
        end

        events.compact
      end

      def send_message(session, content, **options)
        channel_id = extract_channel_id(session)

        response = with_retry do
          http_client.headers(auth_headers).post(
            "#{API_BASE_URL}/channels/#{channel_id}/messages",
            json: build_message_payload(content, options)
          )
        end

        handle_api_error(response, "sendMessage")
        log_api_call("POST", "channels/messages", response.status)

        result = JSON.parse(response.body)
        result["id"]
      end

      def send_media(session, attachment_type, file_url, **options)
        channel_id = extract_channel_id(session)

        # Discord requires multipart upload for files
        response = with_retry do
          http_client.headers(auth_headers).post(
            "#{API_BASE_URL}/channels/#{channel_id}/messages",
            json: {
              content: options[:caption],
              embeds: [{
                image: attachment_type == "image" ? { url: file_url } : nil,
                video: attachment_type == "video" ? { url: file_url } : nil
              }.compact]
            }
          )
        end

        handle_api_error(response, "sendMedia")

        result = JSON.parse(response.body)
        result["id"]
      end

      def download_media(platform_file_id)
        # Discord file IDs are URLs
        return nil unless platform_file_id&.start_with?("http")

        response = http_client.get(platform_file_id)

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

        http_client.headers(auth_headers).post(
          "#{API_BASE_URL}/channels/#{channel_id}/typing"
        )
      end

      def get_user_profile(platform_user_id)
        response = http_client.headers(auth_headers).get(
          "#{API_BASE_URL}/users/#{platform_user_id}"
        )

        return nil unless response.status.success?

        data = JSON.parse(response.body)

        avatar_hash = data["avatar"]
        avatar_url = avatar_hash ? "https://cdn.discordapp.com/avatars/#{platform_user_id}/#{avatar_hash}.png" : nil

        {
          id: data["id"],
          username: data["username"],
          discriminator: data["discriminator"],
          display_name: data["global_name"] || data["username"],
          avatar_url: avatar_url
        }
      end

      def test_connection
        response = http_client.headers(auth_headers).get("#{API_BASE_URL}/users/@me")
        response.status.success?
      end

      # Discord doesn't use webhooks in the same way - uses gateway events or interaction endpoints
      def setup_webhook(webhook_url)
        # For interaction-based bots, the URL is set in Discord Developer Portal
        Rails.logger.info "Discord webhook URL should be configured in Discord Developer Portal: #{webhook_url}"
        true
      end

      private

      def auth_headers
        { "Authorization" => "Bot #{credentials[:bot_token]}" }
      end

      def extract_channel_id(session)
        # Session stores channel_id in metadata or platform_user_id is the DM channel
        session.user_metadata["channel_id"] || session.platform_user_id
      end

      def parse_message(message)
        return nil if message["author"]["bot"]  # Ignore bot messages

        author = message["author"]

        {
          type: "message",
          message_id: message["id"],
          from: {
            id: author["id"],
            username: author["username"],
            discriminator: author["discriminator"],
            display_name: author["global_name"]
          },
          chat_id: message["channel_id"],
          content: message["content"],
          message_type: determine_message_type(message),
          timestamp: Time.parse(message["timestamp"]),
          attachments: parse_attachments(message["attachments"]),
          metadata: {
            channel_id: message["channel_id"],
            guild_id: message["guild_id"]
          }
        }
      end

      def parse_command(data)
        {
          type: "slash_command",
          interaction_id: data["id"],
          interaction_token: data["token"],
          command_name: data["data"]["name"],
          from: {
            id: data["member"]["user"]["id"],
            username: data["member"]["user"]["username"]
          },
          options: data["data"]["options"],
          content: build_command_content(data)
        }
      end

      def parse_component(data)
        {
          type: "component_interaction",
          interaction_id: data["id"],
          interaction_token: data["token"],
          component_id: data["data"]["custom_id"],
          from: {
            id: data["member"]["user"]["id"],
            username: data["member"]["user"]["username"]
          },
          content: data["data"]["values"]&.first || data["data"]["custom_id"]
        }
      end

      def parse_autocomplete(data)
        {
          type: "autocomplete",
          interaction_id: data["id"],
          interaction_token: data["token"],
          command_name: data["data"]["name"],
          focused_option: data["data"]["options"]&.find { |o| o["focused"] }
        }
      end

      def determine_message_type(message)
        if message["attachments"]&.any?
          attachment = message["attachments"].first
          content_type = attachment["content_type"] || ""

          case content_type
          when /^image\// then "image"
          when /^video\// then "video"
          when /^audio\// then "audio"
          else "document"
          end
        else
          "text"
        end
      end

      def parse_attachments(attachments)
        return [] if attachments.blank?

        attachments.map do |attachment|
          {
            type: determine_attachment_type(attachment["content_type"]),
            file_id: attachment["url"],
            filename: attachment["filename"],
            mime_type: attachment["content_type"],
            size: attachment["size"]
          }
        end
      end

      def determine_attachment_type(content_type)
        return "document" if content_type.blank?

        case content_type
        when /^image\// then "image"
        when /^video\// then "video"
        when /^audio\// then "audio"
        else "document"
        end
      end

      def build_command_content(data)
        options = data["data"]["options"]
        return data["data"]["name"] if options.blank?

        option_str = options.map { |o| "#{o['name']}=#{o['value']}" }.join(" ")
        "/#{data['data']['name']} #{option_str}"
      end

      def build_message_payload(content, options)
        payload = { content: content }

        if options[:embeds].present?
          payload[:embeds] = options[:embeds]
        end

        if options[:components].present?
          payload[:components] = options[:components]
        end

        if options[:reply_to].present?
          payload[:message_reference] = { message_id: options[:reply_to] }
        end

        payload
      end
    end
  end
end
