# frozen_string_literal: true

# Plugin Installation Model
# Tracks installed plugins and their configuration per account
class PluginInstallation < ApplicationRecord
  include Auditable

  belongs_to :account
  belongs_to :plugin
  belongs_to :installed_by, class_name: "User"

  # Validations
  validates :status, inclusion: { in: %w[active inactive error updating] }
  validates :plugin_id, uniqueness: { scope: :account_id }

  # JSON attributes
  attribute :configuration, :json, default: -> { {} }
  attribute :credentials, :json, default: -> { {} }
  attribute :installation_metadata, :json, default: -> { {} }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :with_errors, -> { where(status: "error") }
  scope :recently_used, -> { where("last_used_at >= ?", 7.days.ago) }

  # Callbacks
  before_create :set_installed_at
  after_create :register_plugin_resources
  after_destroy :unregister_plugin_resources

  # Status management
  def activate!
    update!(status: "active", last_activated_at: Time.current)
    register_plugin_resources
  end

  def deactivate!
    update!(status: "inactive")
    unregister_plugin_resources
  end

  def mark_used!
    update!(last_used_at: Time.current)
    increment!(:execution_count)
  end

  def add_cost(cost_amount)
    increment!(:total_cost, cost_amount)
  end

  # Configuration management
  def merged_configuration
    plugin.configuration.deep_merge(configuration)
  end

  def update_configuration(new_config)
    update!(configuration: configuration.deep_merge(new_config))
  end

  # Credentials management (encrypted)
  def set_credential(key, value)
    self.credentials = credentials.merge(key => encrypt_credential(value))
    save!
  end

  def get_credential(key)
    encrypted_value = credentials[key]
    return nil if encrypted_value.blank?

    decrypt_credential(encrypted_value)
  end

  private

  def set_installed_at
    self.installed_at = Time.current
  end

  def register_plugin_resources
    # Register plugin with appropriate registries based on type
    if plugin.provider?
      PluginProviderRegistryService.new(account: account).register_provider_plugin(self)
    end

    if plugin.workflow_node?
      PluginNodeRegistryService.new(account: account).register_node_plugin(self)
    end
  rescue StandardError => e
    Rails.logger.error "[PLUGIN_INSTALLATION] Failed to register resources: #{e.message}"
  end

  def unregister_plugin_resources
    if plugin.provider?
      PluginProviderRegistryService.new(account: account).unregister_provider_plugin(self)
    end

    if plugin.workflow_node?
      PluginNodeRegistryService.new(account: account).unregister_node_plugin(self)
    end
  rescue StandardError => e
    Rails.logger.error "[PLUGIN_INSTALLATION] Failed to unregister resources: #{e.message}"
  end

  def encrypt_credential(value)
    # Use Rails encrypted attributes
    Rails.application.message_encryptor(:plugins).encrypt_and_sign(value)
  end

  def decrypt_credential(encrypted_value)
    Rails.application.message_encryptor(:plugins).decrypt_and_verify(encrypted_value)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
