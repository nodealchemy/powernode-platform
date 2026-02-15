# frozen_string_literal: true

module Ai
  module Workflows
    class TemplateService
      module TemplateInstantiation
        extend ActiveSupport::Concern

        # Create a workflow from a template
        # @param template [Ai::WorkflowTemplate] Source template
        # @param options [Hash] Workflow options and customizations
        # @return [Result] Result object with workflow
        def create_workflow_from_template(template, options = {})
          workflow_definition = template.workflow_definition || {}
          customizations = options[:customizations] || {}

          workflow = ::Ai::Workflow.new(
            name: options[:name] || "#{template.name} Workflow",
            description: options[:description] || template.description,
            account: account,
            creator: user,
            status: "draft",
            visibility: "private",
            version: "1.0.0",
            configuration: merge_configuration(workflow_definition["configuration"], customizations),
            metadata: {
              source_template_id: template.id,
              source_template_version: template.version,
              created_from_template_at: Time.current.iso8601
            }
          )

          ActiveRecord::Base.transaction do
            workflow.save!

            # Create nodes from template
            create_nodes_from_template(workflow, workflow_definition["nodes"] || [], customizations)

            # Create edges from template
            create_edges_from_template(workflow, workflow_definition["edges"] || [])

            # Create triggers from template
            create_triggers_from_template(workflow, workflow_definition["triggers"] || [])

            # Create variables from template
            create_variables_from_template(workflow, workflow_definition["variables"] || [])
          end

          Result.success(workflow: workflow)
        rescue ActiveRecord::RecordInvalid => e
          Result.failure(error: e.record.errors.full_messages.join(", "))
        rescue StandardError => e
          Rails.logger.error("Workflow creation from template failed: #{e.message}")
          Result.failure(error: "Failed to create workflow: #{e.message}")
        end

        # Create a new workflow from a source workflow (used for template instantiation)
        # @param source_workflow [Ai::Workflow] Source workflow to duplicate
        # @param options [Hash] Options including :name override
        # @return [Result] Result object with workflow
        def create_workflow_from_source(source_workflow, options = {})
          new_workflow = source_workflow.duplicate(account, user)

          if options[:name].present?
            new_workflow.update!(name: options[:name])
          end

          Result.success(workflow: new_workflow)
        rescue ActiveRecord::RecordInvalid => e
          Result.failure(error: e.record.errors.full_messages.join(", "))
        rescue StandardError => e
          Rails.logger.error("Workflow creation from source failed: #{e.message}")
          Result.failure(error: "Failed to create workflow from source: #{e.message}")
        end

        private

        # Create nodes from template definition
        # @param workflow [Ai::Workflow] Target workflow
        # @param nodes_data [Array<Hash>] Node definitions
        # @param customizations [Hash] User customizations
        def create_nodes_from_template(workflow, nodes_data, customizations)
          nodes_data.each do |node_data|
            config = node_data[:configuration] || node_data["configuration"] || {}

            # Apply customizations
            if customizations[:nodes]&.dig(node_data[:node_id] || node_data["node_id"])
              config = config.merge(customizations[:nodes][node_data[:node_id] || node_data["node_id"]])
            end

            workflow.nodes.create!(
              node_id: node_data[:node_id] || node_data["node_id"],
              node_type: node_data[:node_type] || node_data["node_type"],
              name: node_data[:name] || node_data["name"],
              description: node_data[:description] || node_data["description"],
              position: node_data[:position] || node_data["position"] || { x: 0, y: 0 },
              configuration: config,
              metadata: node_data[:metadata] || node_data["metadata"] || {},
              is_start_node: node_data[:is_start_node] || node_data["is_start_node"] || false,
              is_end_node: node_data[:is_end_node] || node_data["is_end_node"] || false
            )
          end
        end

        # Create edges from template definition
        # @param workflow [Ai::Workflow] Target workflow
        # @param edges_data [Array<Hash>] Edge definitions
        def create_edges_from_template(workflow, edges_data)
          edges_data.each do |edge_data|
            workflow.edges.create!(
              edge_id: edge_data[:edge_id] || edge_data["edge_id"],
              source_node_id: edge_data[:source_node_id] || edge_data["source_node_id"],
              target_node_id: edge_data[:target_node_id] || edge_data["target_node_id"],
              source_handle: edge_data[:source_handle] || edge_data["source_handle"] || "output",
              target_handle: edge_data[:target_handle] || edge_data["target_handle"] || "input",
              edge_type: edge_data[:edge_type] || edge_data["edge_type"] || "default",
              is_conditional: edge_data[:is_conditional] || edge_data["is_conditional"] || false,
              condition: edge_data[:condition] || edge_data["condition"] || {},
              priority: edge_data[:priority] || edge_data["priority"],
              metadata: edge_data[:metadata] || edge_data["metadata"] || {}
            )
          end
        end

        # Create triggers from template definition
        # @param workflow [Ai::Workflow] Target workflow
        # @param triggers_data [Array<Hash>] Trigger definitions
        def create_triggers_from_template(workflow, triggers_data)
          triggers_data.each do |trigger_data|
            workflow.workflow_triggers.create!(
              trigger_type: trigger_data[:trigger_type] || trigger_data["trigger_type"],
              name: trigger_data[:name] || trigger_data["name"],
              configuration: trigger_data[:configuration] || trigger_data["configuration"] || {},
              is_active: false # Triggers start inactive
            )
          end
        end

        # Create variables from template definition
        # @param workflow [Ai::Workflow] Target workflow
        # @param variables_data [Array<Hash>] Variable definitions
        def create_variables_from_template(workflow, variables_data)
          variables_data.each do |variable_data|
            workflow.variables.create!(
              name: variable_data[:name] || variable_data["name"],
              variable_type: variable_data[:variable_type] || variable_data["variable_type"],
              default_value: variable_data[:default_value] || variable_data["default_value"],
              is_required: variable_data[:is_required] || variable_data["is_required"] || false,
              description: variable_data[:description] || variable_data["description"]
            )
          end
        end

        # Merge template configuration with customizations
        # @param base_config [Hash] Base configuration
        # @param customizations [Hash] User customizations
        # @return [Hash] Merged configuration
        def merge_configuration(base_config, customizations)
          (base_config || {}).deep_merge(customizations[:configuration] || {})
        end
      end
    end
  end
end
