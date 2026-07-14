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
  # Signing-key management (generic — no caller-specific coupling):
  #   - `create_signing_key(name, type:, exportable:)` — POST
  #     transit/keys/<name> with an asymmetric key type (ecdsa-p256 by
  #     default). Idempotent: a pre-flight read no-ops if the key already
  #     exists rather than re-issuing the write (avoids silently mutating
  #     an existing production key's config on a repeated call). Always
  #     rejects `exportable: true` — a transit SIGNING key's whole purpose
  #     is that the private key material never leaves Vault; callers that
  #     need exportable material want a different primitive entirely.
  #   - `signing_public_key(name)` — GET transit/keys/<name>, returns the
  #     PEM public key for the latest version. Public keys are not secret
  #     (safe to log/store/distribute) — this method never touches private
  #     key material, which Vault's transit API does not expose for
  #     non-exportable keys in the first place.
  #
  # Defends against an unmounted transit engine via VaultUnavailableError so
  # callers can degrade gracefully (un-peppered rows continue to work).
  #
  # Reference: comprehensive stabilization sweep P3; signing-key management
  # added for campaign 019f5885 inc8 (platform-side module signing).
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

    # Idempotent creation of an asymmetric transit key intended for
    # SIGNING (not encrypt/decrypt). `exportable` must stay false — this
    # is a hard invariant, not a caller preference: the entire point of a
    # Vault-transit signing key is that the private half never leaves
    # Vault, so cosign (or any other caller) only ever gets to ask Vault
    # to sign, never to hand over key material.
    #
    # Idempotency is implemented via a pre-flight `key_metadata` read
    # rather than relying on Vault's own create-endpoint semantics — this
    # guarantees a second call never re-issues the write (and so never
    # risks silently changing an existing key's type/config), regardless
    # of what a given Vault version does with a duplicate create.
    #
    # @return [Boolean] true if this call created the key, false if it
    #   already existed (no-op).
    def create_signing_key(name, type: "ecdsa-p256", exportable: false)
      raise ArgumentError, "name required" if name.blank?
      if exportable
        raise ArgumentError,
              "signing keys must not be exportable — the private key must never leave Vault"
      end

      return false if key_metadata(name).present?

      with_circuit do
        @vault_client.client.logical.write(
          "#{@mount}/keys/#{name}",
          exportable: false,
          type: type
        )
        true
      end
    end

    # Returns the PEM-encoded public key for the latest version of a
    # transit key. Public keys are NOT secret — safe to log, cache, or
    # hand to a verifier. Raises KeyNotFoundError if the key doesn't
    # exist, TransitError if the key exists but has no public key for its
    # latest version (e.g. it's a symmetric key, not asymmetric).
    def signing_public_key(name, version: nil)
      raise ArgumentError, "name required" if name.blank?

      meta = key_metadata(name)
      raise KeyNotFoundError, "Vault transit key not found: #{name}" if meta.blank?

      keys = meta[:keys] || meta["keys"] || {}
      target_version = (version || meta[:latest_version] || meta["latest_version"]).to_s
      entry = keys[target_version] || keys[target_version.to_sym]
      pubkey = entry.is_a?(Hash) ? (entry[:public_key] || entry["public_key"]) : nil
      raise TransitError, "Vault transit key #{name} has no public_key for version #{target_version}" if pubkey.blank?

      pubkey
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
