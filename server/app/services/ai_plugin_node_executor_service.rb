# frozen_string_literal: true

# AI Plugin Node Executor Service
# Executes AI workflow nodes that are implemented as plugins
class AiPluginNodeExecutorService
  include ActiveModel::Model

  attr_accessor :node_execution, :account

  def initialize(node_execution:, account:)
    @node_execution = node_execution
    @account = account
    @logger = Rails.logger
  end

  # Execute a plugin-based workflow node
  def execute(input_data)
    node = @node_execution.ai_workflow_node
    plugin = node.plugin

    return failure_result('No plugin associated with node') if plugin.nil?

    installation = plugin.installation_for(@account)
    return failure_result('Plugin not installed') if installation.nil?
    return failure_result('Plugin not active') if installation.status != 'active'

    @logger.info "[PLUGIN_NODE_EXEC] Executing plugin node: #{plugin.name} (#{node.node_type})"

    # Get node plugin configuration
    node_plugin = plugin.workflow_node_plugins.find_by(node_type: node.node_type)
    return failure_result('Node type configuration not found') if node_plugin.nil?

    # Validate input
    unless node_plugin.validate_input(input_data)
      return failure_result('Input validation failed')
    end

    # Execute the plugin node
    begin
      result = execute_plugin_node(plugin, node_plugin, installation, node, input_data)

      # Validate output
      unless node_plugin.validate_output(result[:output_data])
        return failure_result('Output validation failed')
      end

      # Track usage
      installation.mark_used!

      success_result(result[:output_data], result[:metadata])
    rescue StandardError => e
      @logger.error "[PLUGIN_NODE_EXEC] Execution error: #{e.message}"
      @logger.error e.backtrace.join("\n")
      failure_result("Execution failed: #{e.message}")
    end
  end

  private

  def execute_plugin_node(plugin, node_plugin, installation, node, input_data)
    # Build execution context
    context = {
      plugin_id: plugin.id,
      installation_id: installation.id,
      node_id: node.id,
      node_execution_id: @node_execution.id,
      configuration: node.configuration.merge(installation.merged_configuration),
      input_data: input_data,
      node_type: node.node_type,
      schemas: {
        input: node_plugin.input_schema,
        output: node_plugin.output_schema,
        configuration: node_plugin.configuration_schema
      }
    }

    # Determine execution strategy based on plugin configuration
    endpoint = plugin.manifest.dig('endpoints', 'node_execute')

    if endpoint.present?
      # Execute via HTTP endpoint
      execute_via_http(endpoint, context, installation)
    else
      # Execute via built-in executor (for simple transformations)
      execute_builtin(context, node_plugin)
    end
  end

  def execute_via_http(endpoint, context, installation)
    base_url = installation.merged_configuration['base_url'] || installation.plugin.source_url
    full_url = URI.join(base_url, endpoint).to_s

    @logger.debug "[PLUGIN_NODE_EXEC] Executing via HTTP: #{full_url}"

    response = HTTP.timeout(30).post(full_url, json: {
      context: context,
      input: context[:input_data]
    })

    if response.status.success?
      result = JSON.parse(response.body.to_s)
      {
        output_data: result['output'] || result['result'] || {},
        metadata: result['metadata'] || {}
      }
    else
      raise StandardError, "HTTP execution failed: #{response.status} - #{response.body}"
    end
  end

  def execute_builtin(context, node_plugin)
    # For simple transformations without external endpoints
    # This would be extended based on plugin capabilities
    @logger.debug "[PLUGIN_NODE_EXEC] Executing builtin transformation"

    {
      output_data: context[:input_data],
      metadata: {
        executed_at: Time.current.iso8601,
        node_type: context[:node_type],
        plugin_id: context[:plugin_id]
      }
    }
  end

  def success_result(output_data, metadata = {})
    {
      success: true,
      output_data: output_data,
      metadata: metadata
    }
  end

  def failure_result(error_message)
    {
      success: false,
      error_message: error_message,
      output_data: {}
    }
  end
end
