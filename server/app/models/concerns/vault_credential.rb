# frozen_string_literal: true

module VaultCredential
  extend ActiveSupport::Concern

  included do
    # Define the credential type for Vault path construction
    class_attribute :vault_credential_type, default: "custom"

    # Scopes for Vault migration status
    scope :migrated_to_vault, -> { where.not(vault_path: nil) }
    scope :pending_vault_migration, -> { where(vault_path: nil).where.not(encrypted_credentials: nil) }

    # Callbacks
    after_destroy :cleanup_vault_secret, if: :vault_path?
  end

  # Get credentials - prefer Vault, fallback to database
  def vault_credentials
    return @vault_credentials if defined?(@vault_credentials)

    @vault_credentials = fetch_vault_credentials
  end

  # Store credentials in Vault
  def store_in_vault(data)
    raise ArgumentError, "Credentials must be a Hash" unless data.is_a?(Hash)

    provider = Security::VaultCredentialProvider.new(account_id: account_id)
    result = provider.store_credential(
      credential_type: self.class.vault_credential_type,
      credential_id: id,
      data: data,
      record: self
    )

    # Clear memoized credentials
    @vault_credentials = nil

    result
  end

  # Check if stored in Vault
  def stored_in_vault?
    vault_path.present? && migrated_to_vault_at.present?
  end

  # Check if pending Vault migration
  def pending_vault_migration?
    vault_path.blank? && respond_to?(:encrypted_credentials) && encrypted_credentials.present?
  end

  # Get credential storage location
  def credential_storage_location
    if stored_in_vault?
      :vault
    elsif respond_to?(:encrypted_credentials) && encrypted_credentials.present?
      :database
    else
      :none
    end
  end

  # Migrate to Vault if not already
  def migrate_to_vault!
    return { status: :already_migrated } if stored_in_vault?

    return { status: :no_credentials } unless respond_to?(:credentials) && credentials.present?

    store_in_vault(credentials)
  end

  # Default credentials accessor pair for the database-fallback path used
  # by Security::VaultCredentialProvider when Vault is unavailable. Models
  # with the `encrypted_credentials` column get DB fallback for free.
  # Models that need custom encryption logic (e.g. Ai::ProviderCredential)
  # override this in their own class — Ruby method lookup gives the class
  # precedence over the included module.
  #
  # Caught in Phase 10.7 — Sdwan::PeerKey/UserDevice/FederationPeer all
  # included VaultCredential but lacked a `credentials=` accessor, which
  # made the provider's DB-fallback path raise CredentialError when Vault
  # was unavailable (every test run + any production Vault outage).
  def credentials
    return @credentials if defined?(@credentials)
    @credentials = decrypt_credentials_for_db
  end

  def credentials=(new_credentials)
    raise ArgumentError, "Credentials must be a Hash" unless new_credentials.is_a?(Hash)
    return unless respond_to?(:encrypted_credentials=)

    @credentials = new_credentials
    self.encrypted_credentials = encrypt_credentials_for_db(new_credentials)
    return unless respond_to?(:encryption_key_id=)

    self.encryption_key_id = current_encryption_key_id
  end

  # Rotate credentials
  def rotate_vault_credentials!(new_data)
    provider = Security::VaultCredentialProvider.new(account_id: account_id)
    result = provider.rotate_credential(
      credential_type: self.class.vault_credential_type,
      credential_id: id,
      new_data: new_data,
      record: self
    )

    @vault_credentials = nil
    result
  end

  # Get credential status
  def vault_credential_status
    provider = Security::VaultCredentialProvider.new(account_id: account_id)
    provider.credential_status(self)
  end

  private

  def fetch_vault_credentials
    provider = Security::VaultCredentialProvider.new(account_id: account_id)
    provider.get_credential(
      credential_type: self.class.vault_credential_type,
      credential_id: id,
      record: self
    )
  end

  def cleanup_vault_secret
    return unless vault_path.present?

    begin
      Security::VaultClient.delete_secret(vault_path)
      Rails.logger.info "Cleaned up Vault secret at #{vault_path}"
    rescue Security::VaultClient::VaultError => e
      Rails.logger.warn "Failed to cleanup Vault secret: #{e.message}"
    end
  end

  # Default DB-fallback encryption helpers. Test env uses base64 round-trip
  # for fast deterministic specs; production uses CredentialEncryptionService
  # under the credential type's namespace. Mirrors the pattern already used
  # by Ai::ProviderCredential.
  def decrypt_credentials_for_db
    return {} unless respond_to?(:encrypted_credentials) && encrypted_credentials.present?

    if Rails.env.test?
      JSON.parse(Base64.strict_decode64(encrypted_credentials))
    else
      ::Security::CredentialEncryptionService.decrypt(
        encrypted_credentials, namespace: vault_credential_namespace
      )
    end
  rescue StandardError => e
    Rails.logger.error "Failed to decrypt credentials: #{e.class}: #{e.message}"
    {}
  end

  def encrypt_credentials_for_db(data)
    return nil if data.blank?

    if Rails.env.test?
      Base64.strict_encode64(data.to_json)
    else
      ::Security::CredentialEncryptionService.encrypt(data, namespace: vault_credential_namespace)
    end
  end

  def current_encryption_key_id
    return "test_key" if Rails.env.test?

    ::Security::CredentialEncryptionService.current_key_id(vault_credential_namespace)
  end

  # Namespace used by CredentialEncryptionService — derives from the
  # credential type prefix (e.g. "wireguard_node_key" → "wireguard").
  def vault_credential_namespace
    type = self.class.vault_credential_type.to_s
    type.split("_").first.presence || "default"
  end
end
