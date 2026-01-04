# frozen_string_literal: true

module Mcp
  # Mcp::NodeExecutionContext - Execution context for individual workflow nodes
  #
  # Provides isolated execution environment for each node with:
  # - Access to workflow variables and previous results
  # - Input/output data management
  # - Variable resolution and template processing
  # - Scoped context for node executors
  #
  # The context ensures proper data flow between nodes while maintaining
  # isolation and preventing unintended side effects.
  #
  # @example Creating execution context
  #   context = Mcp::NodeExecutionContext.new(
  #     node: workflow_node,
  #     workflow_run: run,
  #     execution_context: global_context,
  #     previous_results: node_results
  #   )
  #
  class NodeExecutionContext
    include ActiveModel::Model
    include ActiveModel::Attributes

    attr_reader :node, :workflow_run, :execution_context, :previous_results
    attr_reader :input_data, :scoped_variables, :node_config

    def initialize(node:, workflow_run:, execution_context:, previous_results: {})
      @node = node
      @workflow_run = workflow_run
      @execution_context = execution_context
      @previous_results = previous_results
      @logger = Rails.logger

      # Initialize context data
      initialize_context_data
    end

    # =============================================================================
    # CONTEXT INITIALIZATION
    # =============================================================================

    def initialize_context_data
      @logger.debug "[NODE_CONTEXT] Initializing context for node: #{@node.node_id}"

      # Get node configuration
      @node_config = @node.configuration || {}

      # Build input data for this node
      @input_data = build_input_data

      # Create scoped variable environment
      @scoped_variables = build_scoped_variables

      @logger.debug "[NODE_CONTEXT] Context initialized with #{@scoped_variables.keys.count} variables"
    end

    # =============================================================================
    # INPUT DATA BUILDING
    # =============================================================================

    def build_input_data
      input = {}

      # Start with workflow input variables as base
      workflow_inputs = @execution_context[:variables] || {}
      input.merge!(workflow_inputs)

      # MANDATORY: Always pass previous node outputs
      # This is the new standard - no backward compatibility mode
      predecessor_outputs = auto_wire_predecessor_outputs
      input.merge!(predecessor_outputs) if predecessor_outputs.present?

      # Apply explicit input mapping if configured (overrides auto-wired data)
      if @node_config["input_mapping"].present?
        mapped_inputs = map_inputs_from_previous_nodes
        input.merge!(mapped_inputs)

        @logger.debug "[NODE_CONTEXT] Applied explicit input mapping: #{@node_config['input_mapping'].keys.join(', ')}"
      end

      # Add node-specific static inputs (highest priority - overrides everything)
      if @node_config["static_inputs"].present?
        input.merge!(@node_config["static_inputs"])
      end

      # Process template expressions in input data
      input = process_templates(input)

      @logger.debug "[NODE_CONTEXT] Built input data for #{@node.name}: #{input.keys.join(', ')}"

      input
    end

    def map_inputs_from_previous_nodes
      input_mapping = @node_config["input_mapping"]
      mapped = {}

      input_mapping.each do |target_key, source_expression|
        value = resolve_expression(source_expression)
        mapped[target_key] = value if value.present?
      end

      mapped
    end

    def auto_wire_predecessor_outputs
      # Find nodes that connect to this node
      incoming_edges = @workflow_run.ai_workflow.ai_workflow_edges.where(
        target_node_id: @node.node_id
      )

      predecessor_node_ids = incoming_edges.pluck(:source_node_id)
      auto_wired = {}

      # Safety check: ensure @previous_results is a hash
      return auto_wired if @previous_results.nil? || !@previous_results.is_a?(Hash)

      predecessor_node_ids.each do |predecessor_id|
        result_data = @previous_results[predecessor_id]

        if result_data.present?
          # STANDARD (v1.0): Merge output, data, and result keys ONLY
          # See: docs/platform/WORKFLOW_IO_STANDARD.md
          # NO BACKWARD COMPATIBILITY - all nodes must use standard format

          # Add primary output with node prefix to avoid collisions
          if result_data[:output].present?
            auto_wired["#{predecessor_id}_output"] = result_data[:output]
            # Also add as generic 'output' (will be overwritten by later nodes)
            auto_wired["output"] = result_data[:output]
          end

          # Merge data section (supporting information)
          if result_data[:data].present?
            result_data[:data].each do |key, value|
              # Add with node prefix for specificity
              auto_wired["#{predecessor_id}_#{key}"] = value
              # Also add without prefix (will be overwritten by later nodes)
              auto_wired[key.to_s] = value
            end
          end

          # Merge result section (computed values)
          if result_data[:result].present?
            auto_wired["#{predecessor_id}_result"] = result_data[:result]
            auto_wired["result"] = result_data[:result]
          end
        end
      end

      auto_wired
    end

    # =============================================================================
    # VARIABLE MANAGEMENT
    # =============================================================================

    def build_scoped_variables
      variables = {}

      # Global workflow variables
      variables.merge!(@execution_context[:variables] || {})

      # Node-scoped variables
      if @node_config["local_variables"].present?
        variables.merge!(@node_config["local_variables"])
      end

      # CRITICAL FIX: Include input_data in scoped variables
      # This allows template placeholders like {{outline_output}} to resolve
      # input_data contains auto-wired predecessor outputs and workflow inputs
      variables.merge!(@input_data) if @input_data.present?

      # Previous node results accessible as variables
      # IMPORTANT: Make ALL previous results accessible via multiple naming conventions
      # This ensures templates can use {{node_id_output}} regardless of graph structure
      @previous_results.each do |node_id, result|
        next unless result.present?

        # Store full result with node_ prefix
        variables["node_#{node_id}_result"] = result

        # Extract and store output with standard {node_id}_output naming
        # This allows templates to reference any previous node's output directly
        if result.is_a?(Hash)
          output = result[:output] || result["output"]
          if output.present?
            variables["#{node_id}_output"] = output
          end

          # Also extract data fields with {node_id}_{field} naming
          data = result[:data] || result["data"]
          if data.is_a?(Hash)
            data.each do |key, value|
              variables["#{node_id}_#{key}"] = value
            end
          end
        end
      end

      # Special context variables
      variables["_workflow_id"] = @workflow_run.ai_workflow_id
      variables["_run_id"] = @workflow_run.run_id
      variables["_node_id"] = @node.node_id
      variables["_node_name"] = @node.name
      variables["_execution_time"] = Time.current.iso8601

      variables
    end

    # Get a variable value
    #
    # @param name [String, Symbol] Variable name
    # @param default [Object] Default value if not found
    # @return [Object] Variable value
    def get_variable(name, default = nil)
      return default if @scoped_variables.nil?

      @scoped_variables[name.to_s] || default
    end

    # Set a variable in the scoped context
    #
    # @param name [String, Symbol] Variable name
    # @param value [Object] Variable value
    def set_variable(name, value)
      @scoped_variables[name.to_s] = value
    end

    # Check if variable exists
    #
    # @param name [String, Symbol] Variable name
    # @return [Boolean]
    def has_variable?(name)
      @scoped_variables.key?(name.to_s)
    end

    # =============================================================================
    # EXPRESSION RESOLUTION
    # =============================================================================

    # Resolve an expression to its value
    #
    # Supported expression formats:
    # - ${variable_name} - Variable reference
    # - ${node.node_id.path} - Node result path
    # - ${workflow.variable_name} - Workflow variable
    # - literal values
    #
    # @param expression [String] Expression to resolve
    # @return [Object] Resolved value
    def resolve_expression(expression)
      return expression unless expression.is_a?(String)

      # Check for variable reference: ${...}
      if expression.match?(/\A\$\{(.+)\}\z/)
        variable_path = expression.match(/\A\$\{(.+)\}\z/)[1]
        return resolve_variable_path(variable_path)
      end

      # Check for node result reference: @node_id or @node_id.path
      if expression.match?(/\A@([a-zA-Z0-9_-]+)(\..+)?\z/)
        matches = expression.match(/\A@([a-zA-Z0-9_-]+)(\..+)?\z/)
        node_id = matches[1]
        path = matches[2]&.delete_prefix(".")

        return resolve_node_result(node_id, path)
      end

      # Check for workflow variable reference: workflow.variable_name
      if expression.start_with?("workflow.")
        variable_name = expression.delete_prefix("workflow.")
        return @execution_context[:variables][variable_name]
      end

      # Return literal value
      expression
    end

    def resolve_variable_path(path)
      # Handle special paths
      if path.start_with?("node.")
        # ${node.node_id.field.subfield}
        parts = path.split(".")
        node_id = parts[1]
        field_path = parts[2..].join(".")

        return resolve_node_result(node_id, field_path)
      end

      if path.start_with?("workflow.")
        # ${workflow.variable_name}
        variable_name = path.delete_prefix("workflow.")
        return @execution_context[:variables][variable_name]
      end

      # Simple variable reference: ${variable_name}
      get_variable(path)
    end

    def resolve_node_result(node_id, path = nil)
      result = @previous_results[node_id]
      return nil unless result

      # If no path specified, return full result
      return result if path.blank?

      # Navigate path through result
      extract_value_from_path(result, path)
    end

    def extract_value_from_path(data, path)
      return data if path.blank?

      path.to_s.split(".").reduce(data) do |current, key|
        break nil unless current.respond_to?(:[])

        # Handle array index access
        if current.is_a?(Array) && key =~ /\A\d+\z/
          current[key.to_i]
        else
          current[key.to_s] || current[key.to_sym]
        end
      end
    end

    # =============================================================================
    # TEMPLATE PROCESSING
    # =============================================================================

    # Process template expressions in data structure
    #
    # @param data [Object] Data to process
    # @return [Object] Processed data
    def process_templates(data)
      case data
      when Hash
        data.transform_values { |v| process_templates(v) }
      when Array
        data.map { |v| process_templates(v) }
      when String
        interpolate_string(data)
      else
        data
      end
    end

    # Interpolate variables in a string
    #
    # Supports both ${var} and {{var}} syntax
    #
    # @param string [String] Template string
    # @return [String] Interpolated string
    def interpolate_string(string)
      return string unless string.is_a?(String)

      result = string.dup

      # Process ${variable} expressions
      result.gsub!(/\$\{([^}]+)\}/) do |match|
        expression = $1
        value = resolve_expression("${#{expression}}")
        value.is_a?(String) ? value : value.to_json
      end

      # Process {{variable}} expressions
      result.gsub!(/\{\{([^}]+)\}\}/) do |match|
        variable_name = $1.strip
        value = get_variable(variable_name)

        # Handle nil values gracefully
        if value.nil?
          match  # Keep the placeholder if variable not found
        elsif value.is_a?(String)
          value
        else
          value.to_json
        end
      end

      result
    end

    # =============================================================================
    # OUTPUT MANAGEMENT
    # =============================================================================

    # Prepare output data with proper formatting
    #
    # @param raw_output [Object] Raw output from node executor
    # @return [Hash] Formatted output data
    def format_output(raw_output)
      return {} if raw_output.blank?

      formatted = {}

      if raw_output.is_a?(Hash)
        formatted = raw_output.dup

        # Ensure standard fields
        formatted["node_id"] ||= @node.node_id
        formatted["node_type"] ||= @node.node_type
        formatted["executed_at"] ||= Time.current.iso8601

        # Add output metadata
        formatted["_metadata"] ||= build_output_metadata
      else
        # Wrap non-hash output
        formatted = {
          "content" => raw_output,
          "node_id" => @node.node_id,
          "node_type" => @node.node_type,
          "executed_at" => Time.current.iso8601,
          "_metadata" => build_output_metadata
        }
      end

      formatted
    end

    def build_output_metadata
      {
        "node_execution_context" => {
          "node_id" => @node.node_id,
          "node_name" => @node.name,
          "node_type" => @node.node_type,
          "workflow_id" => @workflow_run.ai_workflow_id,
          "run_id" => @workflow_run.run_id
        },
        "execution_timestamp" => Time.current.iso8601
      }
    end

    # =============================================================================
    # CONFIGURATION HELPERS
    # =============================================================================

    # Get node configuration value
    #
    # @param key [String] Configuration key
    # @param default [Object] Default value
    # @return [Object] Configuration value
    def config(key, default = nil)
      @node_config[key.to_s] || default
    end

    # Get MCP tool configuration
    #
    # @return [Hash] MCP tool configuration
    def mcp_tool_config
      {
        "tool_id" => @node.mcp_tool_id,
        "tool_version" => @node.mcp_tool_version,
        "tool_config" => @node_config["mcp_tool_config"] || {}
      }
    end

    # =============================================================================
    # CONTEXT SERIALIZATION
    # =============================================================================

    # Convert context to hash for storage/debugging
    #
    # @return [Hash] Context data
    def to_h
      {
        node_id: @node.node_id,
        node_type: @node.node_type,
        input_data: @input_data,
        scoped_variables: @scoped_variables,
        node_config: @node_config,
        execution_context_id: @execution_context[:run_id]
      }
    end

    # Get context summary for logging
    #
    # @return [Hash] Context summary
    def summary
      {
        node_id: @node.node_id,
        node_name: @node.name,
        node_type: @node.node_type,
        variable_count: @scoped_variables.keys.count,
        input_keys: @input_data.keys,
        has_previous_results: @previous_results.any?
      }
    end

    # =============================================================================
    # PERSISTENT CONTEXT ACCESS
    # =============================================================================

    # Get agent memory entries for a specific agent
    #
    # @param agent_id [String] Agent ID
    # @return [Hash, nil] Agent memory data or nil
    def get_agent_memory(agent_id)
      @execution_context.dig(:agent_memories, agent_id)
    end

    # Get all loaded agent memories
    #
    # @return [Hash] All agent memories keyed by agent_id
    def agent_memories
      @execution_context[:agent_memories] || {}
    end

    # Get a specific memory entry for an agent
    #
    # @param agent_id [String] Agent ID
    # @param key [String] Memory entry key
    # @return [Object, nil] Memory value or nil
    def recall_agent_memory(agent_id, key)
      @execution_context.dig(:agent_memories, agent_id, :entries, key)
    end

    # Get knowledge base by ID
    #
    # @param kb_id [String] Knowledge base ID
    # @return [Hash, nil] Knowledge base data or nil
    def get_knowledge_base(kb_id)
      @execution_context.dig(:knowledge_bases, kb_id)
    end

    # Get all loaded knowledge bases
    #
    # @return [Hash] All knowledge bases keyed by ID
    def knowledge_bases
      @execution_context[:knowledge_bases] || {}
    end

    # Get persistent context by ID
    #
    # @param context_id [String] Context ID
    # @return [AiPersistentContext, nil] Context object or nil
    def get_persistent_context(context_id)
      @execution_context.dig(:persistent_contexts, context_id)
    end

    # Check if agent memory is available
    #
    # @param agent_id [String] Agent ID
    # @return [Boolean]
    def has_agent_memory?(agent_id)
      @execution_context.dig(:agent_memories, agent_id).present?
    end

    # Get relevant context entries for the current node
    # Searches across all loaded knowledge bases
    #
    # @param query [String] Search query
    # @param limit [Integer] Maximum results
    # @return [Array] Matching context entries
    def search_knowledge(query, limit: 10)
      return [] unless query.present?

      results = []
      knowledge_bases.each_value do |kb_data|
        context = kb_data[:context]
        next unless context.present?

        entries = context.ai_context_entries
          .active
          .where("content_text ILIKE ?", "%#{query}%")
          .order(importance_score: :desc)
          .limit(limit)

        results.concat(entries.to_a)
      end

      results.sort_by { |e| -e.importance_score }.first(limit)
    end

    # =============================================================================
    # UTILITY METHODS
    # =============================================================================

    # Get workflow run
    #
    # @return [AiWorkflowRun]
    def workflow_run
      @workflow_run
    end

    # Get workflow
    #
    # @return [AiWorkflow]
    def workflow
      @workflow_run.ai_workflow
    end

    # Get account
    #
    # @return [Account]
    def account
      @workflow_run.account
    end

    # Get user
    #
    # @return [User]
    def user
      @workflow_run.triggered_by_user
    end

    # Get all available data for node execution
    #
    # @return [Hash] Complete data context
    def execution_data
      {
        input: @input_data,
        variables: @scoped_variables,
        config: @node_config,
        workflow_context: @execution_context,
        previous_results: @previous_results
      }
    end

    # Check if node should retry on failure
    #
    # @return [Boolean]
    def retry_on_failure?
      retry_count = config("retry_count", 0)
      retry_count.to_i > 0
    end

    # Get retry configuration
    #
    # @return [Hash] Retry settings
    def retry_config
      {
        max_retries: config("retry_count", 0).to_i,
        retry_delay: config("retry_delay", 1).to_f,
        backoff_multiplier: config("backoff_multiplier", 2).to_f,
        max_retry_delay: config("max_retry_delay", 60).to_f
      }
    end

    # Get timeout configuration
    #
    # @return [Integer] Timeout in seconds
    def timeout_seconds
      @node.timeout_seconds || config("timeout_seconds", 300).to_i
    end
  end
end
