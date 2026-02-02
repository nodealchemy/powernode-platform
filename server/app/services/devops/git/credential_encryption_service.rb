# frozen_string_literal: true

module Devops
  module Git
  class CredentialEncryptionService
    class EncryptionError < StandardError; end
    class DecryptionError < StandardError; end

    class << self
      def encrypt(credentials_hash)
        raise EncryptionError, "Credentials must be a hash" unless credentials_hash.is_a?(Hash)
        return nil if credentials_hash.blank?

        json_data = credentials_hash.to_json
        encrypted_data = encryptor.encrypt_and_sign(json_data)
        Base64.strict_encode64(encrypted_data)
      rescue StandardError => e
        Rails.logger.error "Devops::Git::CredentialEncryptionService encrypt error: #{e.message}"
        raise EncryptionError, "Failed to encrypt credentials: #{e.message}"
      end

      def decrypt(encrypted_data, key_id = nil)
        return {} if encrypted_data.blank?

        decoded_data = Base64.strict_decode64(encrypted_data)
        json_data = encryptor(key_id).decrypt_and_verify(decoded_data)
        JSON.parse(json_data)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage => e
        Rails.logger.error "Devops::Git::CredentialEncryptionService decrypt error: Invalid message"
        raise DecryptionError, "Failed to decrypt credentials: Invalid encryption"
      rescue JSON::ParserError => e
        Rails.logger.error "Devops::Git::CredentialEncryptionService decrypt error: Invalid JSON"
        raise DecryptionError, "Failed to decrypt credentials: Invalid data format"
      rescue StandardError => e
        Rails.logger.error "Devops::Git::CredentialEncryptionService decrypt error: #{e.message}"
        raise DecryptionError, "Failed to decrypt credentials: #{e.message}"
      end

      def current_key_id
        # Return a key identifier for the current encryption key
        # This allows for key rotation by tracking which key was used
        key_hash = Digest::SHA256.hexdigest(encryption_key)[0..7]
        "git_cred_#{key_hash}"
      end

      def rotate_credentials(credential, new_key_id = nil)
        # Decrypt with old key and re-encrypt with new key
        credentials = credential.credentials
        credential.credentials = credentials
        credential.save!
      end

      private

      def encryptor(key_id = nil)
        # In production, you might use different keys based on key_id for rotation
        # For now, we use a single key derived from the secret key base
        ActiveSupport::MessageEncryptor.new(encryption_key)
      end

      def encryption_key
        # Derive a 32-byte key from the application secret
        key_base = Rails.application.credentials.secret_key_base ||
                   ENV.fetch("SECRET_KEY_BASE", "development_secret_key_base_for_testing")

        # Use HKDF to derive a purpose-specific key
        OpenSSL::KDF.hkdf(
          key_base,
          salt: "git_credentials_encryption",
          info: "git_ai_provider_credentials",
          length: 32,
          hash: "SHA256"
        )
      end
    end
  end
  end

# Backwards compatibility alias
GitCredentialEncryptionService = Devops::Git::CredentialEncryptionService unless defined?(GitCredentialEncryptionService)
end
