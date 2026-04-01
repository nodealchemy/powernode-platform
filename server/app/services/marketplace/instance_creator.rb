# frozen_string_literal: true

module Marketplace
  # Service for creating feature instances from subscribed marketplace templates
  #
  # Usage:
  #   creator = Marketplace::InstanceCreator.new(user)
  #   pipeline = creator.create_from_pipeline_template(template, name: "My Pipeline")
  #
  class InstanceCreator
    attr_reader :user, :account

    def initialize(user)
      @user = user
      @account = user.account
    end

    # Create a CI/CD pipeline from a pipeline template
    def create_from_pipeline_template(template, params = {})
      validate_subscription!(template)

      pipeline = Devops::Pipeline.create!(
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

      instance = Devops::IntegrationInstance.create!(
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

    def create_pipeline_steps(pipeline, template)
      steps = template.pipeline_definition["steps"] || []

      steps.each do |step_def|
        Devops::PipelineStep.create!(
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
