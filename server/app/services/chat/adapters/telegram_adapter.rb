# frozen_string_literal: true

module Chat
  module Adapters
    class TelegramAdapter < Chat::BaseAdapter
      API_BASE_URL = "https://api.telegram.org"

      def platform_name
        "telegram"
      end

      def verify_webhook(request)
        # Telegram uses secret token in header
        secret_token = request.headers["X-Telegram-Bot-Api-Secret-Token"]
        expected_token = credentials[:webhook_secret] || channel.webhook_token

        if secret_token.present?
          ActiveSupport::SecurityUtils.secure_compare(secret_token, expected_token)
        else
          # Fallback to URL-based verification
          true  # Telegram is verified by the webhook URL token
        end
      end

      def parse_webhook(payload)
        data = JSON.parse(payload)
        events = []

        # Handle message updates
        if data["message"].present?
          events << parse_message(data["message"])
        end

        # Handle edited messages
        if data["edited_message"].present?
          events << parse_message(data["edited_message"], edited: true)
        end

        # Handle callback queries (button clicks)
        if data["callback_query"].present?
          events << parse_callback_query(data["callback_query"])
        end

        events.compact
      end

      def send_message(session, content, **options)
        response = with_retry do
          http_client.post(
            api_url("sendMessage"),
            json: {
              chat_id: session.platform_user_id,
              text: content,
              parse_mode: options[:parse_mode] || "HTML"
            }.merge(build_reply_markup(options))
          )
        end

        handle_api_error(response, "sendMessage")
        log_api_call("POST", "sendMessage", response.status)

        result = JSON.parse(response.body)
        result.dig("result", "message_id").to_s
      end

      def send_media(session, attachment_type, file_url, **options)
        method = media_method(attachment_type)

        response = with_retry do
          http_client.post(
            api_url(method),
            json: {
              chat_id: session.platform_user_id,
              attachment_type => file_url,
              caption: options[:caption]
            }.compact
          )
        end

        handle_api_error(response, method)

        result = JSON.parse(response.body)
        result.dig("result", "message_id").to_s
      end

      def download_media(platform_file_id)
        # Get file path
        response = http_client.get(api_url("getFile"), params: { file_id: platform_file_id })
        handle_api_error(response, "getFile")

        file_info = JSON.parse(response.body)
        file_path = file_info.dig("result", "file_path")

        return nil unless file_path

        # Download file
        file_url = "#{API_BASE_URL}/file/bot#{credentials[:bot_token]}/#{file_path}"
        file_response = http_client.get(file_url)

        {
          content: file_response.body,
          size: file_response.body.bytesize,
          mime_type: file_response.content_type.mime_type
        }
      end

      def send_typing_indicator(session, typing: true)
        action = typing ? "typing" : "cancel"

        http_client.post(
          api_url("sendChatAction"),
          json: { chat_id: session.platform_user_id, action: action }
        )
      end

      def get_user_profile(platform_user_id)
        response = http_client.get(api_url("getChat"), params: { chat_id: platform_user_id })

        return nil unless response.status.success?

        data = JSON.parse(response.body)["result"]

        {
          id: data["id"],
          username: data["username"],
          first_name: data["first_name"],
          last_name: data["last_name"],
          photo_url: get_profile_photo(data["id"])
        }
      end

      def test_connection
        response = http_client.get(api_url("getMe"))
        response.status.success?
      end

      def setup_webhook(webhook_url)
        response = http_client.post(
          api_url("setWebhook"),
          json: {
            url: webhook_url,
            allowed_updates: %w[message edited_message callback_query],
            secret_token: channel.webhook_token,
            drop_pending_updates: false
          }
        )

        handle_api_error(response, "setWebhook")

        result = JSON.parse(response.body)
        result["ok"] == true
      end

      private

      def api_url(method)
        "#{API_BASE_URL}/bot#{credentials[:bot_token]}/#{method}"
      end

      def parse_message(message, edited: false)
        from = message["from"]
        chat = message["chat"]

        event = {
          type: edited ? "message_edited" : "message",
          message_id: message["message_id"].to_s,
          from: {
            id: from["id"].to_s,
            username: from["username"],
            first_name: from["first_name"],
            last_name: from["last_name"]
          },
          chat_id: chat["id"].to_s,
          timestamp: Time.at(message["date"]),
          metadata: { chat_type: chat["type"] }
        }

        # Parse message content
        if message["text"].present?
          event[:content] = message["text"]
          event[:message_type] = "text"
        elsif message["photo"].present?
          largest_photo = message["photo"].max_by { |p| p["file_size"] || 0 }
          event[:content] = message["caption"] || "[Photo]"
          event[:message_type] = "image"
          event[:attachments] = [ {
            type: "image",
            file_id: largest_photo["file_id"],
            mime_type: "image/jpeg"
          } ]
        elsif message["voice"].present?
          event[:content] = "[Voice message]"
          event[:message_type] = "audio"
          event[:attachments] = [ {
            type: "audio",
            file_id: message["voice"]["file_id"],
            mime_type: message["voice"]["mime_type"] || "audio/ogg",
            metadata: { duration: message["voice"]["duration"] }
          } ]
        elsif message["audio"].present?
          event[:content] = message["caption"] || "[Audio]"
          event[:message_type] = "audio"
          event[:attachments] = [ {
            type: "audio",
            file_id: message["audio"]["file_id"],
            filename: message["audio"]["file_name"],
            mime_type: message["audio"]["mime_type"]
          } ]
        elsif message["video"].present?
          event[:content] = message["caption"] || "[Video]"
          event[:message_type] = "video"
          event[:attachments] = [ {
            type: "video",
            file_id: message["video"]["file_id"],
            filename: message["video"]["file_name"],
            mime_type: message["video"]["mime_type"] || "video/mp4"
          } ]
        elsif message["document"].present?
          event[:content] = message["caption"] || "[Document]"
          event[:message_type] = "document"
          event[:attachments] = [ {
            type: "document",
            file_id: message["document"]["file_id"],
            filename: message["document"]["file_name"],
            mime_type: message["document"]["mime_type"]
          } ]
        elsif message["sticker"].present?
          event[:content] = message["sticker"]["emoji"] || "[Sticker]"
          event[:message_type] = "sticker"
        elsif message["location"].present?
          event[:content] = "[Location]"
          event[:message_type] = "location"
          event[:metadata][:location] = {
            latitude: message["location"]["latitude"],
            longitude: message["location"]["longitude"]
          }
        else
          return nil  # Unsupported message type
        end

        event
      end

      def parse_callback_query(callback)
        {
          type: "callback_query",
          callback_id: callback["id"],
          message_id: callback.dig("message", "message_id")&.to_s,
          from: {
            id: callback["from"]["id"].to_s,
            username: callback["from"]["username"]
          },
          data: callback["data"],
          content: callback["data"]
        }
      end

      def build_reply_markup(options)
        return {} unless options[:buttons].present?

        {
          reply_markup: {
            inline_keyboard: options[:buttons].map do |row|
              row.map { |btn| { text: btn[:text], callback_data: btn[:data] || btn[:text] } }
            end
          }
        }
      end

      def media_method(type)
        case type
        when "image" then "sendPhoto"
        when "audio" then "sendAudio"
        when "video" then "sendVideo"
        when "document" then "sendDocument"
        else "sendDocument"
        end
      end

      def get_profile_photo(user_id)
        response = http_client.get(api_url("getUserProfilePhotos"), params: { user_id: user_id, limit: 1 })

        return nil unless response.status.success?

        photos = JSON.parse(response.body).dig("result", "photos")
        return nil if photos.blank?

        # Get the smallest photo for profile
        photos.first&.first&.dig("file_id")
      end
    end
  end
end
