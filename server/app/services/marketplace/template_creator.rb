# frozen_string_literal: true

module Marketplace
  # Service for creating marketplace templates from existing features
  #
  # Usage:
  #   creator = Marketplace::TemplateCreator.new(user)
  #   template = creator.create_from_workflow(workflow, name: "My Template", description: "...")
  #
  class TemplateCreator
    attr_reader :user, :account

    def initialize(user)
      @user = user
      @account = user.account
    end

    # Create a workflow template from an existing AI workflow
    def create_from_workflow(workflow, params = {})
      validate_ownership!(workflow)

      Ai::WorkflowTemplate.create!(
        account: account,
        created_by_user: user,
        source_workflow: workflow,
        name: params[:name] || "#{workflow.name} Template",
        description: params[:description] || workflow.description,
        category: params[:category] || workflow.category || "custom",
        difficulty_level: params[:difficulty_level] || "intermediate",
        workflow_definition: extract_workflow_definition(workflow),
        default_variables: params[:default_variables] || workflow.variables || {},
        tags: params[:tags] || [],
        version: "1.0.0",
        is_public: false,
        is_featured: false
      )
    end

    # Create a pipeline template from an existing CI/CD pipeline
    def create_from_pipeline(pipeline, params = {})
      validate_ownership!(pipeline)

      Devops::PipelineTemplate.create!(
        account: account,
        created_by_user: user,
        source_pipeline: pipeline,
        name: params[:name] || "#{pipeline.name} Template",
        description: params[:description] || pipeline.description,
        category: params[:category] || pipeline.pipeline_type,
        difficulty_level: params[:difficulty_level] || "intermediate",
        pipeline_definition: extract_pipeline_definition(pipeline),
        default_variables: params[:default_variables] || {},
        triggers: pipeline.triggers || {},
        timeout_minutes: pipeline.timeout_minutes,
        tags: params[:tags] || [],
        version: "1.0.0",
        is_public: false,
        is_featured: false
      )
    end

    # Create an integration template from an existing integration template
    # (For duplicating/customizing existing templates)
    def create_from_integration(integration_template, params = {})
      validate_ownership!(integration_template) if integration_template.account_id.present?

      Devops::IntegrationTemplate.create!(
        account: account,
        name: params[:name] || "#{integration_template.name} Copy",
        slug: nil, # Will be auto-generated
        description: params[:description] || integration_template.description,
        integration_type: integration_template.integration_type,
        category: params[:category] || integration_template.category,
        configuration_schema: integration_template.configuration_schema,
        credential_requirements: integration_template.credential_requirements,
        capabilities: integration_template.capabilities,
        input_schema: integration_template.input_schema,
        output_schema: integration_template.output_schema,
        default_configuration: integration_template.default_configuration,
        metadata: params[:metadata] || {},
        version: "1.0.0",
        is_public: false,
        is_active: true
      )
    end

    # Create a prompt template from an existing prompt template
    # (For duplicating/customizing existing templates)
    def create_from_prompt(prompt_template, params = {})
      validate_ownership!(prompt_template)

      Shared::PromptTemplate.create!(
        account: account,
        created_by: user,
        name: params[:name] || "#{prompt_template.name} Copy",
        slug: nil, # Will be auto-generated
        description: params[:description] || prompt_template.description,
        content: params[:content] || prompt_template.content,
        category: params[:category] || prompt_template.category,
        domain: params[:domain] || prompt_template.domain,
        variables: prompt_template.variables,
        metadata: params[:metadata] || {},
        version: 1,
        is_active: true,
        is_system: false
      )
    end

    private

    def validate_ownership!(resource)
      return if resource.account_id == account.id
      raise TemplateCreatorError, "You can only create templates from your own resources"
    end

    def extract_workflow_definition(workflow)
      {
        "nodes" => workflow.nodes.order(:position).map do |node|
          {
            "node_id" => node.node_id,
            "node_type" => node.node_type,
            "name" => node.name,
            "position" => { "x" => node.position_x, "y" => node.position_y },
            "configuration" => sanitize_configuration(node.configuration),
            "conditions" => node.conditions
          }
        end,
        "edges" => workflow.edges.map do |edge|
          {
            "edge_id" => edge.edge_id,
            "source_node_id" => edge.source_node_id,
            "target_node_id" => edge.target_node_id,
            "source_handle" => edge.source_handle,
            "target_handle" => edge.target_handle,
            "conditions" => edge.conditions
          }
        end,
        "variables" => workflow.variables || [],
        "settings" => {
          "timeout_minutes" => workflow.timeout_minutes,
          "retry_on_failure" => workflow.retry_on_failure,
          "max_retries" => workflow.max_retries
        }
      }
    end

    def extract_pipeline_definition(pipeline)
      {
        "pipeline_type" => pipeline.pipeline_type,
        "steps" => pipeline.steps.order(:position).map do |step|
          {
            "name" => step.name,
            "step_type" => step.step_type,
            "position" => step.position,
            "configuration" => sanitize_configuration(step.configuration),
            "conditions" => step.conditions,
            "timeout_minutes" => step.timeout_minutes,
            "continue_on_error" => step.continue_on_error
          }
        end,
        "features" => pipeline.features || {},
        "runner_labels" => pipeline.runner_labels || [],
        "environment_variables" => sanitize_environment_variables(pipeline.environment_variables)
      }
    end

    # Remove sensitive data from configuration
    def sanitize_configuration(config)
      return {} unless config.is_a?(Hash)

      config.deep_dup.tap do |sanitized|
        # Remove common sensitive keys
        %w[api_key secret token password credentials auth_token].each do |key|
          sanitized.delete(key)
          sanitized.delete(key.to_sym)
        end
      end
    end

    # Remove values from environment variables (keep keys as placeholders)
    def sanitize_environment_variables(env_vars)
      return {} unless env_vars.is_a?(Hash)

      env_vars.transform_values { |_| "{{PLACEHOLDER}}" }
    end
  end

  class TemplateCreatorError < StandardError; end
end
