# frozen_string_literal: true

# Plugin Installation Service
# Handles installation, uninstallation, and lifecycle management of plugins
class PluginInstallationService
  include ActiveModel::Model

  attr_accessor :account, :user

  def initialize(account: nil, user: nil)
    @account = account
    @user = user
    @logger = Rails.logger
  end

  # Install a plugin for an account
  def install_plugin(plugin, target_account, installing_user, configuration = {})
    @account = target_account
    @user = installing_user

    @logger.info "[PLUGIN_INSTALL] Installing plugin: #{plugin.name} (#{plugin.plugin_id})"

    # Check if already installed
    if plugin.installed_for?(target_account)
      raise StandardError, "Plugin #{plugin.name} is already installed"
    end

    # Validate compatibility
    validate_compatibility!(plugin)

    # Validate dependencies
    validate_dependencies!(plugin)

    # Create installation record
    installation = PluginInstallation.create!(
      account: target_account,
      plugin: plugin,
      installed_by: installing_user,
      status: 'active',
      configuration: configuration,
      installed_at: Time.current
    )

    # Update plugin statistics
    plugin.increment_install_count!

    @logger.info "[PLUGIN_INSTALL] Plugin installed successfully: #{installation.id}"
    installation
  rescue StandardError => e
    @logger.error "[PLUGIN_INSTALL] Installation failed: #{e.message}"
    raise
  end

  # Uninstall a plugin
  def uninstall_plugin(installation)
    @logger.info "[PLUGIN_INSTALL] Uninstalling plugin: #{installation.plugin.name}"

    # Check for dependent plugins
    check_dependent_plugins!(installation)

    # Deactivate before destroying
    installation.deactivate! if installation.status == 'active'

    # Destroy installation
    installation.destroy!

    @logger.info "[PLUGIN_INSTALL] Plugin uninstalled successfully"
  rescue StandardError => e
    @logger.error "[PLUGIN_INSTALL] Uninstallation failed: #{e.message}"
    raise
  end

  # Update plugin configuration
  def update_plugin_configuration(installation, new_configuration)
    @logger.info "[PLUGIN_INSTALL] Updating plugin configuration: #{installation.plugin.name}"

    installation.update_configuration(new_configuration)

    # Reload plugin resources if active
    if installation.status == 'active'
      reload_plugin_resources(installation)
    end

    installation
  end

  private

  def validate_compatibility!(plugin)
    # Check Powernode version compatibility
    unless plugin.compatible_with?(Rails.application.config.version)
      raise StandardError, "Plugin #{plugin.name} is not compatible with this Powernode version"
    end

    # Check plugin types are supported
    unsupported_types = plugin.plugin_types - %w[ai_provider workflow_node integration]
    if unsupported_types.any?
      raise StandardError, "Unsupported plugin types: #{unsupported_types.join(', ')}"
    end
  end

  def validate_dependencies!(plugin)
    dependencies = plugin.plugin_dependencies.required

    dependencies.each do |dependency|
      unless dependency.satisfied?(@account)
        dep_plugin = dependency.dependency_plugin(@account)
        if dep_plugin
          raise StandardError, "Dependency #{dependency.dependency_plugin_id} version constraint not satisfied"
        else
          raise StandardError, "Required dependency #{dependency.dependency_plugin_id} is not installed"
        end
      end
    end
  end

  def check_dependent_plugins!(installation)
    # Check if any installed plugins depend on this one
    dependent_installations = PluginInstallation
      .joins(:plugin)
      .joins('INNER JOIN plugin_dependencies ON plugin_dependencies.plugin_id = plugins.id')
      .where(account: installation.account, status: 'active')
      .where('plugin_dependencies.dependency_plugin_id = ?', installation.plugin.plugin_id)
      .where('plugin_dependencies.is_required = ?', true)

    if dependent_installations.exists?
      dependent_names = dependent_installations.map { |i| i.plugin.name }.join(', ')
      raise StandardError, "Cannot uninstall: Required by #{dependent_names}"
    end
  end

  def reload_plugin_resources(installation)
    # Unregister and re-register plugin resources with updated configuration
    installation.send(:unregister_plugin_resources)
    installation.send(:register_plugin_resources)
  end
end
