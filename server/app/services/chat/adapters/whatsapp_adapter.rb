# frozen_string_literal: true

module Chat
  module Adapters
    class WhatsappAdapter < Chat::BaseAdapter
      # Meta/WhatsApp Cloud API
      API_BASE_URL = "https://graph.facebook.com/v18.0"

      def platform_name
        "whatsapp"
      end

      def verify_webhook(request)
        # Handle verification challenge (GET request)
        if request.get?
          return verify_webhook_challenge(request)
        end

        # Verify signature for POST requests
        signature_header = request.headers["X-Hub-Signature-256"]
        return false if signature_header.blank?

        app_secret = credentials[:app_secret]
        return false if app_secret.blank?

        body = request.raw_post
        expected_signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", app_secret, body)

        ActiveSupport::SecurityUtils.secure_compare(signature_header, expected_signature)
      end

      def parse_webhook(payload)
        data = JSON.parse(payload)
        events = []

        # WhatsApp webhooks come through Meta's Graph API
        data["entry"]&.each do |entry|
          entry["changes"]&.each do |change|
            value = change["value"]
            next unless value["messaging_product"] == "whatsapp"

            # Parse messages
            value["messages"]&.each do |message|
              events << parse_message(message, value["contacts"]&.first, value["metadata"])
            end

            # Parse status updates
            value["statuses"]&.each do |status|
              events << parse_status(status)
            end
          end
        end

        events.compact
      end

      def send_message(session, content, **options)
        phone_number_id = credentials[:phone_number_id]
        recipient = session.platform_user_id

        response = with_retry do
          http_client.headers(auth_headers).post(
            "#{API_BASE_URL}/#{phone_number_id}/messages",
            json: build_message_payload(recipient, content, options)
          )
        end

        handle_api_error(response, "sendMessage")
        log_api_call("POST", "messages", response.status)

        result = JSON.parse(response.body)
        result.dig("messages", 0, "id")
      end

      def send_media(session, attachment_type, file_url, **options)
        phone_number_id = credentials[:phone_number_id]
        recipient = session.platform_user_id

        media_type = whatsapp_media_type(attachment_type)

        response = with_retry do
          http_client.headers(auth_headers).post(
            "#{API_BASE_URL}/#{phone_number_id}/messages",
            json: {
              messaging_product: "whatsapp",
              recipient_type: "individual",
              to: recipient,
              type: media_type,
              media_type => {
                link: file_url,
                caption: options[:caption]
              }.compact
            }
          )
        end

        handle_api_error(response, "sendMedia")

        result = JSON.parse(response.body)
        result.dig("messages", 0, "id")
      end

      def download_media(platform_file_id)
        # First, get the media URL
        response = http_client.headers(auth_headers).get(
          "#{API_BASE_URL}/#{platform_file_id}"
        )

        return nil unless response.status.success?

        data = JSON.parse(response.body)
        media_url = data["url"]

        return nil unless media_url

        # Download the media with auth
        file_response = http_client.headers(auth_headers).get(media_url)

        return nil unless file_response.status.success?

        {
          content: file_response.body,
          size: file_response.body.bytesize,
          mime_type: data["mime_type"]
        }
      end

      def mark_read(session, platform_message_id)
        phone_number_id = credentials[:phone_number_id]

        http_client.headers(auth_headers).post(
          "#{API_BASE_URL}/#{phone_number_id}/messages",
          json: {
            messaging_product: "whatsapp",
            status: "read",
            message_id: platform_message_id
          }
        )
      end

      def get_user_profile(platform_user_id)
        # WhatsApp doesn't provide a profile API
        # Profile info comes with messages via contacts array
        nil
      end

      def test_connection
        phone_number_id = credentials[:phone_number_id]

        response = http_client.headers(auth_headers).get(
          "#{API_BASE_URL}/#{phone_number_id}"
        )

        response.status.success?
      end

      def setup_webhook(webhook_url)
        # WhatsApp webhooks are configured in Meta Developer Console
        Rails.logger.info "WhatsApp webhook should be configured in Meta Developer Console: #{webhook_url}"

        # Could use Meta's API to configure if needed
        true
      end

      private

      def auth_headers
        { "Authorization" => "Bearer #{credentials[:access_token]}" }
      end

      def verify_webhook_challenge(request)
        mode = request.params["hub.mode"]
        token = request.params["hub.verify_token"]
        challenge = request.params["hub.challenge"]

        if mode == "subscribe" && token == credentials[:verify_token]
          challenge
        else
          false
        end
      end

      def parse_message(message, contact, metadata)
        from = message["from"]
        contact_info = contact || {}

        event = {
          type: "message",
          message_id: message["id"],
          from: {
            id: from,
            username: contact_info["profile"]&.dig("name"),
            phone: from
          },
          chat_id: from,
          timestamp: Time.at(message["timestamp"].to_i),
          metadata: {
            phone_number_id: metadata["phone_number_id"],
            display_phone_number: metadata["display_phone_number"]
          }
        }

        # Parse message type
        case message["type"]
        when "text"
          event[:content] = message.dig("text", "body")
          event[:message_type] = "text"
        when "image"
          event[:content] = message.dig("image", "caption") || "[Image]"
          event[:message_type] = "image"
          event[:attachments] = [ {
            type: "image",
            file_id: message.dig("image", "id"),
            mime_type: message.dig("image", "mime_type")
          } ]
        when "audio", "voice"
          event[:content] = "[Voice message]"
          event[:message_type] = "audio"
          event[:attachments] = [ {
            type: "audio",
            file_id: message.dig(message["type"], "id"),
            mime_type: message.dig(message["type"], "mime_type")
          } ]
        when "video"
          event[:content] = message.dig("video", "caption") || "[Video]"
          event[:message_type] = "video"
          event[:attachments] = [ {
            type: "video",
            file_id: message.dig("video", "id"),
            mime_type: message.dig("video", "mime_type")
          } ]
        when "document"
          event[:content] = message.dig("document", "caption") || "[Document]"
          event[:message_type] = "document"
          event[:attachments] = [ {
            type: "document",
            file_id: message.dig("document", "id"),
            filename: message.dig("document", "filename"),
            mime_type: message.dig("document", "mime_type")
          } ]
        when "sticker"
          event[:content] = "[Sticker]"
          event[:message_type] = "sticker"
          event[:attachments] = [ {
            type: "image",
            file_id: message.dig("sticker", "id"),
            mime_type: message.dig("sticker", "mime_type")
          } ]
        when "location"
          location = message["location"]
          event[:content] = "[Location: #{location['name'] || 'Shared location'}]"
          event[:message_type] = "location"
          event[:metadata][:location] = {
            latitude: location["latitude"],
            longitude: location["longitude"],
            name: location["name"],
            address: location["address"]
          }
        when "contacts"
          event[:content] = "[Shared contacts]"
          event[:message_type] = "text"
          event[:metadata][:contacts] = message["contacts"]
        when "interactive"
          # Button reply or list reply
          interactive = message["interactive"]
          if interactive["type"] == "button_reply"
            event[:content] = interactive.dig("button_reply", "title")
          elsif interactive["type"] == "list_reply"
            event[:content] = interactive.dig("list_reply", "title")
          end
          event[:message_type] = "text"
        else
          event[:content] = "[Unsupported message type: #{message['type']}]"
          event[:message_type] = "text"
        end

        event
      end

      def parse_status(status)
        {
          type: "message_status",
          message_id: status["id"],
          status: status["status"],  # sent, delivered, read, failed
          recipient_id: status["recipient_id"],
          timestamp: Time.at(status["timestamp"].to_i),
          error: status["errors"]&.first
        }
      end

      def build_message_payload(recipient, content, options)
        payload = {
          messaging_product: "whatsapp",
          recipient_type: "individual",
          to: recipient
        }

        if options[:template].present?
          # Template message
          payload[:type] = "template"
          payload[:template] = options[:template]
        elsif options[:buttons].present?
          # Interactive button message
          payload[:type] = "interactive"
          payload[:interactive] = {
            type: "button",
            body: { text: content },
            action: {
              buttons: options[:buttons].map.with_index do |btn, idx|
                { type: "reply", reply: { id: btn[:id] || idx.to_s, title: btn[:text][0..19] } }
              end
            }
          }
        elsif options[:list].present?
          # Interactive list message
          payload[:type] = "interactive"
          payload[:interactive] = {
            type: "list",
            body: { text: content },
            action: options[:list]
          }
        else
          # Regular text message
          payload[:type] = "text"
          payload[:text] = { body: content }
        end

        payload
      end

      def whatsapp_media_type(attachment_type)
        case attachment_type
        when "image" then "image"
        when "audio" then "audio"
        when "video" then "video"
        else "document"
        end
      end
    end
  end
end
