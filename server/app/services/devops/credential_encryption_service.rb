# frozen_string_literal: true

module Devops
  class CredentialEncryptionService
    ALGORITHM = "aes-256-gcm"
    KEY_LENGTH = 32
    IV_LENGTH = 12
    AUTH_TAG_LENGTH = 16

    class EncryptionError < StandardError; end
    class DecryptionError < StandardError; end

    class << self
      # Encrypt credentials for an Devops::IntegrationCredential record
      def encrypt(credential_record, credentials_hash)
        raise EncryptionError, "Invalid credential record" unless credential_record.is_a?(Devops::IntegrationCredential)
        raise EncryptionError, "Credentials must be a hash" unless credentials_hash.is_a?(Hash)

        encrypted = encrypt_data(credentials_hash.to_json)
        credential_record.update!(encrypted_credentials: encrypted)

        true
      end

      # Decrypt credentials from an Devops::IntegrationCredential record
      def decrypt(credential_record)
        raise DecryptionError, "Invalid credential record" unless credential_record.is_a?(Devops::IntegrationCredential)
        return {} if credential_record.encrypted_credentials.blank?

        decrypted_json = decrypt_data(credential_record.encrypted_credentials)
        JSON.parse(decrypted_json).with_indifferent_access
      rescue JSON::ParserError => e
        raise DecryptionError, "Failed to parse decrypted credentials: #{e.message}"
      end

      # Decrypt encrypted data string (for standalone use)
      def decrypt_data(ciphertext, _key_id = nil)
        raise DecryptionError, "Cannot decrypt nil or empty data" if ciphertext.blank?

        combined = Base64.strict_decode64(ciphertext)

        iv = combined[0, IV_LENGTH]
        auth_tag = combined[IV_LENGTH, AUTH_TAG_LENGTH]
        encrypted = combined[IV_LENGTH + AUTH_TAG_LENGTH..]

        cipher = OpenSSL::Cipher.new(ALGORITHM)
        cipher.decrypt

        cipher.key = encryption_key
        cipher.iv = iv
        cipher.auth_tag = auth_tag

        cipher.update(encrypted) + cipher.final
      rescue ArgumentError => e
        raise DecryptionError, "Invalid base64 encoding: #{e.message}"
      rescue OpenSSL::Cipher::CipherError => e
        raise DecryptionError, "Decryption failed: #{e.message}"
      end

      # Encrypt raw data (for standalone use)
      def encrypt_data(plaintext)
        raise EncryptionError, "Cannot encrypt nil or empty data" if plaintext.blank?

        cipher = OpenSSL::Cipher.new(ALGORITHM)
        cipher.encrypt

        key = encryption_key
        iv = cipher.random_iv

        cipher.key = key
        cipher.iv = iv

        encrypted = cipher.update(plaintext) + cipher.final
        auth_tag = cipher.auth_tag

        # Combine IV + auth_tag + encrypted data and encode
        combined = iv + auth_tag + encrypted
        Base64.strict_encode64(combined)
      rescue OpenSSL::Cipher::CipherError => e
        raise EncryptionError, "Encryption failed: #{e.message}"
      end

      # Get current encryption key ID
      def current_key_id
        "primary"
      end

      # Rotate encryption key for a credential record
      def rotate_key(credential_record, new_key: nil)
        # Decrypt with current key
        credentials = decrypt(credential_record)

        # Re-encrypt with new key (or regenerated key if not provided)
        if new_key.present?
          with_temporary_key(new_key) do
            encrypt(credential_record, credentials)
          end
        else
          encrypt(credential_record, credentials)
        end

        true
      end

      # Validate that credentials can be decrypted
      def valid?(credential_record)
        decrypt(credential_record)
        true
      rescue DecryptionError
        false
      end

      # Mask sensitive credential fields for display
      def mask_credentials(credentials_hash, visible_chars: 4)
        return {} unless credentials_hash.is_a?(Hash)

        credentials_hash.transform_values do |value|
          mask_value(value, visible_chars: visible_chars)
        end
      end

      # Generate a new encryption key
      def generate_key
        Base64.strict_encode64(SecureRandom.random_bytes(KEY_LENGTH))
      end

      private

      def encryption_key
        key_base64 = ENV.fetch("INTEGRATION_CREDENTIAL_ENCRYPTION_KEY") do
          # Fallback to Rails secret key base for development
          Rails.application.secret_key_base[0, KEY_LENGTH]
        end

        # Decode if base64 encoded, otherwise use directly
        if base64_encoded?(key_base64) && key_base64.length > KEY_LENGTH
          decoded = Base64.strict_decode64(key_base64)
          decoded[0, KEY_LENGTH]
        else
          key_base64.to_s[0, KEY_LENGTH]
        end
      end

      def base64_encoded?(string)
        return false if string.nil?

        Base64.strict_decode64(string)
        true
      rescue ArgumentError
        false
      end

      def with_temporary_key(key)
        original_key = ENV["INTEGRATION_CREDENTIAL_ENCRYPTION_KEY"]
        ENV["INTEGRATION_CREDENTIAL_ENCRYPTION_KEY"] = key
        yield
      ensure
        ENV["INTEGRATION_CREDENTIAL_ENCRYPTION_KEY"] = original_key
      end

      def mask_value(value, visible_chars:)
        return value unless value.is_a?(String)
        return "***" if value.length <= visible_chars

        visible = value[-visible_chars..]
        "#{"*" * (value.length - visible_chars)}#{visible}"
      end
    end
  end
end
