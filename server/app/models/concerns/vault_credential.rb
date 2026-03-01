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
end
