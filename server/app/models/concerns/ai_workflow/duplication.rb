# frozen_string_literal: true

module AiWorkflow::Duplication
  extend ActiveSupport::Concern

  def duplicate(target_account = nil, user = nil)
    target_account ||= account
    user ||= creator
    duplicate_for_account(target_account, user)
  end

  def duplicate_for_account(target_account, user)
    transaction do
      new_workflow = self.class.new(
        account: target_account,
        creator: user,
        name: "#{name} (Copy)",
        description: description,
        configuration: configuration.deep_dup,
        metadata: metadata.deep_dup.merge(
          "duplicated_from" => id,
          "duplicated_at" => Time.current.iso8601
        ),
        visibility: "private",
        status: "draft"
      )

      new_workflow.save!

      # Duplicate nodes with new node IDs
      node_id_mapping = {}
      ai_workflow_nodes.each do |node|
        new_node_id = SecureRandom.uuid
        node_id_mapping[node.node_id] = new_node_id

        new_workflow.ai_workflow_nodes.create!(
          node_id: new_node_id,
          node_type: node.node_type,
          name: node.name,
          description: node.description,
          position: node.position.dup,
          configuration: node.configuration.deep_dup,
          validation_rules: node.validation_rules.deep_dup,
          metadata: node.metadata.deep_dup,
          is_start_node: node.is_start_node,
          is_end_node: node.is_end_node,
          is_error_handler: node.is_error_handler,
          error_node_id: node.error_node_id,
          timeout_seconds: node.timeout_seconds,
          retry_count: node.retry_count
        )
      end

      # Duplicate edges with mapped node IDs
      ai_workflow_edges.each do |edge|
        new_workflow.ai_workflow_edges.create!(
          edge_id: SecureRandom.uuid,
          source_node_id: node_id_mapping[edge.source_node_id],
          target_node_id: node_id_mapping[edge.target_node_id],
          source_handle: edge.source_handle,
          target_handle: edge.target_handle,
          edge_type: edge.edge_type,
          condition: edge.condition.deep_dup,
          configuration: edge.configuration.deep_dup,
          metadata: edge.metadata.deep_dup,
          is_conditional: edge.is_conditional,
          priority: edge.priority
        )
      end

      # Duplicate variables
      ai_workflow_variables.each do |variable|
        new_workflow.ai_workflow_variables.create!(
          name: variable.name,
          variable_type: variable.variable_type,
          description: variable.description,
          default_value: variable.default_value.deep_dup,
          validation_rules: variable.validation_rules.deep_dup,
          metadata: variable.metadata.deep_dup,
          is_required: variable.is_required,
          is_input: variable.is_input,
          is_output: variable.is_output,
          is_secret: variable.is_secret,
          scope: variable.scope
        )
      end

      new_workflow
    end
  end

  class_methods do
    def import_from_data(import_data, target_account, user, name_override: nil)
      transaction do
        workflow_data = import_data[:workflow] || import_data["workflow"]
        nodes_data = import_data[:nodes] || import_data["nodes"] || []
        edges_data = import_data[:edges] || import_data["edges"] || []

        workflow = create!(
          account: target_account,
          creator: user,
          name: name_override || workflow_data[:name] || workflow_data["name"],
          description: workflow_data[:description] || workflow_data["description"],
          status: workflow_data[:status] || workflow_data["status"] || "draft",
          visibility: workflow_data[:visibility] || workflow_data["visibility"] || "private",
          configuration: workflow_data[:configuration] || workflow_data["configuration"] || {}
        )

        # Import nodes
        node_id_mapping = {}
        nodes_data.each do |node_data|
          old_node_id = node_data[:node_id] || node_data["node_id"]
          new_node_id = SecureRandom.uuid
          new_node = workflow.ai_workflow_nodes.create!(
            node_id: new_node_id,
            node_type: node_data[:node_type] || node_data["node_type"],
            name: node_data[:name] || node_data["name"],
            position: node_data[:position] || node_data["position"] || {},
            configuration: node_data[:configuration] || node_data["configuration"] || {},
            is_start_node: node_data[:is_start_node] || node_data["is_start_node"] || false,
            is_end_node: node_data[:is_end_node] || node_data["is_end_node"] || false
          )
          node_id_mapping[old_node_id] = new_node.node_id
        end

        # Import edges with updated node IDs
        edges_data.each do |edge_data|
          old_source = edge_data[:source_node_id] || edge_data["source_node_id"]
          old_target = edge_data[:target_node_id] || edge_data["target_node_id"]

          workflow.ai_workflow_edges.create!(
            edge_id: SecureRandom.uuid,
            source_node_id: node_id_mapping[old_source],
            target_node_id: node_id_mapping[old_target],
            edge_type: edge_data[:edge_type] || edge_data["edge_type"] || "default",
            configuration: edge_data[:configuration] || edge_data["configuration"] || {}
          )
        end

        workflow
      end
    end
  end
end
