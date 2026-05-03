# frozen_string_literal: true

module Security
  # Wraps Vault transit-engine operations: encrypt/decrypt with named keys,
  # rotate, key versioning. Transit is fundamentally different from KV — Vault
  # holds the key and never exposes plaintext key material. Operations are
  # round-trips: client sends plaintext (base64), gets ciphertext blob like
  # `vault:v1:abc...` where v1 is the key version.
  #
  # Key lifecycle:
  #   - `create_key(name)` — POST transit/keys/<name>; idempotent.
  #   - `encrypt(name, plaintext)` — returns Vault-prefixed ciphertext blob.
  #   - `decrypt(name, ciphertext)` — returns plaintext.
  #   - `rotate_key(name)` — bumps key version; old versions still decrypt
  #     until explicit retire.
  #
  # Defends against an unmounted transit engine via VaultUnavailableError so
  # callers can degrade gracefully (un-peppered rows continue to work).
  #
  # Reference: comprehensive stabilization sweep P3.
  class VaultTransitClient
    class VaultUnavailableError < StandardError; end
    class TransitError < StandardError; end
    class KeyNotFoundError < TransitError; end
    class CiphertextMismatchError < TransitError; end

    DEFAULT_MOUNT = "transit"
    PEPPER_PREFIX = "vault:v"

    def initialize(mount: DEFAULT_MOUNT, vault_client: nil)
      @mount = mount
      @vault_client = vault_client || ::Security::VaultClient.instance
    end

    # Idempotent — creating an existing key is a no-op success.
    def create_key(name, exportable: false, derived: false, type: "aes256-gcm96")
      with_circuit do
        @vault_client.client.logical.write(
          "#{@mount}/keys/#{name}",
          exportable: exportable,
          derived: derived,
          type: type
        )
        true
      end
    end

    def encrypt(name, plaintext)
      raise ArgumentError, "name required" if name.blank?
      raise ArgumentError, "plaintext required" if plaintext.nil?

      with_circuit do
        b64 = Base64.strict_encode64(plaintext.to_s)
        result = @vault_client.client.logical.write(
          "#{@mount}/encrypt/#{name}",
          plaintext: b64
        )
        ciphertext = result&.data&.dig(:ciphertext)
        raise TransitError, "Vault transit encrypt returned no ciphertext" if ciphertext.blank?

        ciphertext # e.g., "vault:v1:abc123..."
      end
    end

    def decrypt(name, ciphertext)
      raise ArgumentError, "name required" if name.blank?
      raise ArgumentError, "ciphertext required" if ciphertext.blank?
      raise CiphertextMismatchError, "not a Vault transit blob" unless peppered_blob?(ciphertext)

      with_circuit do
        result = @vault_client.client.logical.write(
          "#{@mount}/decrypt/#{name}",
          ciphertext: ciphertext
        )
        b64 = result&.data&.dig(:plaintext)
        raise TransitError, "Vault transit decrypt returned no plaintext" if b64.blank?

        Base64.strict_decode64(b64)
      end
    end

    # Rotate creates a new key version; previously-encrypted blobs still
    # decrypt with their original version until explicit migration.
    def rotate_key(name)
      with_circuit do
        @vault_client.client.logical.write("#{@mount}/keys/#{name}/rotate")
        key_metadata(name)
      end
    end

    def key_metadata(name)
      with_circuit do
        result = @vault_client.client.logical.read("#{@mount}/keys/#{name}")
        result&.data || {}
      end
    end

    def peppered_blob?(value)
      value.is_a?(String) && value.start_with?(PEPPER_PREFIX)
    end

    private

    # Translate Vault errors into our domain errors so callers can pattern-match
    # on VaultUnavailableError vs. TransitError.
    def with_circuit
      yield
    rescue Vault::HTTPError => e
      if e.respond_to?(:code) && e.code.to_i == 404
        raise KeyNotFoundError, "Vault transit key not found: #{e.message}"
      elsif e.message.to_s.include?("transit") && e.message.to_s.include?("disabled")
        raise VaultUnavailableError, "Vault transit engine not mounted"
      else
        raise TransitError, "Vault transit error: #{e.message}"
      end
    rescue Vault::HTTPConnectionError => e
      raise VaultUnavailableError, "Vault unreachable: #{e.message}"
    rescue ::Security::VaultClient::ConnectionError => e
      raise VaultUnavailableError, e.message
    rescue ::Security::VaultClient::AuthenticationError => e
      raise VaultUnavailableError, "Vault auth failed: #{e.message}"
    end
  end
end
