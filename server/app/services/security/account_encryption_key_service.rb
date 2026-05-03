# frozen_string_literal: true

module Security
  # Per-account encryption pepper backed by Vault transit. Each account gets
  # its own transit key (`account-#{account.id}`); peppered values can only
  # be decrypted by a process holding both the platform DB and a valid Vault
  # token. See `docs/system/credential-restoration.md`.
  #
  # Public API:
  #   generate_for(account)        # idempotent; ensures the account has a key
  #   peppered(account, plaintext) # returns Vault-transit ciphertext (`vault:v1:...`)
  #   decrypt(account, blob)       # returns plaintext from a peppered blob
  #   rotate_for(account)          # bumps key version; prior versions still decrypt
  #   peppered_blob?(value)        # true iff `value` looks like a Vault transit blob
  #
  # Errors:
  #   VaultUnavailableError — Vault transit engine unmounted or unreachable.
  #     Callers should degrade gracefully (e.g., AccountPepperedEncryption
  #     concern stores plaintext when this is raised; subsequent reads
  #     continue to work).
  #
  # Reference: comprehensive stabilization sweep P3.
  class AccountEncryptionKeyService
    KEY_PREFIX = "account-"

    class << self
      # Idempotent: returns the account's vault key path, creating the key
      # in Vault and persisting the path on the account if not already.
      def generate_for(account)
        return account.encryption_key_vault_path if account.encryption_key_vault_path.present?

        with_vault_translation do
          key_name = key_name_for(account)
          transit_client.create_key(key_name)
          path = "transit/keys/#{key_name}"
          account.update_columns(encryption_key_vault_path: path)
          path
        end
      end

      # Encrypts plaintext with the account's pepper. Generates the account's
      # key on first call. Raises VaultUnavailableError if Vault transit is
      # unreachable — callers should rescue and store plaintext as a fallback.
      def peppered(account, plaintext)
        return plaintext if plaintext.blank?

        with_vault_translation do
          generate_for(account) if account.encryption_key_vault_path.blank?
          transit_client.encrypt(key_name_for(account), plaintext)
        end
      end

      # Decrypts a peppered blob. Returns nil if blob is blank. Returns the
      # input unchanged if it doesn't look like a Vault transit blob (legacy
      # un-peppered value).
      def decrypt(account, blob)
        return nil if blob.blank?
        return blob unless peppered_blob?(blob)

        with_vault_translation do
          transit_client.decrypt(key_name_for(account), blob)
        end
      end

      # Rotates the key version. Returns the new metadata. Existing blobs
      # encrypted with prior versions still decrypt; re-encryption via
      # rewrap is a separate operator step.
      def rotate_for(account)
        raise ArgumentError, "account has no key to rotate" if account.encryption_key_vault_path.blank?

        transit_client.rotate_key(key_name_for(account))
      end

      def peppered_blob?(value)
        value.is_a?(String) && value.start_with?(::Security::VaultTransitClient::PEPPER_PREFIX)
      end

      def transit_client
        @transit_client ||= ::Security::VaultTransitClient.new
      rescue ::Security::VaultClient::AuthenticationError,
             ::Security::VaultClient::ConnectionError,
             Vault::HTTPConnectionError => e
        raise ::Security::VaultTransitClient::VaultUnavailableError, e.message
      end

      # Test seam — allows specs to inject a stub.
      attr_writer :transit_client

      def reset_transit_client!
        @transit_client = nil
      end

      private

      # Translates any Vault-related error class into our domain-level
      # VaultUnavailableError so a single rescue covers them all.
      def with_vault_translation
        yield
      rescue ::Security::VaultTransitClient::VaultUnavailableError
        raise
      rescue ::Security::VaultClient::AuthenticationError,
             ::Security::VaultClient::ConnectionError,
             Vault::HTTPConnectionError => e
        raise ::Security::VaultTransitClient::VaultUnavailableError, e.message
      end

      def key_name_for(account)
        "#{KEY_PREFIX}#{account.id}"
      end
    end
  end
end
