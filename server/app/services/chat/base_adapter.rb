# frozen_string_literal: true

module Chat
  class BaseAdapter
    class AdapterError < StandardError; end
    class AuthenticationError < AdapterError; end
    class RateLimitError < AdapterError; end
    class DeliveryError < AdapterError; end
    class MediaError < AdapterError; end

    attr_reader :channel

    def initialize(channel)
      @channel = channel
      @credentials = nil
    end

    # Override in subclasses
    def platform_name
      raise NotImplementedError, "Subclass must implement #platform_name"
    end

    # Verify webhook signature
    def verify_webhook(request)
      raise NotImplementedError, "Subclass must implement #verify_webhook"
    end

    # Parse incoming webhook payload
    def parse_webhook(payload)
      raise NotImplementedError, "Subclass must implement #parse_webhook"
    end

    # Send text message
    def send_message(session, content, **options)
      raise NotImplementedError, "Subclass must implement #send_message"
    end

    # Send media message
    def send_media(session, attachment_type, file_url, **options)
      raise NotImplementedError, "Subclass must implement #send_media"
    end

    # Download media from platform
    def download_media(platform_file_id)
      raise NotImplementedError, "Subclass must implement #download_media"
    end

    # Send typing indicator
    def send_typing_indicator(session, typing: true)
      # Optional - not all platforms support this
      Rails.logger.debug "Typing indicator not implemented for #{platform_name}"
    end

    # Mark message as read
    def mark_read(session, platform_message_id)
      # Optional - not all platforms support this
      Rails.logger.debug "Mark read not implemented for #{platform_name}"
    end

    # Get user profile from platform
    def get_user_profile(platform_user_id)
      # Optional - return nil if not supported
      nil
    end

    # Test connection/credentials
    def test_connection
      raise NotImplementedError, "Subclass must implement #test_connection"
    end

    # Setup webhook on platform (if required)
    def setup_webhook(webhook_url)
      # Optional - not all platforms require this
      Rails.logger.info "Webhook setup not required for #{platform_name}"
      true
    end

    protected

    def credentials
      @credentials ||= fetch_credentials
    end

    def fetch_credentials
      provider = Security::VaultCredentialProvider.new(account_id: channel.account_id)
      creds = provider.get_credential(
        credential_type: :chat_channel,
        credential_id: channel.id,
        record: channel
      )

      raise AuthenticationError, "No credentials found for channel #{channel.id}" if creds.blank?

      creds.with_indifferent_access
    end

    def http_client
      @http_client ||= HTTP.timeout(connect: 5, write: 10, read: 30)
    end

    def handle_api_error(response, context = "API call")
      case response.status
      when 401, 403
        raise AuthenticationError, "#{context} authentication failed: #{response.status}"
      when 429
        raise RateLimitError, "#{context} rate limited: #{response.body}"
      when 400..499
        raise AdapterError, "#{context} client error: #{response.status} - #{response.body}"
      when 500..599
        raise AdapterError, "#{context} server error: #{response.status}"
      end
    end

    def log_api_call(method, url, response_status)
      Rails.logger.info "[#{platform_name}] #{method} #{url} -> #{response_status}"
    end

    def with_retry(max_attempts: 3)
      attempts = 0
      begin
        attempts += 1
        yield
      rescue RateLimitError, HTTP::ConnectionError => e
        if attempts < max_attempts
          sleep(2 ** attempts)
          retry
        end
        raise
      end
    end
  end
end
