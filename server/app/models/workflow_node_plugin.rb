# frozen_string_literal: true

# Workflow Node Plugin Model
# Specific configuration for workflow node type plugins
class WorkflowNodePlugin < ApplicationRecord
  belongs_to :plugin

  # Validations
  validates :node_type, presence: true
  validates :node_category, presence: true,
            inclusion: { in: %w[data logic integration ai custom] }

  # JSON attributes
  attribute :input_schema, :json, default: -> { {} }
  attribute :output_schema, :json, default: -> { {} }
  attribute :configuration_schema, :json, default: -> { {} }
  attribute :ui_configuration, :json, default: -> { {} }

  # Scopes
  scope :by_category, ->(category) { where(node_category: category) }
  scope :by_type, ->(type) { where(node_type: type) }

  # UI helpers
  def icon
    ui_configuration['icon'] || 'plugin'
  end

  def color
    ui_configuration['color'] || '#6366f1'
  end

  def display_description
    ui_configuration['description'] || plugin.description
  end

  # Schema validation
  def validate_input(input_data)
    return true if input_schema.blank?

    validator = JsonSchemaValidator.new(input_schema)
    validator.valid?(input_data)
  end

  def validate_output(output_data)
    return true if output_schema.blank?

    validator = JsonSchemaValidator.new(output_schema)
    validator.valid?(output_data)
  end

  def validate_configuration(config_data)
    return true if configuration_schema.blank?

    validator = JsonSchemaValidator.new(configuration_schema)
    validator.valid?(config_data)
  end
end
