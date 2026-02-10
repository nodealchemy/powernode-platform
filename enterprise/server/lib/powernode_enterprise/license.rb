# frozen_string_literal: true

require "openssl"
require "json"
require "base64"

module PowernodeEnterprise
  module License
    GRACE_PERIOD_DAYS = 14

    class << self
      def valid?
        payload = decode_license
        return false unless payload

        edition = payload["edition"]
        return false unless %w[enterprise business].include?(edition)

        expires_at = Time.parse(payload["expires_at"]) rescue nil
        return false unless expires_at

        expires_at > Time.current
      end

      def grace_period?
        payload = decode_license
        return false unless payload

        expires_at = Time.parse(payload["expires_at"]) rescue nil
        return false unless expires_at
        return false if expires_at > Time.current # Not expired yet

        expires_at + GRACE_PERIOD_DAYS.days > Time.current
      end

      def grace_days_remaining
        payload = decode_license
        return 0 unless payload

        expires_at = Time.parse(payload["expires_at"]) rescue nil
        return 0 unless expires_at

        remaining = ((expires_at + GRACE_PERIOD_DAYS.days - Time.current) / 1.day).ceil
        [remaining, 0].max
      end

      def edition
        payload = decode_license
        payload&.dig("edition") || "community"
      end

      def max_users
        payload = decode_license
        payload&.dig("max_users") || 0
      end

      def features
        payload = decode_license
        payload&.dig("features") || []
      end

      def validate!
        raise LicenseError, "Invalid or missing enterprise license" unless valid? || grace_period?
      end

      private

      def decode_license
        @decoded_license ||= begin
          raw = license_key
          return nil if raw.blank?

          parts = raw.split(".")
          return nil unless parts.length == 2

          payload_b64, signature_b64 = parts
          payload_json = Base64.urlsafe_decode64(payload_b64)
          signature = Base64.urlsafe_decode64(signature_b64)

          # Verify HMAC-SHA256 signature
          secret = signing_secret
          expected_signature = OpenSSL::HMAC.digest("SHA256", secret, payload_json)

          unless ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
            Rails.logger.error "[PowernodeEnterprise] License signature verification failed"
            return nil
          end

          JSON.parse(payload_json)
        rescue StandardError => e
          Rails.logger.error "[PowernodeEnterprise] License decode error: #{e.message}"
          nil
        end
      end

      def license_key
        # Check environment variable first, then file
        ENV["POWERNODE_LICENSE_KEY"].presence ||
          license_file_contents
      end

      def license_file_contents
        file_path = Rails.root.join("..", "enterprise", "LICENSE_KEY")
        return nil unless File.exist?(file_path)

        File.read(file_path).strip.presence
      end

      def signing_secret
        ENV.fetch("POWERNODE_LICENSE_SECRET", "powernode-enterprise-default-secret")
      end
    end

    class LicenseError < StandardError; end
  end
end
