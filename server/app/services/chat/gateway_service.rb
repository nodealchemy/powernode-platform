# frozen_string_literal: true

module Chat
  class GatewayService
    class GatewayError < StandardError; end

    def initialize(channel)
      @channel = channel
      @session_manager = SessionManager.new(channel)
      @message_router = MessageRouter.new(channel)
      @verification_service = WebhookVerificationService.new(channel)
    end

    # Main entry point for incoming webhooks
    def process_webhook(request)
      # Verify webhook signature
      @verification_service.verify!(request)

      # Parse webhook payload
      adapter = AdapterFactory.for_channel(@channel)
      events = adapter.parse_webhook(request.raw_post)

      # Process each event
      results = events.map { |event| process_event(event) }

      {
        success: true,
        processed: results.count { |r| r[:status] == "processed" },
        total: results.count
      }
    rescue WebhookVerificationService::VerificationError => e
      Rails.logger.warn "Webhook verification failed: #{e.message}"
      { success: false, error: "verification_failed" }
    rescue StandardError => e
      Rails.logger.error "Webhook processing error: #{e.message}"
      { success: false, error: e.message }
    end

    # Process a single event from webhook
    def process_event(event)
      case event[:type]
      when "message"
        process_message_event(event)
      when "message_status"
        process_status_event(event)
      when "message_read"
        process_read_event(event)
      when "user_joined", "user_left"
        process_user_event(event)
      else
        Rails.logger.debug "Unhandled event type: #{event[:type]}"
        { status: "ignored", type: event[:type] }
      end
    rescue StandardError => e
      Rails.logger.error "Error processing event: #{e.message}"
      { status: "error", error: e.message }
    end

    # Send a message to a session
    def send_message(session, content, **options)
      @message_router.route_outbound(
        session: session,
        content: content,
        **options
      )
    end

    # Get session for a platform user
    def get_session(platform_user_id:, **options)
      @session_manager.get_session(
        platform_user_id: platform_user_id,
        **options
      )
    end

    # Connect channel to platform
    def connect
      return if @channel.connected?

      @channel.connect!

      adapter = AdapterFactory.for_channel(@channel)

      # Test connection
      unless adapter.test_connection
        @channel.mark_disconnected!("Connection test failed")
        return false
      end

      # Setup webhook if needed
      adapter.setup_webhook(@channel.webhook_url)

      @channel.mark_connected!
      true
    rescue StandardError => e
      @channel.mark_disconnected!(e.message)
      false
    end

    # Disconnect channel
    def disconnect
      @channel.disconnect!
      true
    end

    # Get channel statistics
    def statistics
      {
        channel: @channel.channel_summary,
        sessions: @session_manager.session_stats,
        status: @channel.status,
        uptime: calculate_uptime
      }
    end

    private

    def process_message_event(event)
      # Get or create session
      session = @session_manager.get_session(
        platform_user_id: event[:from][:id],
        platform_username: event[:from][:username],
        metadata: event[:from]
      )

      # Route message
      result = @message_router.route_inbound(
        session: session,
        content: event[:content],
        message_type: event[:message_type] || "text",
        platform_message_id: event[:message_id],
        metadata: event[:metadata] || {}
      )

      # Handle media attachments
      if event[:attachments].present?
        process_attachments(result[:message], event[:attachments])
      end

      { status: "processed", session_id: session.id, message_id: result[:message]&.id }
    rescue SessionManager::BlockedUserError
      { status: "blocked" }
    end

    def process_status_event(event)
      message = Chat::Message.find_by(platform_message_id: event[:message_id])
      return { status: "ignored" } unless message

      case event[:status]
      when "sent"
        message.mark_sent!
      when "delivered"
        message.mark_delivered!
      when "failed"
        message.mark_failed!(event[:error])
      end

      { status: "processed", message_id: message.id }
    end

    def process_read_event(event)
      message = Chat::Message.find_by(platform_message_id: event[:message_id])
      return { status: "ignored" } unless message

      message.mark_read!
      { status: "processed", message_id: message.id }
    end

    def process_user_event(event)
      session = @channel.sessions.find_by(platform_user_id: event[:user_id])
      return { status: "ignored" } unless session

      case event[:type]
      when "user_joined"
        session.activate!
      when "user_left"
        session.mark_idle!
      end

      { status: "processed", session_id: session.id }
    end

    def process_attachments(message, attachments)
      adapter = AdapterFactory.for_channel(@channel)

      attachments.each do |attachment|
        # Download media from platform
        file_data = adapter.download_media(attachment[:file_id])
        next unless file_data

        # Create attachment record
        message.attachments.create!(
          attachment_type: attachment[:type] || determine_attachment_type(attachment[:mime_type]),
          mime_type: attachment[:mime_type],
          filename: attachment[:filename],
          platform_file_id: attachment[:file_id],
          file_size: file_data[:size],
          metadata: attachment[:metadata] || {}
        )

        # Store file in file management system
        store_attachment_file(message.attachments.last, file_data)
      end
    end

    def determine_attachment_type(mime_type)
      case mime_type
      when /^image\//
        "image"
      when /^audio\//
        "audio"
      when /^video\//
        "video"
      else
        "document"
      end
    end

    def store_attachment_file(attachment, file_data)
      # Use file management service to store
      storage_service = FileManagement::StorageService.new(
        account: @channel.account,
        storage: @channel.account.file_storages.default.first
      )

      file_object = storage_service.upload(
        file: file_data[:content],
        filename: attachment.filename || "attachment",
        content_type: attachment.mime_type,
        folder: "chat/attachments/#{@channel.id}"
      )

      attachment.update!(
        file_object: file_object,
        storage_url: file_object.url
      )
    rescue StandardError => e
      Rails.logger.error "Failed to store attachment: #{e.message}"
    end

    def calculate_uptime
      return nil unless @channel.connected_at

      Time.current - @channel.connected_at
    end
  end
end
