# frozen_string_literal: true

class AiCredentialEncryptionService
  ENCRYPTION_VERSION = "v1"
  KEY_ROTATION_INTERVAL = 90.days
  MIN_KEY_LENGTH = 16  # Minimum 128-bit key
  DEFAULT_ALGORITHM = "aes-256-gcm"

  class EncryptionError < StandardError; end
  class DecryptionError < StandardError; end
  class InvalidKeyError < StandardError; end
  class WeakEncryptionKeyError < StandardError; end

  attr_reader :cipher_algorithm

  # Instance methods for encryption/decryption
  # When no key provided, uses the application's key management system
  def initialize(encryption_key: nil)
    @cipher_algorithm = DEFAULT_ALGORITHM

    if encryption_key
      validate_key_strength(encryption_key)
      @salt = SecureRandom.random_bytes(16)
      @encryption_key = derive_key_from_password(encryption_key, Base64.strict_encode64(@salt))
      @key_id = nil
    else
      # Use the application's key management - same as class methods
      @key_id = self.class.current_key_id
      key_b64 = self.class.get_encryption_key(@key_id)
      @encryption_key = Base64.decode64(key_b64)
    end
  end

  # Instance method for encrypting credentials
  def encrypt_credentials(credentials_hash)
    raise ArgumentError, "Credentials must be a Hash" unless credentials_hash.is_a?(Hash)
    raise ArgumentError, "Credentials cannot be empty" if credentials_hash.empty?

    # Sanitize credentials
    sanitized = self.class.send(:sanitize_credentials, credentials_hash)
    json_data = sanitized.to_json

    # Encrypt with instance key
    cipher = OpenSSL::Cipher.new(@cipher_algorithm)
    cipher.encrypt
    cipher.key = @encryption_key

    iv = cipher.random_iv
    encrypted_data = cipher.update(json_data) + cipher.final
    auth_tag = cipher.auth_tag

    # Return base64 encoded result with metadata
    Base64.strict_encode64({
      "encrypted_data" => Base64.strict_encode64(encrypted_data),
      "iv" => Base64.strict_encode64(iv),
      "auth_tag" => Base64.strict_encode64(auth_tag),
      "algorithm" => @cipher_algorithm,
      "timestamp" => Time.current.to_i
    }.to_json)
  rescue OpenSSL::Cipher::CipherError => e
    raise EncryptionError, "Encryption failed: #{e.message}"
  rescue StandardError => e
    raise EncryptionError, "Failed to encrypt credentials: #{e.message}"
  end

  # Instance method for decrypting credentials
  def decrypt_credentials(encrypted_string)
    raise ArgumentError, "Encrypted credentials cannot be blank" if encrypted_string.blank?

    # Decode base64 wrapper
    wrapper = JSON.parse(Base64.strict_decode64(encrypted_string))

    # Extract components
    encrypted_data = Base64.strict_decode64(wrapper["encrypted_data"])
    iv = Base64.strict_decode64(wrapper["iv"])
    auth_tag = Base64.strict_decode64(wrapper["auth_tag"])
    algorithm = wrapper["algorithm"] || DEFAULT_ALGORITHM

    # Decrypt
    cipher = OpenSSL::Cipher.new(algorithm)
    cipher.decrypt
    cipher.key = @encryption_key
    cipher.iv = iv
    cipher.auth_tag = auth_tag

    decrypted_json = cipher.update(encrypted_data) + cipher.final
    JSON.parse(decrypted_json)
  rescue JSON::ParserError => e
    raise DecryptionError, "Invalid encrypted credentials format: #{e.message}"
  rescue OpenSSL::Cipher::CipherError => e
    raise DecryptionError, "Decryption failed: #{e.message}"
  rescue StandardError => e
    raise DecryptionError, "Failed to decrypt credentials: #{e.message}"
  end

  # Instance method for key derivation
  def derive_key_for_password(password, salt)
    derive_key_from_password(password, salt)
  end

  # Simple encrypt method for single values (compatibility wrapper)
  def encrypt(value)
    return nil if value.blank?

    cipher = OpenSSL::Cipher.new(@cipher_algorithm)
    cipher.encrypt
    cipher.key = @encryption_key

    iv = cipher.random_iv
    encrypted_data = cipher.update(value.to_s) + cipher.final
    auth_tag = cipher.auth_tag

    # Return base64 encoded result with key_id for proper decryption
    Base64.strict_encode64({
      "data" => Base64.strict_encode64(encrypted_data),
      "iv" => Base64.strict_encode64(iv),
      "tag" => Base64.strict_encode64(auth_tag),
      "key_id" => @key_id || self.class.current_key_id
    }.to_json)
  rescue StandardError => e
    raise EncryptionError, "Failed to encrypt value: #{e.message}"
  end

  # Simple decrypt method for single values (compatibility wrapper)
  def decrypt(encrypted_value)
    return nil if encrypted_value.blank?

    wrapper = JSON.parse(Base64.strict_decode64(encrypted_value))

    encrypted_data = Base64.strict_decode64(wrapper["data"])
    iv = Base64.strict_decode64(wrapper["iv"])
    auth_tag = Base64.strict_decode64(wrapper["tag"])
    stored_key_id = wrapper["key_id"]

    # Use stored key_id to get the correct decryption key
    decryption_key = if stored_key_id
                       key_b64 = self.class.get_encryption_key(stored_key_id)
                       Base64.decode64(key_b64)
    else
                       @encryption_key
    end

    cipher = OpenSSL::Cipher.new(@cipher_algorithm)
    cipher.decrypt
    cipher.key = decryption_key
    cipher.iv = iv
    cipher.auth_tag = auth_tag

    cipher.update(encrypted_data) + cipher.final
  rescue StandardError => e
    raise DecryptionError, "Failed to decrypt value: #{e.message}"
  end

  private

  def generate_encryption_key
    SecureRandom.random_bytes(32) # 256 bits for AES-256
  end

  def derive_key_from_password(password, salt)
    OpenSSL::KDF.pbkdf2_hmac(
      password,
      salt: salt,
      iterations: 100_000,
      length: 32,
      hash: "SHA256"
    )
  end

  def validate_key_strength(key)
    if key.length < MIN_KEY_LENGTH
      raise WeakEncryptionKeyError, "Encryption key must be at least #{MIN_KEY_LENGTH} characters"
    end
  end

  # Class methods for production use
  class << self
    # Encrypt credentials hash and return encrypted string
    def encrypt(credentials_hash)
      raise ArgumentError, "Credentials must be a Hash" unless credentials_hash.is_a?(Hash)
      raise ArgumentError, "Credentials cannot be empty" if credentials_hash.empty?

      # Sanitize and validate credentials
      sanitized_credentials = sanitize_credentials(credentials_hash)

      # Convert to JSON
      json_data = sanitized_credentials.to_json

      # Encrypt with current key
      encrypted_data = encrypt_data(json_data)

      # Return base64 encoded result with version info
      Base64.strict_encode64({
        version: ENCRYPTION_VERSION,
        key_id: current_key_id,
        encrypted_data: encrypted_data,
        created_at: Time.current.to_i
      }.to_json)
    rescue StandardError => e
      Rails.logger.error "AI credential encryption failed: #{e.message}"
      raise EncryptionError, "Failed to encrypt credentials: #{e.message}"
    end

    # Decrypt credentials and return hash
    def decrypt(encrypted_credentials, key_id = nil)
      raise ArgumentError, "Encrypted credentials cannot be blank" if encrypted_credentials.blank?

      begin
        # Decode base64 wrapper
        wrapper_data = JSON.parse(Base64.strict_decode64(encrypted_credentials))

        # Extract components
        version = wrapper_data["version"]
        stored_key_id = wrapper_data["key_id"]
        encrypted_data = wrapper_data["encrypted_data"]

        # Use provided key_id or fallback to stored key_id
        effective_key_id = key_id || stored_key_id

        # Validate version compatibility
        validate_version(version)

        # Decrypt data
        decrypted_json = decrypt_data(encrypted_data, effective_key_id)

        # Parse and return credentials
        JSON.parse(decrypted_json)
      rescue JSON::ParserError => e
        raise DecryptionError, "Invalid encrypted credentials format: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "AI credential decryption failed: #{e.message}"
        raise DecryptionError, "Failed to decrypt credentials: #{e.message}"
      end
    end

    # Test if credentials can be decrypted
    def valid_encrypted_credentials?(encrypted_credentials, key_id = nil)
      decrypt(encrypted_credentials, key_id)
      true
    rescue StandardError
      false
    end

    # Get current encryption key ID
    def current_key_id
      Rails.application.credentials.dig(:ai_encryption, :current_key_id) || "default"
    end

    # Get encryption key for given ID
    def get_encryption_key(key_id)
      # Try to get key from credentials first
      key = Rails.application.credentials.dig(:ai_encryption, :keys, key_id.to_sym)

      # Fall back to environment-based key generation for development/test
      if key.nil?
        key = generate_fallback_key(key_id)
      end

      raise InvalidKeyError, "Encryption key '#{key_id}' not found" unless key

      # Ensure key is proper length for AES-256
      validate_key_format(key)
      key
    end

    # Rotate credentials to new encryption key
    def rotate_credentials(ai_provider_credential, new_key_id = nil)
      target_key_id = new_key_id || current_key_id
      return if ai_provider_credential.encryption_key_id == target_key_id

      # Decrypt with old key
      old_credentials = ai_provider_credential.credentials

      # Re-encrypt with new key
      ai_provider_credential.update!(
        credentials: old_credentials,  # This will trigger re-encryption
        encryption_key_id: target_key_id
      )

      Rails.logger.info "Rotated AI credentials for #{ai_provider_credential.id} to key #{target_key_id}"
    rescue StandardError => e
      Rails.logger.error "Failed to rotate AI credentials: #{e.message}"
      raise EncryptionError, "Credential rotation failed: #{e.message}"
    end

    # Bulk rotate all credentials for a key
    def rotate_all_credentials_for_key(old_key_id, new_key_id = nil)
      target_key_id = new_key_id || current_key_id
      rotated_count = 0
      failed_count = 0

      Ai::ProviderCredential.where(encryption_key_id: old_key_id).find_each do |credential|
        begin
          rotate_credentials(credential, target_key_id)
          rotated_count += 1
        rescue StandardError => e
          Rails.logger.error "Failed to rotate credential #{credential.id}: #{e.message}"
          failed_count += 1
        end
      end

      {
        rotated: rotated_count,
        failed: failed_count,
        total: rotated_count + failed_count
      }
    end

    # Get list of available encryption keys
    def available_keys
      Rails.application.credentials.dig(:ai_encryption, :keys)&.keys&.map(&:to_s) || [ "default" ]
    end

    # Check if key rotation is needed
    def key_rotation_needed?(credential)
      return false unless credential.created_at
      return true if credential.encryption_key_id != current_key_id

      credential.created_at < KEY_ROTATION_INTERVAL.ago
    end

    # Generate new encryption key (for setup/maintenance)
    def generate_new_key
      SecureRandom.base64(32)  # 32 bytes = 256 bits for AES-256
    end

    # Alias for backwards compatibility with tests
    def encrypt_credentials(credentials_hash)
      encrypt(credentials_hash)
    end

    # Validate credential format before encryption
    def validate_credentials_format(credentials_hash, provider_type)
      case provider_type
      when "text_generation"
        validate_text_generation_format(credentials_hash)
      when "image_generation"
        validate_image_generation_format(credentials_hash)
      when "code_execution"
        validate_code_execution_format(credentials_hash)
      else
        validate_generic_format(credentials_hash)
      end
    end

    private

    def sanitize_credentials(credentials_hash)
      sanitized = {}

      credentials_hash.each do |key, value|
        # Convert keys to strings and sanitize
        clean_key = key.to_s.strip.downcase

        # Skip empty keys or values
        next if clean_key.blank? || value.blank?

        # Sanitize value based on key type
        sanitized[clean_key] = sanitize_credential_value(clean_key, value)
      end

      sanitized
    end

    def sanitize_credential_value(key, value)
      case key
      when /api[_\-]?key|token|secret/
        # API keys and tokens - remove whitespace but preserve case
        value.to_s.strip
      when /url|endpoint/
        # URLs - ensure proper format
        url = value.to_s.strip
        url = "https://#{url}" if url.present? && !url.start_with?("http")
        url
      when /organization|org[_\-]?id/
        # Organization IDs - remove whitespace
        value.to_s.strip
      else
        # Generic string cleanup
        value.to_s.strip
      end
    end

    def encrypt_data(data)
      key = get_encryption_key(current_key_id)
      cipher = OpenSSL::Cipher.new("AES-256-GCM")
      cipher.encrypt
      cipher.key = Base64.decode64(key)

      iv = cipher.random_iv
      encrypted_data = cipher.update(data) + cipher.final
      auth_tag = cipher.auth_tag

      # Combine IV, auth tag, and encrypted data
      Base64.strict_encode64(iv + auth_tag + encrypted_data)
    end

    def decrypt_data(encrypted_data_b64, key_id)
      key = get_encryption_key(key_id)
      cipher = OpenSSL::Cipher.new("AES-256-GCM")
      cipher.decrypt
      cipher.key = Base64.decode64(key)

      # Decode and extract components
      combined_data = Base64.strict_decode64(encrypted_data_b64)
      iv = combined_data[0..11]  # 12 bytes IV
      auth_tag = combined_data[12..27]  # 16 bytes auth tag
      encrypted_data = combined_data[28..-1]  # Rest is encrypted data

      cipher.iv = iv
      cipher.auth_tag = auth_tag

      cipher.update(encrypted_data) + cipher.final
    end

    def validate_version(version)
      unless version == ENCRYPTION_VERSION
        raise DecryptionError, "Unsupported encryption version: #{version}"
      end
    end

    def validate_key_format(key)
      decoded_key = Base64.decode64(key)
      unless decoded_key.length == 32  # 256 bits
        raise InvalidKeyError, "Invalid key length: expected 32 bytes, got #{decoded_key.length}"
      end
    rescue ArgumentError
      raise InvalidKeyError, "Invalid key format: must be base64 encoded"
    end

    def validate_text_generation_format(credentials)
      required_fields = %w[api_key]
      optional_fields = %w[organization base_url model]
      validate_credential_fields(credentials, required_fields, optional_fields)
    end

    def validate_image_generation_format(credentials)
      required_fields = %w[api_key]
      optional_fields = %w[organization base_url]
      validate_credential_fields(credentials, required_fields, optional_fields)
    end

    def validate_code_execution_format(credentials)
      required_fields = %w[api_key]
      optional_fields = %w[base_url workspace_id]
      validate_credential_fields(credentials, required_fields, optional_fields)
    end

    def validate_generic_format(credentials)
      # Generic validation - at least one credential field required
      valid_fields = %w[api_key token secret base_url organization]
      has_valid_field = credentials.keys.any? { |key| valid_fields.include?(key.to_s) }

      unless has_valid_field
        raise ArgumentError, "Credentials must include at least one of: #{valid_fields.join(', ')}"
      end
    end

    def validate_credential_fields(credentials, required_fields, optional_fields)
      missing_required = required_fields - credentials.keys
      unless missing_required.empty?
        raise ArgumentError, "Missing required fields: #{missing_required.join(', ')}"
      end

      invalid_fields = credentials.keys - (required_fields + optional_fields)
      unless invalid_fields.empty?
        Rails.logger.warn "Unknown credential fields: #{invalid_fields.join(', ')}"
      end
    end

    # Generate fallback encryption key for development/test environments
    def generate_fallback_key(key_id)
      return nil if Rails.env.production?

      # Use environment variable if available
      env_key = ENV["AI_ENCRYPTION_KEY_#{key_id.upcase}"]
      return env_key if env_key.present?

      # Generate deterministic key based on Rails secret and key_id for development
      base_secret = Rails.application.secret_key_base || "default_secret_for_development"
      key_material = "#{base_secret}_ai_encryption_#{key_id}"

      # Generate 32-byte key and base64 encode it
      digest = Digest::SHA256.digest(key_material)
      Base64.strict_encode64(digest)
    end
  end
end
