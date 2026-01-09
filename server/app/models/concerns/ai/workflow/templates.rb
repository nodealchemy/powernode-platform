# frozen_string_literal: true

module Ai
  class Workflow
    module Templates
      extend ActiveSupport::Concern

      # Template methods
      def create_from_template(template, account, user, customizations = {})
        transaction do
          # Create workflow from template
          workflow_data = template.workflow_definition.deep_dup
          workflow_data.merge!(customizations)

          new_workflow = account.ai_workflows.create!(
            name: customizations["name"] || "#{template.name} (Copy)",
            description: customizations["description"] || template.description,
            creator: user,
            configuration: workflow_data["configuration"] || {},
            metadata: workflow_data["metadata"]&.merge("template_id" => template.id) || { "template_id" => template.id },
            status: "draft"
          )

          # Create nodes from template
          if workflow_data["nodes"].present?
            workflow_data["nodes"].each do |node_data|
              new_workflow.workflow_nodes.create!(
                node_id: node_data["node_id"],
                node_type: node_data["node_type"],
                name: node_data["name"],
                description: node_data["description"],
                position: node_data["position"] || {},
                configuration: node_data["configuration"] || {},
                validation_rules: node_data["validation_rules"] || {},
                metadata: node_data["metadata"] || {},
                is_start_node: node_data["is_start_node"] || false,
                is_end_node: node_data["is_end_node"] || false
              )
            end
          end

          # Create edges from template
          if workflow_data["edges"].present?
            workflow_data["edges"].each do |edge_data|
              new_workflow.workflow_edges.create!(
                edge_id: edge_data["edge_id"],
                source_node_id: edge_data["source_node_id"],
                target_node_id: edge_data["target_node_id"],
                source_handle: edge_data["source_handle"],
                target_handle: edge_data["target_handle"],
                edge_type: edge_data["edge_type"] || "default",
                condition: edge_data["condition"] || {},
                configuration: edge_data["configuration"] || {},
                is_conditional: edge_data["is_conditional"] || false
              )
            end
          end

          # Create variables from template
          if workflow_data["variables"].present?
            workflow_data["variables"].each do |var_data|
              new_workflow.workflow_variables.create!(
                name: var_data["name"],
                variable_type: var_data["variable_type"] || "string",
                description: var_data["description"],
                default_value: var_data["default_value"],
                validation_rules: var_data["validation_rules"] || {},
                is_required: var_data["is_required"] || false,
                is_input: var_data["is_input"] || false,
                is_output: var_data["is_output"] || false
              )
            end
          end

          # Record template installation
          installation = template.workflow_template_installations.create!(
            workflow: new_workflow,
            account: account,
            installed_by: user,
            installation_id: SecureRandom.uuid,
            template_version: template.version,
            customizations: customizations
          )

          # Update template usage count
          template.increment!(:usage_count)

          new_workflow
        end
      end

      def publish!
        return false unless can_edit? && has_valid_structure?

        update!(
          status: "active",
          published_at: Time.current,
          version: increment_version(version)
        )
      end

      def archive!
        update!(
          status: "archived",
          metadata: metadata.merge("archived_at" => Time.current.iso8601)
        )
      end

      def pause!
        update!(
          status: "paused",
          metadata: metadata.merge("paused_at" => Time.current.iso8601)
        )
      end

      private

      def increment_version(current_version)
        major, minor, patch = current_version.split(".").map(&:to_i)
        "#{major}.#{minor}.#{patch + 1}"
      end
    end
  end
end
