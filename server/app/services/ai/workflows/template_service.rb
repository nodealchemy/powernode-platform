# frozen_string_literal: true

module Ai
  module Workflows
    # Service for managing workflow templates - creation, conversion, and instantiation
    #
    # Consolidates template-related logic from WorkflowsController and MarketplaceController:
    # - Converting workflows to templates
    # - Creating workflows from templates
    # - Template configuration and customization
    # - Template publishing and versioning
    #
    # Usage:
    #   service = Ai::Workflows::TemplateService.new(account: current_account, user: current_user)
    #   result = service.create_from_workflow(workflow, name: "My Template", is_public: true)
    #
    class TemplateService
      attr_reader :account, :user

      # Initialize the service
      # @param account [Account] The account context
      # @param user [User] The user performing operations
      def initialize(account:, user:)
        @account = account
        @user = user
      end

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

      # Publish a template to the marketplace
      # @param template [Ai::WorkflowTemplate] Template to publish
      # @param options [Hash] Publishing options
      # @return [Result] Result object
      def publish_template(template, options = {})
        validate_template_ownership!(template)

        # Validate template is ready for publishing
        validation = validate_for_publishing(template)
        return validation if validation.failure?

        template.assign_attributes(
          is_public: options[:is_public] || true,
          is_featured: options[:is_featured] || false,
          published_at: Time.current,
          version: bump_version(template.version, options[:version_bump] || "patch")
        )

        if template.save
          Result.success(template: template)
        else
          Result.failure(error: template.errors.full_messages.join(", "))
        end
      end

      # Update template version
      # @param template [Ai::WorkflowTemplate] Template to update
      # @param changes [Hash] Changes to apply
      # @param version_bump [String] Version bump type (major, minor, patch)
      # @return [Result] Result object
      def update_template_version(template, changes:, version_bump: "patch")
        validate_template_ownership!(template)

        new_version = bump_version(template.version, version_bump)

        template.assign_attributes(changes.merge(
          version: new_version,
          metadata: template.metadata.merge(
            "version_history" => (template.metadata["version_history"] || []) + [
              {
                version: template.version,
                updated_at: Time.current.iso8601,
                updated_by: user.id
              }
            ]
          )
        ))

        if template.save
          Result.success(template: template)
        else
          Result.failure(error: template.errors.full_messages.join(", "))
        end
      end

      # Export template as JSON
      # @param template [Ai::WorkflowTemplate] Template to export
      # @return [Result] Result object with export data
      def export_template(template)
        {
          name: template.name,
          description: template.description,
          version: template.version,
          category: template.category,
          difficulty_level: template.difficulty_level,
          tags: template.tags,
          license: template.license,
          workflow_definition: template.workflow_definition,
          configuration_schema: template.metadata&.dig("configuration_schema"),
          exported_at: Time.current.iso8601,
          exported_by: user.email
        }

        Result.success(export_data: export_data)
      end

      # Import template from JSON
      # @param import_data [Hash] Imported template data
      # @return [Result] Result object with template
      def import_template(import_data)
        template = ::Ai::WorkflowTemplate.new(
          name: import_data["name"],
          description: import_data["description"],
          version: import_data["version"] || "1.0.0",
          category: import_data["category"] || "imported",
          difficulty_level: import_data["difficulty_level"] || "intermediate",
          tags: import_data["tags"] || [],
          license: import_data["license"] || "private",
          is_public: false,
          workflow_definition: import_data["workflow_definition"],
          account: account,
          created_by_user: user,
          author_name: user.full_name,
          author_email: user.email,
          metadata: {
            imported_at: Time.current.iso8601,
            original_exported_at: import_data["exported_at"],
            configuration_schema: import_data["configuration_schema"]
          }
        )

        if template.save
          Result.success(template: template)
        else
          Result.failure(error: template.errors.full_messages.join(", "))
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
          source_workflow_id: workflow.id,
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

      # Validate template is ready for publishing
      # @param template [Ai::WorkflowTemplate] Template to validate
      # @return [Result] Validation result
      def validate_for_publishing(template)
        errors = []

        errors << "Template must have a name" if template.name.blank?
        errors << "Template must have a description" if template.description.blank?
        errors << "Template must have a workflow definition" if template.workflow_definition.blank?
        errors << "Template must have at least one node" if (template.workflow_definition&.dig("nodes") || []).empty?

        if errors.any?
          Result.failure(error: errors.join(", "))
        else
          Result.success
        end
      end

      # Bump version number
      # @param version [String] Current version
      # @param bump_type [String] Type of bump (major, minor, patch)
      # @return [String] New version
      def bump_version(version, bump_type)
        parts = (version || "1.0.0").split(".").map(&:to_i)
        parts = [ 1, 0, 0 ] if parts.length < 3

        case bump_type.to_s
        when "major"
          parts[0] += 1
          parts[1] = 0
          parts[2] = 0
        when "minor"
          parts[1] += 1
          parts[2] = 0
        else # patch
          parts[2] += 1
        end

        parts.join(".")
      end

      def validate_workflow_ownership!(workflow)
        unless workflow.account_id == account.id
          raise OwnershipError, "Workflow does not belong to this account"
        end
      end

      def validate_template_ownership!(template)
        unless template.account_id == account.id
          raise OwnershipError, "Template does not belong to this account"
        end
      end

      # Result wrapper for service operations
      class Result
        attr_reader :success, :data

        def initialize(success:, data: {})
          @success = success
          @data = data
        end

        def self.success(data = {})
          new(success: true, data: data)
        end

        def self.failure(data = {})
          new(success: false, data: data)
        end

        def success?
          @success
        end

        def failure?
          !@success
        end

        def method_missing(method, *args, &block)
          if data.key?(method)
            data[method]
          else
            super
          end
        end

        def respond_to_missing?(method, include_private = false)
          data.key?(method) || super
        end
      end

      # Custom error class
      class OwnershipError < StandardError; end
    end
  end
end
