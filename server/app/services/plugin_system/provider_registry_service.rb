# frozen_string_literal: true

module PluginSystem
  # Plugin Provider Registry Service
  # Manages AI provider plugins and registers them as available AI providers
  class ProviderRegistryService
    include ActiveModel::Model

    attr_accessor :account

    def initialize(account:)
      @account = account
      @logger = Rails.logger
      @providers = {}

      load_installed_providers
    end

    # Register an AI provider plugin as an available provider
    def register_provider_plugin(installation)
      plugin = installation.plugin
      provider_plugin = plugin.ai_provider_plugin

      return unless provider_plugin

      @logger.info "[PLUGIN_PROVIDER] Registering provider plugin: #{plugin.name}"

      # Create or update Ai::Provider record
      provider = Ai::Provider.find_or_initialize_by(
        account: account,
        provider_identifier: plugin.plugin_id
      )

      provider.assign_attributes(
        name: plugin.name,
        provider_type: provider_plugin.provider_type,
        status: "active",
        is_active: true,
        configuration: {
          "plugin_id" => plugin.id,
          "plugin_installation_id" => installation.id,
          "is_plugin" => true,
          "models" => provider_plugin.models,
          "capabilities" => provider_plugin.supported_capabilities
        }.merge(installation.merged_configuration)
      )

      provider.save!

      # Store provider credentials from installation
      sync_provider_credentials(provider, installation)

      @providers[plugin.plugin_id] = provider

      @logger.info "[PLUGIN_PROVIDER] Provider plugin registered: #{provider.id}"
      provider
    end

    # Unregister a provider plugin
    def unregister_provider_plugin(installation)
      plugin = installation.plugin

      @logger.info "[PLUGIN_PROVIDER] Unregistering provider plugin: #{plugin.name}"

      provider = Ai::Provider.find_by(
        account: account,
        provider_identifier: plugin.plugin_id
      )

      if provider
        provider.update!(status: "inactive", is_active: false)
        @providers.delete(plugin.plugin_id)
      end

      @logger.info "[PLUGIN_PROVIDER] Provider plugin unregistered: #{plugin.plugin_id}"
    end

    # Get all registered provider plugins
    def list_provider_plugins
      installations = PluginSystem::Installation
        .joins(:plugin)
        .where(account: account, status: "active")
        .where("'ai_provider' = ANY(plugins.plugin_types)")
        .includes(:plugin)

      installations.map { |inst| provider_info(inst) }
    end

    # Get provider by plugin ID
    def get_provider_by_plugin_id(plugin_id)
      Ai::Provider.find_by(account: account, provider_identifier: plugin_id)
    end

    private

    def load_installed_providers
      list_provider_plugins.each do |provider_info|
        @providers[provider_info[:plugin_id]] = provider_info
      end

      @logger.info "[PLUGIN_PROVIDER] Loaded #{@providers.size} provider plugins"
    end

    def sync_provider_credentials(provider, installation)
      # Sync authentication credentials from plugin installation to provider
      auth_schema = installation.plugin.ai_provider_plugin.authentication_schema

      auth_schema["fields"]&.each do |field|
        field_name = field["name"]
        credential_value = installation.get_credential(field_name)

        next if credential_value.blank?

        # Create or update provider credential
        credential = provider.provider_credentials.find_or_initialize_by(
          credential_type: field_name
        )

        credential.assign_attributes(
          account: account,
          credential_value: credential_value,
          is_active: true
        )

        credential.save!
      end
    end

    def provider_info(installation)
      plugin = installation.plugin
      provider_plugin = plugin.ai_provider_plugin

      {
        plugin_id: plugin.plugin_id,
        plugin_name: plugin.name,
        provider_type: provider_plugin.provider_type,
        capabilities: provider_plugin.supported_capabilities,
        models: provider_plugin.models,
        status: installation.status,
        configuration: installation.merged_configuration
      }
    end
  end
end
