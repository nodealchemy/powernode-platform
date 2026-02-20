# frozen_string_literal: true

module Ai
  module Security
    class EncryptedCommunicationService
      # OWASP ASI07 - Secure Agent Communication
      # Implements X25519 ECDH key exchange + AES-256-GCM encryption for inter-agent messaging.

      SESSION_TTL = 1.hour
      CIPHER_ALGORITHM = "aes-256-gcm"
      NONCE_LENGTH = 12
      KEY_LENGTH = 32

      class CommunicationError < StandardError; end
      class SessionError < StandardError; end
      class DecryptionError < StandardError; end

      def initialize(account:)
        @account = account
        @redis = Redis.new(url: redis_url)
      end

      # Establish an encrypted session between two agents via X25519 ECDH.
      # Returns session_id string.
      def establish_session!(agent_a:, agent_b:, task_id: nil)
        session_id = SecureRandom.uuid

        # Generate ephemeral X25519 keypairs for both sides
        key_a = OpenSSL::PKey.generate_key("X25519")
        key_b = OpenSSL::PKey.generate_key("X25519")

        # Derive shared secret via ECDH
        shared_secret = key_a.derive(key_b)

        # Derive session key via HKDF
        session_key = derive_session_key(shared_secret, session_id)

        # Store session key in Redis with TTL
        session_data = {
          key: Base64.strict_encode64(session_key),
          agent_a_id: agent_a.id,
          agent_b_id: agent_b.id,
          task_id: task_id,
          sequence: 0,
          established_at: Time.current.iso8601,
          ephemeral_public_key_a: Base64.strict_encode64(key_a.public_to_der),
          ephemeral_public_key_b: Base64.strict_encode64(key_b.public_to_der)
        }
        @redis.setex(session_redis_key(session_id), SESSION_TTL.to_i, session_data.to_json)

        # Initialize atomic sequence counter
        seq_key = "#{session_redis_key(session_id)}:seq"
        @redis.setex(seq_key, SESSION_TTL.to_i, "0")

        audit_log("session_established", outcome: "allowed",
                  details: { session_id: session_id, agent_a: agent_a.id, agent_b: agent_b.id, task_id: task_id })

        session_id
      rescue StandardError => e
        Rails.logger.error "[EncryptedCommunication] establish_session! failed: #{e.message}"
        raise SessionError, "Failed to establish session: #{e.message}"
      end

      # Encrypt a plaintext message within a session.
      # Returns the created EncryptedMessage record.
      def encrypt(session_id:, from_agent_id:, to_agent_id:, plaintext:, metadata: {})
        session = load_session(session_id)
        raise SessionError, "Session not found or expired" unless session

        session_key = Base64.strict_decode64(session["key"])
        sequence = increment_sequence(session_id)

        # Build AAD
        aad_data = build_aad(
          from_agent_id: from_agent_id,
          to_agent_id: to_agent_id,
          task_id: session["task_id"],
          timestamp: Time.current.iso8601,
          sequence: sequence
        )
        aad_json = aad_data.to_json

        # AES-256-GCM encrypt
        cipher = OpenSSL::Cipher.new(CIPHER_ALGORITHM)
        cipher.encrypt
        cipher.key = session_key
        nonce = cipher.random_iv
        cipher.auth_data = aad_json

        ciphertext = cipher.update(plaintext) + cipher.final
        auth_tag = cipher.auth_tag

        # Sign the envelope with the sender's identity (if available)
        identity_service = AgentIdentityService.new(account: @account)
        envelope = { session_id: session_id, sequence: sequence, aad: aad_json }.to_json
        signature = begin
          agent = Ai::Agent.find(from_agent_id)
          identity_service.sign(agent: agent, payload: envelope)
        rescue StandardError
          nil
        end

        message = Ai::EncryptedMessage.create!(
          account: @account,
          from_agent_id: from_agent_id,
          to_agent_id: to_agent_id,
          task_id: session["task_id"],
          nonce: nonce,
          ciphertext: ciphertext,
          auth_tag: auth_tag,
          aad: aad_json,
          signature: signature,
          ephemeral_public_key: session["ephemeral_public_key_a"],
          sequence_number: sequence,
          session_id: session_id,
          status: "delivered"
        )

        audit_log("message_encrypted", outcome: "allowed",
                  details: { session_id: session_id, message_id: message.id, sequence: sequence })

        message
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "[EncryptedCommunication] encrypt record invalid: #{e.message}"
        raise CommunicationError, "Failed to store encrypted message: #{e.message}"
      end

      # Decrypt an encrypted message by its record ID.
      # Returns the decrypted plaintext string.
      def decrypt(message_id:)
        message = Ai::EncryptedMessage.find(message_id)
        session = load_session(message.session_id)
        raise SessionError, "Session not found or expired for message #{message_id}" unless session

        session_key = Base64.strict_decode64(session["key"])

        # Verify anti-replay
        verify_anti_replay(message.session_id, message.sequence_number)

        # Verify signature if present
        if message.signature.present?
          verify_result = AgentIdentityService.new(account: @account)
            .verify(
              agent_id: message.from_agent_id,
              payload: { session_id: message.session_id, sequence: message.sequence_number, aad: message.aad }.to_json,
              signature: message.signature
            )
          unless verify_result[:valid]
            audit_log("message_signature_invalid", outcome: "denied",
                      details: { message_id: message.id, reason: verify_result[:reason] })
            raise DecryptionError, "Message signature verification failed: #{verify_result[:reason]}"
          end
        end

        # AES-256-GCM decrypt
        cipher = OpenSSL::Cipher.new(CIPHER_ALGORITHM)
        cipher.decrypt
        cipher.key = session_key
        cipher.iv = message.nonce
        cipher.auth_tag = message.auth_tag
        cipher.auth_data = message.aad || ""

        plaintext = cipher.update(message.ciphertext) + cipher.final

        message.mark_read!

        audit_log("message_decrypted", outcome: "allowed",
                  details: { session_id: message.session_id, message_id: message.id })

        plaintext
      rescue OpenSSL::Cipher::CipherError => e
        Rails.logger.error "[EncryptedCommunication] decrypt cipher error: #{e.message}"
        raise DecryptionError, "Decryption failed: #{e.message}"
      end

      # Close a session, zeroing key material from Redis.
      def close_session!(session_id:)
        session = load_session(session_id)

        if session
          # Mark remaining delivered messages as expired
          Ai::EncryptedMessage.for_session(session_id).delivered.find_each(&:mark_expired!)
        end

        # Delete session key and sequence counter from Redis
        @redis.del(session_redis_key(session_id))
        @redis.del("#{session_redis_key(session_id)}:seq")

        audit_log("session_closed", outcome: "allowed", details: { session_id: session_id })

        { closed: true, session_id: session_id }
      rescue StandardError => e
        Rails.logger.error "[EncryptedCommunication] close_session! failed: #{e.message}"
        raise SessionError, "Failed to close session: #{e.message}"
      end

      private

      def redis_url
        Rails.application.credentials.redis_url || ENV.fetch("REDIS_URL", "redis://localhost:6379")
      end

      def session_redis_key(session_id)
        "powernode:encrypted_session:#{session_id}"
      end

      def load_session(session_id)
        data = @redis.get(session_redis_key(session_id))
        return nil unless data

        JSON.parse(data)
      rescue JSON::ParserError
        nil
      end

      def increment_sequence(session_id)
        seq_key = "#{session_redis_key(session_id)}:seq"
        @redis.incr(seq_key).to_i
      end

      def derive_session_key(shared_secret, salt)
        OpenSSL::KDF.hkdf(
          shared_secret,
          salt: salt.to_s,
          info: "powernode-agent-communication",
          length: KEY_LENGTH,
          hash: "SHA256"
        )
      end

      def build_aad(from_agent_id:, to_agent_id:, task_id:, timestamp:, sequence:)
        {
          from_agent_id: from_agent_id,
          to_agent_id: to_agent_id,
          task_id: task_id,
          timestamp: timestamp,
          sequence: sequence
        }.compact
      end

      def verify_anti_replay(session_id, sequence_number)
        # Check if this sequence number has already been processed
        processed_key = "powernode:encrypted_session:#{session_id}:processed"
        already_processed = @redis.sismember(processed_key, sequence_number.to_s)

        if already_processed
          raise DecryptionError, "Replay detected: sequence #{sequence_number} already processed"
        end

        @redis.sadd(processed_key, sequence_number.to_s)
        @redis.expire(processed_key, SESSION_TTL.to_i)
      end

      def audit_log(action, outcome:, details: {})
        Ai::SecurityAuditTrail.log!(
          action: action,
          outcome: outcome,
          account: @account,
          asi_reference: "ASI07",
          csa_pillar: "segmentation",
          source_service: "EncryptedCommunicationService",
          severity: outcome == "denied" ? "warning" : "info",
          details: details
        )
      rescue StandardError => e
        Rails.logger.error "[EncryptedCommunication] audit_log failed: #{e.message}"
      end
    end
  end
end
