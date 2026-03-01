# frozen_string_literal: true

module Devops
  # Individual step configuration within a pipeline
  # Defines step type, inputs, outputs, and execution conditions
  class PipelineStep < ApplicationRecord
    self.table_name = "devops_pipeline_steps"

    STEP_TYPES = %w[
      checkout
      claude_execute
      ai_workflow
      post_comment
      create_pr
      create_branch
      upload_artifact
      download_artifact
      run_tests
      deploy
      notify
      custom
      code_factory_gate
    ].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :pipeline, class_name: "Devops::Pipeline", foreign_key: :devops_pipeline_id
    belongs_to :shared_prompt_template, class_name: "Shared::PromptTemplate", optional: true

    has_many :executions, class_name: "Devops::StepExecution", foreign_key: :devops_pipeline_step_id, dependent: :destroy

    # Alias for backward compatibility during transition
    alias_method :prompt_template, :shared_prompt_template

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true, uniqueness: { scope: :devops_pipeline_id }
    validates :step_type, presence: true, inclusion: { in: ->(record) { STEP_TYPES + Devops::StepHandlerRegistry.all_types } }
    validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

    validate :prompt_template_required_for_claude_execute

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(is_active: true) }
    scope :ordered, -> { order(position: :asc) }
    scope :by_type, ->(type) { where(step_type: type) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :set_default_position, on: :create

    # ============================================
    # Instance Methods
    # ============================================

    def execute(context)
      handler_class.new(self, context).execute
    end

    def handler_class
      # Check dynamic registry first (extension-provided step types)
      registered = Devops::StepHandlerRegistry.handler_for(step_type)
      return registered if registered

      # Fall back to core handler lookup
      "Devops::StepHandlers::#{step_type.camelize}Handler".constantize
    rescue NameError
      Devops::StepHandlers::CustomHandler
    end

    def should_run?(previous_step_outputs)
      return true if condition.blank?

      evaluator = Devops::ConditionEvaluator.new(condition, previous_step_outputs)
      evaluator.evaluate
    rescue StandardError => e
      Rails.logger.error("Condition evaluation failed for step #{name}: #{e.message}")
      false
    end

    def input_value(key, context = {})
      return nil unless inputs.key?(key.to_s)

      input_def = inputs[key.to_s]

      if input_def.is_a?(String) && input_def.start_with?("${{")
        # Expression reference: ${{ steps.previous.outputs.result }}
        resolve_expression(input_def, context)
      else
        input_def
      end
    end

    def resolve_expression(expression, context)
      # Parse expressions like ${{ steps.review.outputs.approved }}
      match = expression.match(/\$\{\{\s*(.+?)\s*\}\}/)
      return expression unless match

      path = match[1].split(".")
      context.dig(*path)
    end

    def output_definitions
      return [] if outputs.blank?

      # Handle both array format [{name: ..., type: ...}] and hash format {name: type}
      if outputs.is_a?(Array)
        outputs.map do |output|
          if output.is_a?(Hash) && output["name"]
            {
              name: output["name"],
              description: output["description"],
              type: output["type"] || "string"
            }
          else
            { name: output.to_s, type: "string" }
          end
        end
      elsif outputs.is_a?(Hash)
        outputs.map do |name, type|
          {
            name: name.to_s,
            description: nil,
            type: type.to_s
          }
        end
      else
        []
      end
    end

    def claude_execute?
      step_type == "claude_execute"
    end

    def requires_prompt?
      %w[claude_execute post_comment].include?(step_type)
    end

    # ============================================
    # Approval Configuration Methods
    # ============================================

    def requires_approval?
      requires_approval == true
    end

    # Get resolved list of recipients for approval notifications
    # Merges step-level overrides with pipeline defaults
    def approval_recipients
      # First check step-level overrides
      step_recipients = approval_settings["notification_recipients"]
      return step_recipients if step_recipients.present?

      # Fall back to pipeline-level recipients
      pipeline.resolved_notification_recipients
    end

    # Get approval timeout in hours
    def approval_timeout_hours
      approval_settings["timeout_hours"] || 24
    end

    # Check if comment is required for approval/rejection
    def approval_requires_comment?
      approval_settings["require_comment"] == true
    end

    private

    def set_default_position
      return if position.present?

      max_position = pipeline.pipeline_steps.maximum(:position) || -1
      self.position = max_position + 1
    end

    def prompt_template_required_for_claude_execute
      return unless claude_execute? && shared_prompt_template.blank?

      errors.add(:shared_prompt_template, "is required for claude_execute steps")
    end
  end
end
