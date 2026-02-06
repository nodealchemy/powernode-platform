# frozen_string_literal: true

module Ai
  module A2a
    class SecurityCardSigner
      SIGNING_ALGORITHM = "RS256"
      CARD_VALIDITY_HOURS = 24

      class SigningError < StandardError; end

      def initialize(account:)
        @account = account
      end

      def sign_card(agent_card)
        card_data = agent_card.to_a2a_json
        card_data[:security] = build_security_section(agent_card)

        payload = {
          card: card_data,
          iss: issuer_id,
          iat: Time.current.to_i,
          exp: CARD_VALIDITY_HOURS.hours.from_now.to_i,
          aud: "a2a-discovery"
        }

        signature = sign_payload(payload)

        {
          signed_card: card_data.merge(
            security: card_data[:security].merge(
              signature: signature,
              signed_at: Time.current.iso8601,
              valid_until: CARD_VALIDITY_HOURS.hours.from_now.iso8601
            )
          ),
          signature: signature
        }
      end

      def verify_signed_card(signed_card_data)
        security = signed_card_data[:security] || signed_card_data["security"]
        return { valid: false, reason: "No security section" } unless security

        signature = security[:signature] || security["signature"]
        return { valid: false, reason: "No signature" } unless signature

        valid_until = security[:valid_until] || security["valid_until"]
        if valid_until && Time.parse(valid_until) < Time.current
          return { valid: false, reason: "Card signature expired" }
        end

        issuer = security[:issuer] || security["issuer"]
        card_without_sig = signed_card_data.deep_dup
        card_security = card_without_sig[:security] || card_without_sig["security"]
        card_security&.delete(:signature)
        card_security&.delete("signature")

        verified = verify_signature(card_without_sig, signature, issuer)

        if verified
          { valid: true, issuer: issuer, verified_at: Time.current.iso8601 }
        else
          { valid: false, reason: "Signature verification failed" }
        end
      rescue StandardError => e
        { valid: false, reason: "Verification error: #{e.message}" }
      end

      private

      def build_security_section(agent_card)
        {
          issuer: issuer_id,
          algorithm: SIGNING_ALGORITHM,
          authentication: agent_card.authentication&.dig("schemes") || [],
          permissions: agent_card.capabilities&.dig("permissions") || [],
          data_classification: determine_data_classification(agent_card)
        }
      end

      def determine_data_classification(agent_card)
        capabilities = agent_card.capabilities || {}
        if capabilities["handles_pii"]
          "confidential"
        elsif capabilities["internal_only"]
          "internal"
        else
          "public"
        end
      end

      def issuer_id
        "powernode:#{@account.id}"
      end

      def sign_payload(payload)
        key = signing_key
        return hmac_sign(payload) unless key

        digest = OpenSSL::Digest::SHA256.new
        signature = key.sign(digest, payload.to_json)
        Base64.strict_encode64(signature)
      rescue StandardError => e
        Rails.logger.warn "[SecurityCardSigner] RSA signing failed, falling back to HMAC: #{e.message}"
        hmac_sign(payload)
      end

      def verify_signature(card_data, signature, issuer)
        # For same-account verification, use HMAC
        if issuer&.start_with?("powernode:")
          expected = hmac_sign(card_data)
          ActiveSupport::SecurityUtils.secure_compare(signature, expected)
        else
          false
        end
      end

      def hmac_sign(data)
        secret = signing_secret
        OpenSSL::HMAC.hexdigest("SHA256", secret, data.to_json)
      end

      def signing_key
        key_pem = ENV["A2A_SIGNING_PRIVATE_KEY"]
        return nil unless key_pem

        OpenSSL::PKey::RSA.new(key_pem)
      rescue OpenSSL::PKey::RSAError
        nil
      end

      def signing_secret
        ENV.fetch("A2A_SIGNING_SECRET") { Rails.application.secret_key_base[0..31] }
      end
    end
  end
end
