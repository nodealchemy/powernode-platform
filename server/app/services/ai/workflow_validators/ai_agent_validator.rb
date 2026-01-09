# frozen_string_literal: true

module Ai::WorkflowValidators
  # Validates AI Agent nodes
  class AiAgentValidator < BaseValidator
    protected

    def validate_node_specific
      validate_required_fields(:agent_id)
      validate_agent_exists
      validate_prompt_configuration
      validate_timeout
      validate_retry_config
    end

    private

    def validate_agent_exists
      return unless node.configuration.present?

      agent_id = node.configuration["agent_id"] || node.configuration[:agent_id]
      return if agent_id.blank?

      unless Ai::Agent.exists?(agent_id)
        add_issue(
          code: "agent_not_found",
          severity: "error",
          category: "configuration",
          message: "AI Agent with ID '#{agent_id}' does not exist",
          suggestion: "Select a valid AI agent or create a new one"
        )
      end
    end

    def validate_prompt_configuration
      return unless node.configuration.present?

      prompt = node.configuration["prompt"] || node.configuration[:prompt]
      system_prompt = node.configuration["system_prompt"] || node.configuration[:system_prompt]

      if prompt.blank? && system_prompt.blank?
        add_issue(
          code: "missing_prompt",
          severity: "warning",
          category: "configuration",
          message: "No prompt or system prompt configured",
          suggestion: "Provide at least a prompt or system prompt for the AI agent"
        )
      end
    end
  end
end
