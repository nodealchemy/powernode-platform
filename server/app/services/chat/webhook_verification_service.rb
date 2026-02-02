# frozen_string_literal: true

module Chat
  class WebhookVerificationService
    class VerificationError < StandardError; end
    class InvalidSignature < VerificationError; end
    class InvalidTimestamp < VerificationError; end
    class ReplayAttack < VerificationError; end

    # Maximum age for webhook timestamp (prevent replay attacks)
    TIMESTAMP_TOLERANCE = 5.minutes

    def initialize(channel)
      @channel = channel
      @platform = channel.platform
    end

    def verify!(request)
      case @platform
      when "whatsapp"
        verify_whatsapp!(request)
      when "telegram"
        verify_telegram!(request)
      when "discord"
        verify_discord!(request)
      when "slack"
        verify_slack!(request)
      when "mattermost"
        verify_mattermost!(request)
      else
        raise VerificationError, "Unknown platform: #{@platform}"
      end
    end

    def verify(request)
      verify!(request)
      true
    rescue VerificationError => e
      Rails.logger.warn "Webhook verification failed for #{@platform}: #{e.message}"
      false
    end

    private

    def credentials
      @credentials ||= begin
        provider = Security::VaultCredentialProvider.new(account_id: @channel.account_id)
        creds = provider.get_credential(
          credential_type: :chat_channel,
          credential_id: @channel.id,
          record: @channel
        )
        creds&.with_indifferent_access || {}
      end
    end

    # WhatsApp - HMAC-SHA256 with X-Hub-Signature-256 header
    def verify_whatsapp!(request)
      signature_header = request.headers["X-Hub-Signature-256"]
      raise InvalidSignature, "Missing X-Hub-Signature-256 header" if signature_header.blank?

      app_secret = credentials[:app_secret]
      raise VerificationError, "WhatsApp app_secret not configured" if app_secret.blank?

      body = request.raw_post
      expected_signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", app_secret, body)

      unless secure_compare(signature_header, expected_signature)
        raise InvalidSignature, "WhatsApp signature mismatch"
      end

      # Check for replay (Meta includes timestamp in payload)
      check_meta_timestamp(request)
    end

    # Telegram - Secret token in X-Telegram-Bot-Api-Secret-Token header
    def verify_telegram!(request)
      secret_token = request.headers["X-Telegram-Bot-Api-Secret-Token"]
      expected_token = credentials[:webhook_secret] || @channel.webhook_token

      if secret_token.present? && expected_token.present?
        unless secure_compare(secret_token, expected_token)
          raise InvalidSignature, "Telegram secret token mismatch"
        end
      else
        # Fallback: verify by webhook token in URL
        verify_webhook_token!(request)
      end
    end

    # Discord - Ed25519 signature verification
    def verify_discord!(request)
      signature = request.headers["X-Signature-Ed25519"]
      timestamp = request.headers["X-Signature-Timestamp"]

      raise InvalidSignature, "Missing Discord signature headers" if signature.blank? || timestamp.blank?

      public_key = credentials[:public_key]
      raise VerificationError, "Discord public_key not configured" if public_key.blank?

      # Check timestamp to prevent replay
      check_timestamp!(timestamp.to_i)

      # Verify Ed25519 signature
      body = request.raw_post
      message = timestamp + body

      begin
        verify_key = Ed25519::VerifyKey.new([public_key].pack("H*"))
        verify_key.verify([signature].pack("H*"), message)
      rescue Ed25519::VerifyError, ArgumentError => e
        raise InvalidSignature, "Discord Ed25519 verification failed: #{e.message}"
      end
    end

    # Slack - HMAC-SHA256 with X-Slack-Signature header
    def verify_slack!(request)
      slack_signature = request.headers["X-Slack-Signature"]
      slack_timestamp = request.headers["X-Slack-Request-Timestamp"]

      raise InvalidSignature, "Missing Slack signature headers" if slack_signature.blank? || slack_timestamp.blank?

      # Check timestamp
      check_timestamp!(slack_timestamp.to_i)

      signing_secret = credentials[:signing_secret]
      raise VerificationError, "Slack signing_secret not configured" if signing_secret.blank?

      # Build signature base string
      body = request.raw_post
      sig_basestring = "v0:#{slack_timestamp}:#{body}"

      # Calculate expected signature
      expected_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)

      unless secure_compare(slack_signature, expected_signature)
        raise InvalidSignature, "Slack signature mismatch"
      end
    end

    # Mattermost - Bearer token or HMAC-SHA256
    def verify_mattermost!(request)
      # Mattermost can use either token-based or signature-based verification
      token = request.headers["Authorization"]&.sub(/^Bearer\s+/i, "")

      if token.present?
        expected_token = credentials[:webhook_token] || @channel.webhook_token
        unless secure_compare(token, expected_token)
          raise InvalidSignature, "Mattermost token mismatch"
        end
      else
        # Fallback to URL token verification
        verify_webhook_token!(request)
      end
    end

    def verify_webhook_token!(request)
      token = request.params[:token] || request.path.split("/").last

      unless secure_compare(token.to_s, @channel.webhook_token)
        raise InvalidSignature, "Webhook token mismatch"
      end
    end

    def check_timestamp!(timestamp)
      request_time = Time.at(timestamp)
      current_time = Time.current

      if (current_time - request_time).abs > TIMESTAMP_TOLERANCE
        raise InvalidTimestamp, "Request timestamp too old or in future"
      end

      # Check for replay (store seen signatures briefly)
      check_replay!(timestamp)
    end

    def check_meta_timestamp(request)
      # Meta platforms include timestamp in payload
      payload = JSON.parse(request.raw_post) rescue {}
      entry = payload.dig("entry", 0, "time")

      if entry.present?
        entry_time = Time.at(entry / 1000.0)
        if (Time.current - entry_time).abs > TIMESTAMP_TOLERANCE
          raise InvalidTimestamp, "Meta webhook timestamp too old"
        end
      end
    end

    def check_replay!(timestamp)
      cache_key = "webhook_replay:#{@channel.id}:#{timestamp}"

      if Rails.cache.exist?(cache_key)
        raise ReplayAttack, "Duplicate webhook detected"
      end

      # Store for replay detection
      Rails.cache.write(cache_key, true, expires_in: TIMESTAMP_TOLERANCE * 2)
    end

    def secure_compare(a, b)
      return false if a.nil? || b.nil?

      ActiveSupport::SecurityUtils.secure_compare(a, b)
    end
  end
end
