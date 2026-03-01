# frozen_string_literal: true

module Ai
  module Security
    class AgentIdentityService
      # OWASP ASI03 - Identity & Access Management for AI Agents
      # Provides Ed25519 keypair generation, signing, verification, rotation, and revocation.

      OVERLAP_WINDOW = 24.hours
      DEFAULT_EXPIRY = 365.days
      ATTESTATION_TOKEN_TTL = 1.hour

      class IdentityError < StandardError; end
      class SigningError < StandardError; end
      class VerificationError < StandardError; end

      def initialize(account:)
        @account = account
      end

      # Provision a new Ed25519 identity for an agent.
      # Returns the created AgentIdentity record.
      def provision!(agent:)
        keypair = generate_ed25519_keypair
        public_pem = keypair.public_to_pem
        private_pem = keypair.private_to_pem
        fingerprint = generate_fingerprint(public_pem)
        agent_uri = build_agent_uri(agent)

        identity = Ai::AgentIdentity.create!(
          account: @account,
          agent_id: agent.id,
          public_key: public_pem,
          encrypted_private_key: encrypt_private_key(private_pem),
          key_fingerprint: fingerprint,
          algorithm: "ed25519",
          status: "active",
          agent_uri: agent_uri,
          attestation_claims: build_attestation_claims(agent),
          capabilities: agent.respond_to?(:skill_slugs) ? agent.skill_slugs : [],
          expires_at: DEFAULT_EXPIRY.from_now
        )

        audit_log("identity_provisioned", agent: agent, outcome: "allowed",
                  details: { identity_id: identity.id, fingerprint: fingerprint })

        identity
      rescue StandardError => e
        Rails.logger.error "[AgentIdentityService] provision! failed: #{e.message}"
        raise IdentityError, "Failed to provision identity: #{e.message}"
      end

      # Sign a payload with the agent's active Ed25519 private key.
      # Returns a Base64-encoded signature string.
      def sign(agent:, payload:)
        identity = active_identity_for(agent)
        raise SigningError, "No active identity for agent #{agent.id}" unless identity

        private_key = load_private_key(identity)
        payload_bytes = payload.is_a?(String) ? payload : payload.to_json
        signature = private_key.sign(nil, payload_bytes)

        Base64.strict_encode64(signature)
      rescue OpenSSL::PKey::PKeyError => e
        Rails.logger.error "[AgentIdentityService] sign failed: #{e.message}"
        raise SigningError, "Signing failed: #{e.message}"
      end

      # Verify a signature against an agent's public key.
      # Returns { valid: bool, identity_id: UUID, reason: String|nil }
      def verify(agent_id:, payload:, signature:)
        identities = Ai::AgentIdentity.for_agent(agent_id).where(status: %w[active rotated]).not_expired
        return { valid: false, identity_id: nil, reason: "No usable identity found" } if identities.empty?

        payload_bytes = payload.is_a?(String) ? payload : payload.to_json
        signature_bytes = Base64.strict_decode64(signature)

        identities.each do |identity|
          next unless identity.usable?

          public_key = OpenSSL::PKey.read(identity.public_key)
          if public_key.verify(nil, signature_bytes, payload_bytes)
            audit_log("signature_verified", agent_id: agent_id, outcome: "allowed",
                      details: { identity_id: identity.id })
            return { valid: true, identity_id: identity.id, reason: nil }
          end
        rescue OpenSSL::PKey::PKeyError => e
          Rails.logger.warn "[AgentIdentityService] verify key error for identity #{identity.id}: #{e.message}"
          next
        end

        audit_log("signature_verification_failed", agent_id: agent_id, outcome: "denied",
                  details: { checked_identities: identities.count })
        { valid: false, identity_id: nil, reason: "Signature verification failed" }
      rescue ArgumentError => e
        { valid: false, identity_id: nil, reason: "Invalid signature format: #{e.message}" }
      end

      # Rotate the agent's identity keypair, setting an overlap window on the old key.
      def rotate!(agent:)
        old_identity = active_identity_for(agent)
        raise IdentityError, "No active identity to rotate for agent #{agent.id}" unless old_identity

        new_identity = provision!(agent: agent)

        old_identity.update!(
          status: "rotated",
          rotated_at: Time.current,
          rotation_overlap_until: OVERLAP_WINDOW.from_now
        )

        audit_log("identity_rotated", agent: agent, outcome: "allowed",
                  details: { old_identity_id: old_identity.id, new_identity_id: new_identity.id })

        new_identity
      end

      # Revoke an agent's identity, disabling all signing/verification.
      def revoke!(agent:, reason:)
        identities = Ai::AgentIdentity.for_agent(agent.id).active
        count = identities.count

        identities.find_each do |identity|
          identity.update!(
            status: "revoked",
            revoked_at: Time.current,
            revocation_reason: reason
          )
        end

        audit_log("identity_revoked", agent: agent, outcome: "blocked",
                  details: { reason: reason, revoked_count: count })

        { revoked_count: count, reason: reason }
      end

      # Generate a time-bounded attestation token (JWT-like) with Ed25519 signing.
      def attestation_token(agent:, capabilities: [])
        identity = active_identity_for(agent)
        raise IdentityError, "No active identity for attestation" unless identity

        now = Time.current
        claims = {
          iss: "powernode.io",
          sub: agent.id,
          aud: "powernode-agents",
          iat: now.to_i,
          exp: (now + ATTESTATION_TOKEN_TTL).to_i,
          jti: SecureRandom.uuid,
          kid: identity.key_fingerprint,
          capabilities: capabilities.presence || identity.capabilities,
          agent_uri: identity.agent_uri,
          trust_tier: agent.respond_to?(:trust_score) ? agent.trust_score&.tier : nil
        }.compact

        payload_json = claims.to_json
        signature = sign(agent: agent, payload: payload_json)

        # Return a simple token format: base64(claims).base64(signature)
        "#{Base64.urlsafe_encode64(payload_json)}.#{signature}"
      end

      private

      def active_identity_for(agent)
        Ai::AgentIdentity.for_agent(agent.id).active.not_expired.order(created_at: :desc).first
      end

      def generate_ed25519_keypair
        OpenSSL::PKey.generate_key("ED25519")
      end

      def encrypt_private_key(key_pem)
        ::Security::CredentialEncryptionService.encrypt_value(key_pem, namespace: "agent_identity")
      end

      def decrypt_private_key(encrypted)
        ::Security::CredentialEncryptionService.decrypt_value(encrypted, namespace: "agent_identity")
      end

      def load_private_key(identity)
        pem = decrypt_private_key(identity.encrypted_private_key)
        OpenSSL::PKey.read(pem)
      end

      def generate_fingerprint(public_key_pem)
        Digest::SHA256.hexdigest(public_key_pem)
      end

      def build_agent_uri(agent)
        capability = agent.respond_to?(:agent_type) ? agent.agent_type : "general"
        "agent://powernode.io/workflow/#{capability}/#{agent.id}"
      end

      def build_attestation_claims(agent)
        {
          provisioned_at: Time.current.iso8601,
          agent_type: agent.respond_to?(:agent_type) ? agent.agent_type : nil,
          account_id: @account.id
        }.compact
      end

      def audit_log(action, agent: nil, agent_id: nil, outcome:, details: {})
        Ai::SecurityAuditTrail.log!(
          action: action,
          outcome: outcome,
          account: @account,
          agent_id: agent_id || agent&.id,
          asi_reference: "ASI03",
          csa_pillar: "identity",
          source_service: "AgentIdentityService",
          severity: outcome == "blocked" ? "warning" : "info",
          details: details
        )
      rescue StandardError => e
        Rails.logger.error "[AgentIdentityService] audit_log failed: #{e.message}"
      end
    end
  end
end
