# frozen_string_literal: true

module Ai
  class WorkflowVariable < ApplicationRecord
    self.table_name = "ai_workflow_variables"

    # Associations
    belongs_to :workflow, class_name: "Ai::Workflow", foreign_key: "ai_workflow_id"

    # Validations
    validates :name, presence: true, uniqueness: { scope: :ai_workflow_id },
                     length: { maximum: 100 },
                     format: { with: /\A[a-zA-Z][a-zA-Z0-9_]*\z/, message: "must start with a letter and contain only letters, numbers, and underscores" }
    validates :variable_type, presence: true, inclusion: {
      in: %w[string number boolean object array date datetime file json],
      message: "must be a valid variable type"
    }
    validates :scope, presence: true, inclusion: {
      in: %w[workflow node global],
      message: "must be a valid scope"
    }
    validate :validate_default_value_type
    validate :validate_input_output_consistency
    validate :validate_secret_variable_rules

    # JSON columns
    attribute :default_value, :json
    attribute :validation_rules, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :input_variables, -> { where(is_input: true) }
    scope :output_variables, -> { where(is_output: true) }
    scope :required_variables, -> { where(is_required: true) }
    scope :secret_variables, -> { where(is_secret: true) }
    scope :by_type, ->(type) { where(variable_type: type) }
    scope :by_scope, ->(scope) { where(scope: scope) }
    scope :workflow_scoped, -> { where(scope: "workflow") }
    scope :node_scoped, -> { where(scope: "node") }
    scope :global_scoped, -> { where(scope: "global") }

    # Callbacks
    before_validation :normalize_variable_type
    before_validation :set_default_validation_rules

    # Type check methods
    def string_type?
      variable_type == "string"
    end

    def number_type?
      variable_type == "number"
    end

    def boolean_type?
      variable_type == "boolean"
    end

    def object_type?
      variable_type == "object"
    end

    def array_type?
      variable_type == "array"
    end

    def date_type?
      variable_type == "date"
    end

    def datetime_type?
      variable_type == "datetime"
    end

    def file_type?
      variable_type == "file"
    end

    def json_type?
      variable_type == "json"
    end

    # Variable role methods
    def input_variable?
      is_input?
    end

    def output_variable?
      is_output?
    end

    def required_variable?
      is_required?
    end

    def secret_variable?
      is_secret?
    end

    def optional_variable?
      !is_required?
    end

    # Value validation and conversion
    def validate_value(value)
      errors_found = []

      if is_required? && value.nil?
        errors_found << "#{name} is required but not provided"
        return errors_found
      end

      return errors_found if value.nil? && !is_required?

      case variable_type
      when "string"
        errors_found.concat(validate_string_value(value))
      when "number"
        errors_found.concat(validate_number_value(value))
      when "boolean"
        errors_found.concat(validate_boolean_value(value))
      when "object"
        errors_found.concat(validate_object_value(value))
      when "array"
        errors_found.concat(validate_array_value(value))
      when "date"
        errors_found.concat(validate_date_value(value))
      when "datetime"
        errors_found.concat(validate_datetime_value(value))
      when "file"
        errors_found.concat(validate_file_value(value))
      when "json"
        errors_found.concat(validate_json_value(value))
      end

      errors_found.concat(validate_custom_rules(value))

      errors_found
    end

    def convert_value(value)
      return default_value if value.nil? && !is_required?
      return nil if value.nil?

      case variable_type
      when "string"
        value.to_s
      when "number"
        convert_to_number(value)
      when "boolean"
        convert_to_boolean(value)
      when "object"
        convert_to_object(value)
      when "array"
        convert_to_array(value)
      when "date"
        convert_to_date(value)
      when "datetime"
        convert_to_datetime(value)
      when "json"
        convert_to_json(value)
      else
        value
      end
    end

    def summary
      {
        name: name,
        type: variable_type,
        scope: scope,
        required: is_required?,
        input: is_input?,
        output: is_output?,
        secret: is_secret?,
        default_value: is_secret? ? "[REDACTED]" : default_value,
        description: description,
        validation_rules: validation_rules.except("pattern")
      }
    end

    # Validation rule accessors
    def min_length
      validation_rules["min_length"]
    end

    def max_length
      validation_rules["max_length"]
    end

    def pattern
      validation_rules["pattern"]
    end

    def allowed_values
      validation_rules["allowed_values"]
    end

    def validation_rule_value(rule_name)
      validation_rules[rule_name.to_s]
    end

    def has_validation_rule?(rule_name)
      validation_rules.key?(rule_name.to_s)
    end

    # Example value generation
    def example_value
      return default_value if default_value.present?

      case variable_type
      when "string"
        "example_string"
      when "number"
        42
      when "boolean"
        true
      when "object"
        {}
      when "array"
        []
      when "date"
        Date.current.to_s
      when "datetime"
        Time.current.iso8601
      when "file"
        { "filename" => "example.txt", "content_type" => "text/plain" }
      when "json"
        { "example" => "data" }
      else
        nil
      end
    end

    private

    def normalize_variable_type
      self.variable_type = variable_type&.downcase&.strip
    end

    def set_default_validation_rules
      return unless validation_rules.empty?

      case variable_type
      when "string"
        self.validation_rules = { "max_length" => 1000 }
      when "number"
        self.validation_rules = {}
      when "array"
        self.validation_rules = { "max_items" => 1000 }
      when "object"
        self.validation_rules = { "max_properties" => 100 }
      else
        self.validation_rules = {}
      end
    end

    def validate_default_value_type
      return unless default_value.present?

      validation_errors = validate_value(default_value)
      if validation_errors.any?
        errors.add(:default_value, "is invalid: #{validation_errors.join(', ')}")
      end
    end

    def validate_input_output_consistency
      if is_input? && is_output?
        errors.add(:base, "Variable cannot be both input and output")
      end
    end

    def validate_secret_variable_rules
      if is_secret? && is_output?
        errors.add(:base, "Secret variables cannot be output variables")
      end
    end

    def validate_string_value(value)
      errs = []
      return errs unless value.is_a?(String)

      min = validation_rules["min_length"]
      max = validation_rules["max_length"]
      pattern = validation_rules["pattern"]
      allowed = validation_rules["allowed_values"]
      format = validation_rules["format"]

      errs << "must be at least #{min} characters" if min && value.length < min
      errs << "must be no more than #{max} characters" if max && value.length > max
      errs << "does not match required pattern" if pattern && !value.match?(Regexp.new(pattern))
      errs << "must be one of: #{allowed.join(', ')}" if allowed && !allowed.include?(value)

      # Format validations
      if format == "email" && !value.match?(URI::MailTo::EMAIL_REGEXP)
        errs << "must be a valid email address"
      end

      errs
    end

    def validate_number_value(value)
      return [ "must be a number" ] unless value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+(\.\d+)?\z/)

      errs = []
      numeric_value = value.is_a?(Numeric) ? value : value.to_f
      min = validation_rules["min_value"]
      max = validation_rules["max_value"]

      errs << "must be at least #{min}" if min && numeric_value < min
      errs << "must be no more than #{max}" if max && numeric_value > max

      errs
    end

    def validate_boolean_value(value)
      return [] if [ true, false ].include?(value)
      return [] if %w[true false 1 0].include?(value.to_s.downcase)

      [ "must be a boolean value (true/false)" ]
    end

    def validate_object_value(value)
      return [ "must be an object" ] unless value.is_a?(Hash)

      errs = []
      required = validation_rules["required_properties"]

      if required.is_a?(Array)
        missing = required - value.keys
        errs << "missing required properties: #{missing.join(', ')}" if missing.any?
      end

      errs
    end

    def validate_array_value(value)
      return [ "must be an array" ] unless value.is_a?(Array)

      errs = []
      min = validation_rules["min_items"]
      max = validation_rules["max_items"]

      errs << "must have at least #{min} items" if min && value.size < min
      errs << "must have no more than #{max} items" if max && value.size > max

      errs
    end

    def validate_date_value(value)
      case value
      when Date
        []
      when String
        Date.parse(value) rescue [ "must be a valid date" ]
        []
      else
        [ "must be a date" ]
      end
    end

    def validate_datetime_value(value)
      case value
      when Time, DateTime
        []
      when String
        Time.parse(value) rescue [ "must be a valid datetime" ]
        []
      else
        [ "must be a datetime" ]
      end
    end

    def validate_file_value(value)
      return [ "must be a file object" ] unless value.is_a?(Hash)
      []
    end

    def validate_json_value(value)
      return [] if value.nil?

      begin
        JSON.parse(value.is_a?(String) ? value : value.to_json)
        []
      rescue JSON::ParserError
        [ "must be valid JSON" ]
      end
    end

    def validate_custom_rules(value)
      []
    end

    def convert_to_number(value)
      case value
      when Numeric
        value
      when String
        value.include?(".") ? value.to_f : value.to_i
      else
        value.to_f
      end
    end

    def convert_to_boolean(value)
      case value
      when TrueClass, FalseClass
        value
      when String
        %w[true 1 yes on].include?(value.downcase)
      when Numeric
        value != 0
      else
        false
      end
    end

    def convert_to_object(value)
      case value
      when Hash
        value
      when String
        JSON.parse(value) rescue {}
      else
        {}
      end
    end

    def convert_to_array(value)
      case value
      when Array
        value
      when String
        JSON.parse(value) rescue [ value ]
      else
        Array(value)
      end
    end

    def convert_to_date(value)
      case value
      when Date
        value
      when String
        Date.parse(value)
      else
        Date.current
      end
    rescue ArgumentError
      Date.current
    end

    def convert_to_datetime(value)
      case value
      when Time, DateTime
        value
      when String
        Time.parse(value)
      else
        Time.current
      end
    rescue ArgumentError
      Time.current
    end

    def convert_to_json(value)
      case value
      when String
        JSON.parse(value)
      else
        value
      end
    rescue JSON::ParserError
      value
    end
  end
end
