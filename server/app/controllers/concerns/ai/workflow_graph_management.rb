# frozen_string_literal: true

# Shared workflow graph management logic for creating and updating nodes and edges
#
# This concern provides standardized methods for:
# - Creating workflow nodes from API data
# - Updating workflow nodes (including removal of deleted nodes)
# - Creating workflow edges from API data
# - Updating workflow edges (including removal of deleted edges)
#
# Usage:
#   class WorkflowsController < ApplicationController
#     include Ai::WorkflowGraphManagement
#
#     def create
#       @workflow = Ai::Workflow.create!(workflow_params)
#       create_workflow_nodes(params[:nodes]) if params[:nodes].present?
#       create_workflow_edges(params[:edges]) if params[:edges].present?
#     end
#
#     def update
#       update_workflow_nodes(params[:nodes]) if params[:nodes].is_a?(Array)
#       update_workflow_edges(params[:edges]) if params[:edges].is_a?(Array)
#       @workflow.update!(workflow_params)
#     end
#   end
#
module Ai
  module WorkflowGraphManagement
    extend ActiveSupport::Concern

    # =============================================================================
    # NODE MANAGEMENT
    # =============================================================================

    # Create workflow nodes from API data
    # @param nodes_data [Array<Hash>] Array of node data hashes
    # @return [Array<Ai::WorkflowNode>] Created nodes
    def create_workflow_nodes(nodes_data)
      return [] unless nodes_data.is_a?(Array)

      nodes_data.map do |node_data|
        @workflow.nodes.create!(
          node_id: node_data[:node_id],
          node_type: node_data[:node_type],
          name: node_data[:name],
          description: node_data[:description],
          position: normalize_position(node_data[:position]),
          configuration: node_data[:configuration] || {},
          metadata: node_data[:metadata] || {},
          is_start_node: node_data[:is_start_node] || false,
          is_end_node: node_data[:is_end_node] || false
        )
      end
    end

    # Update workflow nodes from API data
    # This will:
    # 1. Filter out invalid node data
    # 2. Delete nodes not in the update list
    # 3. Create or update each node
    # @param nodes_data [Array<Hash>] Array of node data hashes
    def update_workflow_nodes(nodes_data)
      return unless nodes_data.is_a?(Array)

      # Filter valid nodes (must have node_id and node_type)
      valid_nodes = nodes_data.select do |node_data|
        node_data[:node_id].present? && node_data[:node_type].present?
      end

      # Get current node IDs to delete nodes not in update
      current_node_ids = valid_nodes.map { |n| n[:node_id] }
      @workflow.nodes.where.not(node_id: current_node_ids).destroy_all

      # Prevent validation during bulk update
      @workflow.instance_variable_set(:@bulk_updating_nodes, true)

      begin
        valid_nodes.each do |node_data|
          node = @workflow.nodes.find_or_initialize_by(node_id: node_data[:node_id])
          node.assign_attributes(
            node_type: node_data[:node_type],
            name: node_data[:name],
            description: node_data[:description],
            position: normalize_position(node_data[:position]),
            configuration: node_data[:configuration] || {},
            metadata: node_data[:metadata] || {},
            is_start_node: node_data[:is_start_node] || false,
            is_end_node: node_data[:is_end_node] || false
          )
          node.save!
        end
      ensure
        @workflow.instance_variable_set(:@bulk_updating_nodes, false)
      end

      # Validate workflow after bulk update
      raise ActiveRecord::RecordInvalid.new(@workflow) unless @workflow.valid?
    end

    # =============================================================================
    # EDGE MANAGEMENT
    # =============================================================================

    # Create workflow edges from API data
    # @param edges_data [Array<Hash>] Array of edge data hashes
    # @return [Array<Ai::WorkflowEdge>] Created edges
    def create_workflow_edges(edges_data)
      return [] unless edges_data.is_a?(Array)

      edges_data.map do |edge_data|
        @workflow.edges.create!(
          edge_id: edge_data[:edge_id],
          source_node_id: edge_data[:source_node_id],
          target_node_id: edge_data[:target_node_id],
          source_handle: edge_data[:source_handle] || "output",
          target_handle: edge_data[:target_handle] || "input",
          edge_type: edge_data[:edge_type] || "default",
          is_conditional: edge_data[:is_conditional] || false,
          condition: edge_data[:condition] || {},
          priority: edge_data[:priority],
          metadata: edge_data[:metadata] || {}
        )
      end
    end

    # Update workflow edges from API data
    # This will:
    # 1. Filter out invalid edge data
    # 2. Delete edges not in the update list
    # 3. Create or update each edge
    # @param edges_data [Array<Hash>] Array of edge data hashes
    def update_workflow_edges(edges_data)
      return unless edges_data.is_a?(Array)

      # Filter valid edges (must have edge_id, source_node_id, and target_node_id)
      valid_edges = edges_data.select do |edge_data|
        edge_data[:edge_id].present? &&
          edge_data[:source_node_id].present? &&
          edge_data[:target_node_id].present?
      end

      # Get current edge IDs to delete edges not in update
      current_edge_ids = valid_edges.map { |e| e[:edge_id] }
      @workflow.edges.where.not(edge_id: current_edge_ids).destroy_all

      valid_edges.each do |edge_data|
        edge = @workflow.edges.find_or_initialize_by(edge_id: edge_data[:edge_id])
        edge.assign_attributes(
          source_node_id: edge_data[:source_node_id],
          target_node_id: edge_data[:target_node_id],
          source_handle: edge_data[:source_handle] || "output",
          target_handle: edge_data[:target_handle] || "input",
          edge_type: edge_data[:edge_type] || "default",
          is_conditional: edge_data[:is_conditional] || false,
          condition: edge_data[:condition] || {},
          priority: edge_data[:priority],
          metadata: edge_data[:metadata] || {}
        )
        edge.save!
      end
    end

    # =============================================================================
    # BULK OPERATIONS
    # =============================================================================

    # Update both nodes and edges in a single operation
    # @param nodes_data [Array<Hash>, nil] Array of node data hashes
    # @param edges_data [Array<Hash>, nil] Array of edge data hashes
    def update_workflow_graph(nodes_data:, edges_data:)
      ActiveRecord::Base.transaction do
        # Update nodes first (edges depend on nodes)
        if nodes_data.is_a?(Array)
          if nodes_data.any?
            update_workflow_nodes(nodes_data)
          else
            @workflow.nodes.destroy_all
          end
        end

        # Update edges after nodes
        if edges_data.is_a?(Array)
          if edges_data.any?
            update_workflow_edges(edges_data)
          else
            @workflow.edges.destroy_all
          end
        end
      end
    end

    # =============================================================================
    # TEMPLATE EXTRACTION
    # =============================================================================

    # Extract workflow template data from a workflow
    # @param workflow [Ai::Workflow] The workflow to extract from
    # @return [Hash] Template definition data
    def extract_workflow_template_data(workflow)
      {
        nodes: workflow.nodes.map do |node|
          {
            node_id: node.node_id,
            node_type: node.node_type,
            name: node.name,
            description: node.description,
            position: node.position,
            configuration: sanitize_node_configuration(node.configuration),
            metadata: node.metadata,
            is_start_node: node.is_start_node,
            is_end_node: node.is_end_node
          }
        end,
        edges: workflow.edges.map do |edge|
          {
            edge_id: edge.edge_id,
            source_node_id: edge.source_node_id,
            target_node_id: edge.target_node_id,
            source_handle: edge.source_handle,
            target_handle: edge.target_handle,
            edge_type: edge.edge_type,
            is_conditional: edge.is_conditional,
            condition: edge.condition,
            priority: edge.priority,
            metadata: edge.metadata
          }
        end,
        triggers: workflow.workflow_triggers.map do |trigger|
          {
            trigger_type: trigger.trigger_type,
            name: trigger.name,
            configuration: sanitize_trigger_configuration(trigger.configuration)
          }
        end,
        variables: workflow.variables.map do |variable|
          {
            name: variable.name,
            variable_type: variable.variable_type,
            default_value: variable.default_value,
            is_required: variable.is_required,
            description: variable.description
          }
        end,
        configuration: sanitize_workflow_configuration(workflow.configuration),
        metadata: {
          original_workflow_id: workflow.id,
          original_workflow_name: workflow.name,
          extracted_at: Time.current.iso8601
        }
      }
    end

    # Generate configuration schema from workflow
    # @param workflow [Ai::Workflow] The workflow to analyze
    # @return [Hash] JSON Schema for workflow configuration
    def generate_configuration_schema(workflow)
      schema = {
        type: "object",
        properties: {},
        required: []
      }

      # Add workflow variables to schema
      workflow.variables.each do |variable|
        schema[:properties][variable.name] = {
          type: map_variable_type_to_json_schema(variable.variable_type),
          description: variable.description,
          default: variable.default_value
        }
        schema[:required] << variable.name if variable.is_required
      end

      # Analyze nodes for additional configuration points
      workflow.nodes.each do |node|
        next unless node.configuration.is_a?(Hash)

        # Extract configurable parameters from node configuration
        node.configuration.each do |key, value|
          next if schema[:properties].key?(key)
          next unless value.is_a?(String) && value.start_with?("{{") && value.end_with?("}}")

          # This is a template variable
          var_name = value.gsub(/\{\{|\}\}/, "").strip
          schema[:properties][var_name] ||= {
            type: "string",
            description: "Configuration for #{node.name}: #{key}"
          }
        end
      end

      schema
    end

    # Calculate workflow complexity score
    # @param workflow [Ai::Workflow] The workflow to analyze
    # @return [Integer] Complexity score (1-100)
    def calculate_complexity_score(workflow)
      score = 0

      # Node count factor
      node_count = workflow.nodes.count
      score += [ node_count * 5, 30 ].min

      # Edge count factor
      edge_count = workflow.edges.count
      score += [ edge_count * 2, 20 ].min

      # Node type diversity
      unique_types = workflow.nodes.pluck(:node_type).uniq.count
      score += [ unique_types * 5, 20 ].min

      # Conditional edges factor
      conditional_edges = workflow.edges.where(is_conditional: true).count
      score += [ conditional_edges * 5, 15 ].min

      # Trigger count factor
      trigger_count = workflow.workflow_triggers.count
      score += [ trigger_count * 3, 15 ].min

      [ score, 100 ].min
    end

    private

    # Normalize position data
    # @param position [Hash, nil] Position data
    # @return [Hash] Normalized position with x and y
    def normalize_position(position)
      return { x: 0, y: 0 } unless position.is_a?(Hash)

      {
        x: position[:x] || position["x"] || 0,
        y: position[:y] || position["y"] || 0
      }
    end

    # Sanitize node configuration for template (remove secrets)
    # @param configuration [Hash] Node configuration
    # @return [Hash] Sanitized configuration
    def sanitize_node_configuration(configuration)
      return {} unless configuration.is_a?(Hash)

      configuration.deep_dup.tap do |config|
        # Remove any secret values
        %w[api_key secret token password credential].each do |secret_key|
          config.keys.each do |key|
            if key.to_s.downcase.include?(secret_key)
              config[key] = "{{#{key}}}"
            end
          end
        end
      end
    end

    # Sanitize trigger configuration for template
    # @param configuration [Hash] Trigger configuration
    # @return [Hash] Sanitized configuration
    def sanitize_trigger_configuration(configuration)
      return {} unless configuration.is_a?(Hash)

      # Remove webhook URLs and other environment-specific values
      configuration.deep_dup.tap do |config|
        config.delete("webhook_url")
        config.delete("callback_url")
      end
    end

    # Sanitize workflow configuration for template
    # @param configuration [Hash] Workflow configuration
    # @return [Hash] Sanitized configuration
    def sanitize_workflow_configuration(configuration)
      return {} unless configuration.is_a?(Hash)

      configuration.deep_dup.tap do |config|
        # Remove account-specific values
        config.delete("account_id")
        config.delete("owner_id")
      end
    end

    # Map variable type to JSON Schema type
    # @param variable_type [String] The variable type
    # @return [String] JSON Schema type
    def map_variable_type_to_json_schema(variable_type)
      case variable_type.to_s
      when "string", "text" then "string"
      when "integer", "number" then "number"
      when "boolean" then "boolean"
      when "array" then "array"
      when "object", "hash" then "object"
      else "string"
      end
    end
  end
end
