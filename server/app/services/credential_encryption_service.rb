# frozen_string_literal: true

# Application-level credential encryption service
# Provides reusable encryption/decryption for any type of credentials
# across all components (MCP servers, storage providers, email settings, etc.)
#
# Usage:
#   # Encrypt any hash of credentials
#   encrypted = CredentialEncryptionService.encrypt({ api_key: 'secret', token: 'value' })
#
#   # Decrypt to get original hash
#   credentials = CredentialEncryptionService.decrypt(encrypted)
#
#   # Encrypt a single value
#   encrypted_token = CredentialEncryptionService.encrypt_value('my-secret-token')
#   token = CredentialEncryptionService.decrypt_value(encrypted_token)
#
#   # Scoped encryption with namespace (for key isolation)
#   encrypted = CredentialEncryptionService.encrypt(data, namespace: 'mcp')
#   credentials = CredentialEncryptionService.decrypt(encrypted, namespace: 'mcp')
#
class CredentialEncryptionService
  ENCRYPTION_VERSION = "v2"
  KEY_ROTATION_INTERVAL = 90.days
  CIPHER_ALGORITHM = "AES-256-GCM"
  IV_LENGTH = 12  # 96 bits for GCM
  AUTH_TAG_LENGTH = 16  # 128 bits

  class EncryptionError < StandardError; end
  class DecryptionError < StandardError; end
  class InvalidKeyError < StandardError; end
  class KeyNotFoundError < StandardError; end

  class << self
    # ==========================================
    # Primary Encryption Methods
    # ==========================================

    # Encrypt a credentials hash and return encrypted string
    # @param credentials_hash [Hash] Credentials to encrypt
    # @param namespace [String, nil] Optional namespace for key isolation
    # @return [String] Base64-encoded encrypted payload
    def encrypt(credentials_hash, namespace: nil)
      raise ArgumentError, "Credentials must be a Hash" unless credentials_hash.is_a?(Hash)
      raise ArgumentError, "Credentials cannot be empty" if credentials_hash.empty?

      # Normalize keys to strings
      normalized = normalize_credentials(credentials_hash)

      # Convert to JSON
      json_data = normalized.to_json

      # Encrypt with current key
      key_id = current_key_id(namespace)
      encrypted_data = encrypt_data(json_data, key_id, namespace)

      # Return base64 encoded result with metadata
      Base64.strict_encode64({
        version: ENCRYPTION_VERSION,
        namespace: namespace,
        key_id: key_id,
        encrypted_data: encrypted_data,
        created_at: Time.current.to_i
      }.compact.to_json)
    rescue StandardError => e
      Rails.logger.error "[CredentialEncryptionService] Encryption failed: #{e.message}"
      raise EncryptionError, "Failed to encrypt credentials: #{e.message}"
    end

    # Decrypt credentials and return hash
    # @param encrypted_credentials [String] Encrypted payload
    # @param namespace [String, nil] Optional namespace (must match encryption namespace)
    # @return [Hash] Decrypted credentials
    def decrypt(encrypted_credentials, namespace: nil)
      raise ArgumentError, "Encrypted credentials cannot be blank" if encrypted_credentials.blank?

      begin
        # Decode base64 wrapper
        wrapper_data = JSON.parse(Base64.strict_decode64(encrypted_credentials))

        # Extract components
        version = wrapper_data["version"]
        stored_namespace = wrapper_data["namespace"]
        stored_key_id = wrapper_data["key_id"]
        encrypted_data = wrapper_data["encrypted_data"]

        # Validate namespace matches if provided
        if namespace.present? && stored_namespace != namespace
          raise DecryptionError, "Namespace mismatch: expected '#{namespace}', got '#{stored_namespace}'"
        end

        # Handle version compatibility
        effective_namespace = stored_namespace || namespace
        validate_version(version)

        # Decrypt data
        decrypted_json = decrypt_data(encrypted_data, stored_key_id, effective_namespace)

        # Parse and return credentials
        JSON.parse(decrypted_json)
      rescue JSON::ParserError => e
        raise DecryptionError, "Invalid encrypted credentials format: #{e.message}"
      rescue ArgumentError => e
        raise DecryptionError, "Base64 decoding failed: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "[CredentialEncryptionService] Decryption failed: #{e.message}"
        raise DecryptionError, "Failed to decrypt credentials: #{e.message}"
      end
    end

    # ==========================================
    # Single Value Encryption (Convenience)
    # ==========================================

    # Encrypt a single value
    # @param value [String] Value to encrypt
    # @param namespace [String, nil] Optional namespace
    # @return [String] Encrypted string
    def encrypt_value(value, namespace: nil)
      return nil if value.blank?

      encrypt({ value: value }, namespace: namespace)
    end

    # Decrypt a single value
    # @param encrypted_value [String] Encrypted payload
    # @param namespace [String, nil] Optional namespace
    # @return [String, nil] Decrypted value
    def decrypt_value(encrypted_value, namespace: nil)
      return nil if encrypted_value.blank?

      decrypt(encrypted_value, namespace: namespace)["value"]
    end

    # ==========================================
    # Validation Methods
    # ==========================================

    # Test if credentials can be decrypted
    # @param encrypted_credentials [String] Encrypted payload
    # @param namespace [String, nil] Optional namespace
    # @return [Boolean]
    def valid_encrypted_credentials?(encrypted_credentials, namespace: nil)
      decrypt(encrypted_credentials, namespace: namespace)
      true
    rescue StandardError
      false
    end

    # Check if the payload is encrypted with current key
    # @param encrypted_credentials [String] Encrypted payload
    # @param namespace [String, nil] Optional namespace
    # @return [Boolean]
    def encrypted_with_current_key?(encrypted_credentials, namespace: nil)
      return false if encrypted_credentials.blank?

      wrapper = JSON.parse(Base64.strict_decode64(encrypted_credentials))
      wrapper["key_id"] == current_key_id(namespace)
    rescue StandardError
      false
    end

    # ==========================================
    # Key Management
    # ==========================================

    # Get current encryption key ID for a namespace
    # @param namespace [String, nil] Optional namespace
    # @return [String]
    def current_key_id(namespace = nil)
      if namespace.present?
        Rails.application.credentials.dig(:encryption, namespace.to_sym, :current_key_id) ||
          Rails.application.credentials.dig(:encryption, :current_key_id) ||
          "default"
      else
        Rails.application.credentials.dig(:encryption, :current_key_id) || "default"
      end
    end

    # Get list of available encryption keys
    # @param namespace [String, nil] Optional namespace
    # @return [Array<String>]
    def available_keys(namespace = nil)
      if namespace.present?
        keys = Rails.application.credentials.dig(:encryption, namespace.to_sym, :keys)
        return keys.keys.map(&:to_s) if keys.present?
      end

      Rails.application.credentials.dig(:encryption, :keys)&.keys&.map(&:to_s) || [ "default" ]
    end

    # Check if key rotation is needed based on creation timestamp
    # @param encrypted_credentials [String] Encrypted payload
    # @param namespace [String, nil] Optional namespace
    # @return [Boolean]
    def key_rotation_needed?(encrypted_credentials, namespace: nil)
      return true if encrypted_credentials.blank?

      begin
        wrapper = JSON.parse(Base64.strict_decode64(encrypted_credentials))

        # Check if using old key
        return true if wrapper["key_id"] != current_key_id(namespace)

        # Check if created too long ago
        created_at = Time.at(wrapper["created_at"].to_i)
        created_at < KEY_ROTATION_INTERVAL.ago
      rescue StandardError
        true
      end
    end

    # Re-encrypt credentials with current key
    # @param encrypted_credentials [String] Encrypted payload
    # @param namespace [String, nil] Optional namespace
    # @return [String] Newly encrypted payload
    def rotate_encryption(encrypted_credentials, namespace: nil)
      decrypted = decrypt(encrypted_credentials, namespace: namespace)
      encrypt(decrypted, namespace: namespace)
    end

    # Generate a new random encryption key (for setup)
    # @return [String] Base64-encoded 32-byte key
    def generate_new_key
      SecureRandom.base64(32)
    end

    private

    # ==========================================
    # Internal Encryption Methods
    # ==========================================

    def normalize_credentials(hash)
      hash.transform_keys(&:to_s)
    end

    def encrypt_data(data, key_id, namespace)
      key = get_encryption_key(key_id, namespace)
      cipher = OpenSSL::Cipher.new(CIPHER_ALGORITHM)
      cipher.encrypt
      cipher.key = Base64.decode64(key)

      iv = cipher.random_iv
      encrypted_data = cipher.update(data) + cipher.final
      auth_tag = cipher.auth_tag

      # Combine IV, auth tag, and encrypted data
      Base64.strict_encode64(iv + auth_tag + encrypted_data)
    end

    def decrypt_data(encrypted_data_b64, key_id, namespace)
      key = get_encryption_key(key_id, namespace)
      cipher = OpenSSL::Cipher.new(CIPHER_ALGORITHM)
      cipher.decrypt
      cipher.key = Base64.decode64(key)

      # Decode and extract components
      combined_data = Base64.strict_decode64(encrypted_data_b64)
      iv = combined_data[0...IV_LENGTH]
      auth_tag = combined_data[IV_LENGTH...(IV_LENGTH + AUTH_TAG_LENGTH)]
      encrypted_data = combined_data[(IV_LENGTH + AUTH_TAG_LENGTH)..-1]

      cipher.iv = iv
      cipher.auth_tag = auth_tag

      cipher.update(encrypted_data) + cipher.final
    end

    def get_encryption_key(key_id, namespace = nil)
      key = nil

      # Try namespace-specific key first
      if namespace.present?
        key = Rails.application.credentials.dig(:encryption, namespace.to_sym, :keys, key_id.to_sym)
      end

      # Fall back to global encryption keys
      key ||= Rails.application.credentials.dig(:encryption, :keys, key_id.to_sym)

      # Fall back to legacy AI encryption keys (backwards compatibility)
      key ||= Rails.application.credentials.dig(:ai_encryption, :keys, key_id.to_sym)

      # Generate fallback key for development/test
      key ||= generate_fallback_key(key_id, namespace)

      raise KeyNotFoundError, "Encryption key '#{key_id}' not found" unless key

      validate_key_format(key)
      key
    end

    def validate_key_format(key)
      decoded_key = Base64.decode64(key)
      unless decoded_key.length == 32
        raise InvalidKeyError, "Invalid key length: expected 32 bytes, got #{decoded_key.length}"
      end
    rescue ArgumentError
      raise InvalidKeyError, "Invalid key format: must be base64 encoded"
    end

    def validate_version(version)
      # Support both v1 (legacy Ai::CredentialEncryptionService) and v2
      unless %w[v1 v2].include?(version)
        raise DecryptionError, "Unsupported encryption version: #{version}"
      end
    end

    def generate_fallback_key(key_id, namespace = nil)
      return nil if Rails.env.production?

      # Use environment variable if available
      env_var_name = namespace ? "ENCRYPTION_KEY_#{namespace.upcase}_#{key_id.upcase}" : "ENCRYPTION_KEY_#{key_id.upcase}"
      env_key = ENV[env_var_name]
      return env_key if env_key.present?

      # Also check legacy AI encryption env var
      env_key = ENV["AI_ENCRYPTION_KEY_#{key_id.upcase}"]
      return env_key if env_key.present?

      # Generate deterministic key based on Rails secret for development
      base_secret = Rails.application.secret_key_base || "default_secret_for_development"
      key_material = namespace ? "#{base_secret}_encryption_#{namespace}_#{key_id}" : "#{base_secret}_encryption_#{key_id}"

      digest = Digest::SHA256.digest(key_material)
      Base64.strict_encode64(digest)
    end
  end
end
