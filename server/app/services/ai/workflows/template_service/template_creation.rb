# frozen_string_literal: true

module Ai
  module Workflows
    class TemplateService
      module TemplateCreation
        extend ActiveSupport::Concern

        # Create a template from an existing workflow
        # @param workflow [Ai::Workflow] Source workflow
        # @param options [Hash] Template options
        # @return [Result] Result object with template
        def create_from_workflow(workflow, options = {})
          template_data = build_template_data(workflow, options)

          template = ::Ai::WorkflowTemplate.new(template_data)

          if template.save
            Result.success(template: template)
          else
            Result.failure(error: template.errors.full_messages.join(", "))
          end
        rescue StandardError => e
          Rails.logger.error("Template creation failed: #{e.message}")
          Result.failure(error: "Failed to create template: #{e.message}")
        end

        # Convert an existing workflow to a template
        # @param workflow [Ai::Workflow] Workflow to convert
        # @param options [Hash] Conversion options
        # @return [Result] Result object with template
        def convert_to_template(workflow, options = {})
          validate_workflow_ownership!(workflow)

          # Update workflow to be a template
          workflow.is_template = true
          workflow.template_category = options[:category] || workflow.template_category
          workflow.metadata = workflow.metadata.merge(
            "template_created_at" => Time.current.iso8601,
            "template_created_by" => user.id
          )

          if workflow.save
            Result.success(workflow: workflow)
          else
            Result.failure(error: workflow.errors.full_messages.join(", "))
          end
        end

        private

        # Build template data from workflow
        # @param workflow [Ai::Workflow] Source workflow
        # @param options [Hash] Template options
        # @return [Hash] Template data
        def build_template_data(workflow, options)
          {
            name: options[:name] || "#{workflow.name} Template",
            description: options[:description] || workflow.description || "Template created from #{workflow.name}",
            category: options[:category] || "custom",
            difficulty_level: options[:difficulty_level] || calculate_difficulty(workflow),
            tags: options[:tags] || workflow.metadata&.dig("tags") || [],
            is_public: options[:is_public] || false,
            version: options[:version] || "1.0.0",
            license: options[:license] || "private",
            account_id: account.id,
            created_by_user_id: user.id,
            author_name: user.full_name,
            author_email: user.email,
            workflow_definition: extract_workflow_definition(workflow),
            metadata: {
              node_count: workflow.nodes.count,
              edge_count: workflow.edges.count,
              complexity_score: calculate_complexity_score(workflow),
              has_ai_agents: workflow.nodes.where(node_type: "ai_agent").exists?,
              has_webhooks: workflow.nodes.where(node_type: "webhook").exists?,
              has_schedules: workflow.triggers.where(trigger_type: "schedule").exists?,
              configuration_schema: generate_configuration_schema(workflow),
              source_workflow_id: workflow.id
            }
          }
        end

        # Extract workflow definition for template
        # @param workflow [Ai::Workflow] Source workflow
        # @return [Hash] Workflow definition
        def extract_workflow_definition(workflow)
          {
            nodes: workflow.nodes.map do |node|
              {
                node_id: node.node_id,
                node_type: node.node_type,
                name: node.name,
                description: node.description,
                position: node.position,
                configuration: sanitize_configuration(node.configuration),
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
                configuration: sanitize_configuration(trigger.configuration)
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
            configuration: sanitize_configuration(workflow.configuration)
          }
        end

        # Sanitize configuration to remove secrets
        # @param configuration [Hash] Configuration to sanitize
        # @return [Hash] Sanitized configuration
        def sanitize_configuration(configuration)
          return {} unless configuration.is_a?(Hash)

          configuration.deep_dup.tap do |config|
            %w[api_key secret token password credential].each do |secret_key|
              config.keys.each do |key|
                config[key] = "{{#{key}}}" if key.to_s.downcase.include?(secret_key)
              end
            end
          end
        end

        # Calculate workflow difficulty level
        # @param workflow [Ai::Workflow] Workflow to analyze
        # @return [String] Difficulty level
        def calculate_difficulty(workflow)
          complexity = calculate_complexity_score(workflow)

          case complexity
          when 0..20 then "beginner"
          when 21..50 then "intermediate"
          when 51..80 then "advanced"
          else "expert"
          end
        end

        # Calculate workflow complexity score
        # @param workflow [Ai::Workflow] Workflow to analyze
        # @return [Integer] Complexity score (1-100)
        def calculate_complexity_score(workflow)
          score = 0

          score += [ workflow.nodes.count * 5, 30 ].min
          score += [ workflow.edges.count * 2, 20 ].min
          score += [ workflow.nodes.pluck(:node_type).uniq.count * 5, 20 ].min
          score += [ workflow.edges.where(is_conditional: true).count * 5, 15 ].min
          score += [ workflow.workflow_triggers.count * 3, 15 ].min

          [ score, 100 ].min
        end

        # Generate configuration schema from workflow
        # @param workflow [Ai::Workflow] Workflow to analyze
        # @return [Hash] JSON Schema
        def generate_configuration_schema(workflow)
          schema = { type: "object", properties: {}, required: [] }

          workflow.variables.each do |variable|
            schema[:properties][variable.name] = {
              type: map_variable_type(variable.variable_type),
              description: variable.description,
              default: variable.default_value
            }
            schema[:required] << variable.name if variable.is_required
          end

          schema
        end

        # Map variable type to JSON Schema type
        # @param variable_type [String] Variable type
        # @return [String] JSON Schema type
        def map_variable_type(variable_type)
          case variable_type.to_s
          when "string", "text" then "string"
          when "integer", "number" then "number"
          when "boolean" then "boolean"
          when "array" then "array"
          when "object", "hash" then "object"
          else "string"
          end
        end

        def validate_workflow_ownership!(workflow)
          unless workflow.account_id == account.id
            raise OwnershipError, "Workflow does not belong to this account"
          end
        end
      end
    end
  end
end
