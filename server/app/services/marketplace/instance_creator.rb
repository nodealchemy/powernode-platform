# frozen_string_literal: true

module Marketplace
  # Service for creating feature instances from subscribed marketplace templates
  #
  # Usage:
  #   creator = Marketplace::InstanceCreator.new(user)
  #   workflow = creator.create_from_workflow_template(template, name: "My Workflow")
  #
  class InstanceCreator
    attr_reader :user, :account

    def initialize(user)
      @user = user
      @account = user.account
    end

    # Create an AI workflow from a workflow template
    def create_from_workflow_template(template, params = {})
      validate_subscription!(template)

      workflow = Ai::Workflow.create!(
        account: account,
        created_by_user: user,
        name: params[:name] || "#{template.name} Instance",
        description: params[:description] || template.description,
        category: template.category,
        workflow_type: "standard",
        variables: merge_variables(template.default_variables, params[:variables]),
        timeout_minutes: template.workflow_definition.dig("settings", "timeout_minutes") || 30,
        retry_on_failure: template.workflow_definition.dig("settings", "retry_on_failure") || false,
        max_retries: template.workflow_definition.dig("settings", "max_retries") || 3,
        is_active: true,
        status: "draft"
      )

      # Create nodes from template definition
      create_workflow_nodes(workflow, template)

      # Create edges from template definition
      create_workflow_edges(workflow, template)

      # Increment template usage count
      template.increment!(:usage_count)

      workflow
    end

    # Create a CI/CD pipeline from a pipeline template
    def create_from_pipeline_template(template, params = {})
      validate_subscription!(template)

      pipeline = CiCd::Pipeline.create!(
        account: account,
        created_by: user,
        name: params[:name] || "#{template.name} Instance",
        description: params[:description] || template.description,
        pipeline_type: template.pipeline_definition["pipeline_type"] || template.category,
        triggers: merge_triggers(template.triggers, params[:triggers]),
        features: template.pipeline_definition["features"] || {},
        runner_labels: template.pipeline_definition["runner_labels"] || [],
        environment_variables: params[:environment_variables] || {},
        timeout_minutes: template.timeout_minutes,
        is_active: true
      )

      # Create steps from template definition
      create_pipeline_steps(pipeline, template)

      # Increment template usage count
      template.increment!(:usage_count)

      pipeline
    end

    # Create an integration instance from an integration template
    def create_from_integration_template(template, params = {})
      validate_subscription!(template)

      instance = Integration::Instance.create!(
        account: account,
        template: template,
        name: params[:name] || "#{template.name} Instance",
        configuration: merge_configuration(template.default_configuration, params[:configuration]),
        status: "inactive",
        metadata: {
          "created_from_template" => template.id,
          "template_version" => template.version
        }
      )

      # Increment template usage count
      template.increment!(:usage_count)

      instance
    end

    private

    def validate_subscription!(template)
      subscription = Marketplace::Subscription.find_by(
        account: account,
        subscribable: template,
        status: "active"
      )

      return if subscription.present?

      # Also check if the template belongs to the account (self-published)
      return if template.respond_to?(:account_id) && template.account_id == account.id

      raise InstanceCreatorError, "You must be subscribed to this template to create instances"
    end

    def merge_variables(default_vars, custom_vars)
      default = default_vars.is_a?(Hash) ? default_vars : {}
      custom = custom_vars.is_a?(Hash) ? custom_vars : {}
      default.deep_merge(custom)
    end

    def merge_triggers(default_triggers, custom_triggers)
      default = default_triggers.is_a?(Hash) ? default_triggers : {}
      custom = custom_triggers.is_a?(Hash) ? custom_triggers : {}
      default.deep_merge(custom)
    end

    def merge_configuration(default_config, custom_config)
      default = default_config.is_a?(Hash) ? default_config : {}
      custom = custom_config.is_a?(Hash) ? custom_config : {}
      default.deep_merge(custom)
    end

    def create_workflow_nodes(workflow, template)
      nodes = template.workflow_definition["nodes"] || []

      nodes.each do |node_def|
        Ai::WorkflowNode.create!(
          workflow: workflow,
          node_id: node_def["node_id"],
          node_type: node_def["node_type"],
          name: node_def["name"],
          position_x: node_def.dig("position", "x") || 0,
          position_y: node_def.dig("position", "y") || 0,
          configuration: node_def["configuration"] || {},
          conditions: node_def["conditions"] || {}
        )
      end
    end

    def create_workflow_edges(workflow, template)
      edges = template.workflow_definition["edges"] || []

      edges.each do |edge_def|
        Ai::WorkflowEdge.create!(
          workflow: workflow,
          edge_id: edge_def["edge_id"],
          source_node_id: edge_def["source_node_id"],
          target_node_id: edge_def["target_node_id"],
          source_handle: edge_def["source_handle"],
          target_handle: edge_def["target_handle"],
          conditions: edge_def["conditions"] || {}
        )
      end
    end

    def create_pipeline_steps(pipeline, template)
      steps = template.pipeline_definition["steps"] || []

      steps.each do |step_def|
        CiCd::PipelineStep.create!(
          pipeline: pipeline,
          name: step_def["name"],
          step_type: step_def["step_type"],
          position: step_def["position"],
          configuration: step_def["configuration"] || {},
          conditions: step_def["conditions"] || {},
          timeout_minutes: step_def["timeout_minutes"] || 10,
          continue_on_error: step_def["continue_on_error"] || false
        )
      end
    end
  end

  class InstanceCreatorError < StandardError; end
end
