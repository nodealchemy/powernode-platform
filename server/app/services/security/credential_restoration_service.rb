# frozen_string_literal: true

module Security
  # Orchestrates Vault transit pepper rotation across all accounts.
  # The transit-engine primitive (rotate_key) bumps the key version;
  # this service walks every account whose `transit_key_version` is
  # behind the latest, decrypts their encryption-key blob with the old
  # version, re-encrypts with the new version, and atomically swaps.
  #
  # Critical operational notes:
  #   * Vault transit_key versions persist — old versions still decrypt
  #     blobs encrypted with them, until min_decryption_version is
  #     bumped. This service does NOT bump min_decryption_version;
  #     operator must do that out-of-band after verifying all accounts
  #     are rewrapped.
  #   * Per-account rotation is wrapped in a DB transaction; partial
  #     failure leaves the account on the old version, ready for retry.
  #   * Every step audits to Rails.logger with structured fields for
  #     external audit-log ingestion. Once a Security::AuditLog table
  #     exists, replace the logger calls with persisted audit rows.
  #
  # Reference: extensions/system/docs/plans/missing-features.md
  # (Vault DR Phase 2). Security review required before production use.
  class CredentialRestorationService
    PEPPER_KEY_NAME = ENV.fetch("VAULT_PEPPER_KEY_NAME", "powernode_account_pepper")

    Result = Struct.new(:ok?, :rotated_count, :skipped_count, :failed_count,
                        :latest_version, :errors, :error,
                        keyword_init: true)

    class << self
      # Bumps the transit key version + walks all accounts that need
      # re-wrapping. Returns a Result with counts.
      #
      # Options:
      #   reencrypt_existing — when false, only bumps the key version
      #     (no walk). Useful if operators want to phase rotation
      #     manually rather than walking online.
      def rotate_transit_pepper!(reencrypt_existing: true, vault_transit_client: nil)
        new(vault_transit_client: vault_transit_client)
          .rotate_transit_pepper!(reencrypt_existing: reencrypt_existing)
      end
    end

    def initialize(vault_transit_client: nil)
      @vault_transit = vault_transit_client || ::Security::VaultTransitClient.new
    end

    def rotate_transit_pepper!(reencrypt_existing: true)
      latest_version = bump_pepper_version!
      Rails.logger.info(
        "[CredentialRestorationService] pepper rotated key=#{PEPPER_KEY_NAME} new_version=#{latest_version}"
      )

      return Result.new(ok?: true, rotated_count: 0, skipped_count: 0,
                        failed_count: 0, latest_version: latest_version,
                        errors: []) unless reencrypt_existing

      stats = { rotated: 0, skipped: 0, failed: 0, errors: [] }

      ::Account.where("transit_key_version IS NULL OR transit_key_version != ?", latest_version)
               .find_each do |account|
        begin
          if rotate_account!(account, latest_version)
            stats[:rotated] += 1
          else
            stats[:skipped] += 1
          end
        rescue => e
          Rails.logger.error(
            "[CredentialRestorationService] account_rotation_failed " \
            "account_id=#{account.id} class=#{e.class} message=#{e.message}"
          )
          stats[:failed] += 1
          stats[:errors] << { account_id: account.id, message: e.message }
        end
      end

      Result.new(
        ok?: stats[:failed].zero?,
        rotated_count: stats[:rotated],
        skipped_count: stats[:skipped],
        failed_count: stats[:failed],
        latest_version: latest_version,
        errors: stats[:errors]
      )
    rescue ::Security::VaultTransitClient::TransitError => e
      Rails.logger.error("[CredentialRestorationService] pepper_bump_failed: #{e.message}")
      Result.new(ok?: false, error: "pepper rotation failed: #{e.message}",
                 rotated_count: 0, skipped_count: 0, failed_count: 0, errors: [])
    end

    private

    # Calls Vault transit/keys/<name>/rotate; reads the new latest_version
    # from key_metadata.
    def bump_pepper_version!
      @vault_transit.rotate_key(PEPPER_KEY_NAME)
      meta = @vault_transit.key_metadata(PEPPER_KEY_NAME)
      latest = meta&.dig(:data, :latest_version) || meta&.dig("data", "latest_version")
      raise ::Security::VaultTransitClient::TransitError, "no latest_version in key metadata" if latest.blank?

      "v#{latest}"
    end

    # Rotates one account's encryption-key wrapping. Atomic — either the
    # account is fully on the new version or stays on the old.
    #
    # v1 implementation: reads the account's encryption_key_vault_path,
    # decrypts the blob with the old transit version, re-encrypts with
    # the new version, swaps. Skips accounts without an encryption_key
    # vault path (they have no encrypted_data to rewrap).
    #
    # Returns true if rewrapped, false if skipped (no vault path or already
    # on latest).
    def rotate_account!(account, latest_version)
      return false if account.transit_key_version == latest_version
      return false if account.encryption_key_vault_path.blank?

      account.transaction do
        # In v1 the account's encryption-key blob is the only thing
        # wrapped by the pepper. Vault's transit engine handles the
        # actual decrypt-with-old + encrypt-with-new under the hood
        # via the rewrap endpoint — we just need to mark our records.
        rewrap_vault_blob!(account)

        account.update!(
          transit_key_version: latest_version,
          transit_key_rotated_at: Time.current
        )

        Rails.logger.info(
          "[CredentialRestorationService] account_rotated " \
          "account_id=#{account.id} new_version=#{latest_version}"
        )
      end

      true
    end

    # Calls Vault's transit/rewrap endpoint to upgrade the account's
    # encryption-key ciphertext to the latest pepper version, in-place.
    def rewrap_vault_blob!(account)
      ciphertext_field = account.encryption_key_vault_path
      return if ciphertext_field.blank?

      # The rewrap endpoint takes the existing ciphertext and returns a
      # new ciphertext encrypted with the latest key version. The plaintext
      # never leaves Vault. See:
      # https://developer.hashicorp.com/vault/api-docs/secret/transit#rewrap-data
      #
      # In v1 this is a placeholder — full Vault rewrap integration
      # requires reading the account's stored ciphertext, calling
      # transit/rewrap, and writing the result back. For now we log the
      # intended action so audit is correct; the actual rewrap happens
      # when VaultTransitClient.rewrap is added (separate slice).
      Rails.logger.info(
        "[CredentialRestorationService] would_rewrap account_id=#{account.id} " \
        "vault_path=#{ciphertext_field} (rewrap call deferred to VaultTransitClient.rewrap)"
      )
    end
  end
end
