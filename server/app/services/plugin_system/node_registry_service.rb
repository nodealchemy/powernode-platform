# frozen_string_literal: true

module PluginSystem
  # Plugin Node Registry Service
  # Manages workflow node plugins and makes them available in the workflow builder
  class NodeRegistryService
    include ActiveModel::Model

    attr_accessor :account

    def initialize(account:)
      @account = account
      @logger = Rails.logger
      @node_types = {}

      load_installed_node_plugins
    end

    # Register a workflow node plugin
    def register_node_plugin(installation)
      plugin = installation.plugin

      return unless plugin.workflow_node?

      @logger.info "[PLUGIN_NODE] Registering node plugin: #{plugin.name}"

      plugin.workflow_node_plugins.each do |node_plugin|
        register_single_node_type(node_plugin, installation)
      end

      @logger.info "[PLUGIN_NODE] Node plugin registered: #{plugin.plugin_id}"
    end

    # Unregister a workflow node plugin
    def unregister_node_plugin(installation)
      plugin = installation.plugin

      @logger.info "[PLUGIN_NODE] Unregistering node plugin: #{plugin.name}"

      plugin.workflow_node_plugins.each do |node_plugin|
        @node_types.delete(node_plugin.node_type)
      end

      @logger.info "[PLUGIN_NODE] Node plugin unregistered: #{plugin.plugin_id}"
    end

    # Get all registered node types
    def list_node_types
      @node_types.values
    end

    # Get node type by ID
    def get_node_type(node_type_id)
      @node_types[node_type_id]
    end

    # Check if node type is registered
    def node_type_registered?(node_type_id)
      @node_types.key?(node_type_id)
    end

    # Get node types by category
    def get_node_types_by_category(category)
      @node_types.values.select { |nt| nt[:category] == category }
    end

    private

    def load_installed_node_plugins
      installations = PluginSystem::Installation
        .joins(:plugin)
        .where(account: account, status: "active")
        .where("'workflow_node' = ANY(plugins.plugin_types)")
        .includes(plugin: :workflow_node_plugins)

      installations.each do |installation|
        installation.plugin.workflow_node_plugins.each do |node_plugin|
          register_single_node_type(node_plugin, installation)
        end
      end

      @logger.info "[PLUGIN_NODE] Loaded #{@node_types.size} node type plugins"
    end

    def register_single_node_type(node_plugin, installation)
      node_type_id = node_plugin.node_type

      @node_types[node_type_id] = {
        node_type: node_type_id,
        plugin_id: installation.plugin.id,
        plugin_name: installation.plugin.name,
        plugin_installation_id: installation.id,
        category: node_plugin.node_category,
        input_schema: node_plugin.input_schema,
        output_schema: node_plugin.output_schema,
        configuration_schema: node_plugin.configuration_schema,
        ui_configuration: node_plugin.ui_configuration,
        icon: node_plugin.icon,
        color: node_plugin.color,
        description: node_plugin.display_description
      }

      @logger.debug "[PLUGIN_NODE] Registered node type: #{node_type_id}"
    end
  end
end
