# frozen_string_literal: true

module Security
  class WebhookAuthenticator
    class AuthenticationError < StandardError; end

    # Maximum time skew allowed for timestamp validation (5 minutes)
    MAX_TIME_SKEW = 300

    class << self
      # Verify HMAC-SHA256 signature (Slack, WhatsApp, GitHub style)
      def verify_hmac_sha256!(payload:, signature:, secret:, header_prefix: "sha256=")
        return false if payload.blank? || signature.blank? || secret.blank?

        expected_signature = "#{header_prefix}#{compute_hmac_sha256(payload, secret)}"

        unless secure_compare(expected_signature, signature)
          raise AuthenticationError, "Invalid HMAC-SHA256 signature"
        end

        true
      end

      # Verify Ed25519 signature (Discord style)
      def verify_ed25519!(payload:, signature:, timestamp:, public_key:)
        return false if payload.blank? || signature.blank? || public_key.blank?

        # Verify timestamp to prevent replay attacks
        verify_timestamp!(timestamp)

        message = "#{timestamp}#{payload}"

        begin
          signature_bytes = [ signature ].pack("H*")
          key_bytes = [ public_key ].pack("H*")

          verify_key = Ed25519::VerifyKey.new(key_bytes)
          verify_key.verify(signature_bytes, message)
        rescue StandardError => e
          raise AuthenticationError, "Invalid Ed25519 signature: #{e.message}"
        end

        true
      end

      # Verify Telegram secret token
      def verify_telegram_token!(request_token:, expected_token:)
        return false if request_token.blank? || expected_token.blank?

        unless secure_compare(request_token, expected_token)
          raise AuthenticationError, "Invalid Telegram secret token"
        end

        true
      end

      # Verify timestamp is within acceptable range
      def verify_timestamp!(timestamp, max_skew: MAX_TIME_SKEW)
        return if timestamp.blank?

        ts = timestamp.is_a?(Integer) ? timestamp : timestamp.to_i
        now = Time.current.to_i

        if (now - ts).abs > max_skew
          raise AuthenticationError, "Request timestamp too old or in the future"
        end

        true
      end

      # Generate webhook signature for outgoing webhooks
      def sign_webhook(payload:, secret:, algorithm: :hmac_sha256)
        case algorithm
        when :hmac_sha256
          "sha256=#{compute_hmac_sha256(payload, secret)}"
        else
          raise ArgumentError, "Unsupported algorithm: #{algorithm}"
        end
      end

      # Generate a secure webhook token
      def generate_token(length: 32)
        SecureRandom.urlsafe_base64(length)
      end

      private

      def compute_hmac_sha256(payload, secret)
        OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      end

      def secure_compare(a, b)
        return false if a.nil? || b.nil?
        return false if a.bytesize != b.bytesize

        ActiveSupport::SecurityUtils.secure_compare(a, b)
      end
    end
  end
end
