# frozen_string_literal: true

# JSON Schema Validator - Validates data against JSON schemas for MCP protocol
class JsonSchemaValidator
  include ActiveModel::Model
  include ActiveModel::Attributes

  class ValidationError < StandardError; end

  attr_accessor :schema

  def initialize(schema)
    @schema = schema
    @errors = []
  end

  # Validate data against the schema
  def valid?(data)
    @errors.clear
    validate_recursive(data, @schema, [])
    @errors.empty?
  end

  # Get validation errors
  def errors
    @errors
  end

  # Get detailed error information
  def detailed_errors
    @errors.map do |error|
      {
        path: error[:path].join('.'),
        message: error[:message],
        expected: error[:expected],
        actual: error[:actual]
      }
    end
  end

  private

  def validate_recursive(data, schema, path)
    return true if schema.blank?

    # Handle schema references (simplified)
    if schema.is_a?(String) && schema.start_with?('#/')
      # Would resolve schema references in a full implementation
      return true
    end

    return true unless schema.is_a?(Hash)

    # Validate type
    validate_type(data, schema, path)

    # Validate based on type
    case schema['type']
    when 'object'
      validate_object(data, schema, path)
    when 'array'
      validate_array(data, schema, path)
    when 'string'
      validate_string(data, schema, path)
    when 'number', 'integer'
      validate_number(data, schema, path)
    when 'boolean'
      validate_boolean(data, schema, path)
    when 'null'
      validate_null(data, schema, path)
    end

    # Validate enum
    validate_enum(data, schema, path) if schema['enum']

    # Validate const
    validate_const(data, schema, path) if schema['const']

    # Validate conditional schemas
    validate_conditionals(data, schema, path)
  end

  def validate_type(data, schema, path)
    expected_type = schema['type']
    return unless expected_type

    actual_type = get_json_type(data)

    # Handle multiple types
    if expected_type.is_a?(Array)
      unless expected_type.include?(actual_type)
        add_error(path, "Expected type to be one of #{expected_type.join(', ')}, got #{actual_type}")
      end
    else
      unless actual_type == expected_type
        add_error(path, "Expected type to be #{expected_type}, got #{actual_type}")
      end
    end
  end

  def validate_object(data, schema, path)
    return unless data.is_a?(Hash)

    # Validate required properties
    if schema['required']
      schema['required'].each do |required_prop|
        unless data.key?(required_prop) || data.key?(required_prop.to_sym)
          add_error(path + [required_prop], "Required property missing")
        end
      end
    end

    # Validate properties
    if schema['properties']
      data.each do |key, value|
        key_string = key.to_s
        if schema['properties'][key_string]
          validate_recursive(value, schema['properties'][key_string], path + [key_string])
        elsif !schema['additionalProperties']
          add_error(path + [key_string], "Additional property not allowed")
        elsif schema['additionalProperties'].is_a?(Hash)
          validate_recursive(value, schema['additionalProperties'], path + [key_string])
        end
      end
    end

    # Validate pattern properties
    if schema['patternProperties']
      data.each do |key, value|
        key_string = key.to_s
        schema['patternProperties'].each do |pattern, pattern_schema|
          if key_string.match?(Regexp.new(pattern))
            validate_recursive(value, pattern_schema, path + [key_string])
          end
        end
      end
    end

    # Validate property count
    validate_property_count(data, schema, path)
  end

  def validate_array(data, schema, path)
    return unless data.is_a?(Array)

    # Validate items
    if schema['items']
      if schema['items'].is_a?(Hash)
        # All items must match the same schema
        data.each_with_index do |item, index|
          validate_recursive(item, schema['items'], path + [index.to_s])
        end
      elsif schema['items'].is_a?(Array)
        # Tuple validation - each position has its own schema
        schema['items'].each_with_index do |item_schema, index|
          if data[index]
            validate_recursive(data[index], item_schema, path + [index.to_s])
          end
        end

        # Handle additional items
        if data.size > schema['items'].size
          if schema['additionalItems'] == false
            add_error(path, "Additional items not allowed")
          elsif schema['additionalItems'].is_a?(Hash)
            (schema['items'].size...data.size).each do |index|
              validate_recursive(data[index], schema['additionalItems'], path + [index.to_s])
            end
          end
        end
      end
    end

    # Validate array length
    validate_array_length(data, schema, path)

    # Validate uniqueness
    if schema['uniqueItems'] && data.uniq.size != data.size
      add_error(path, "Array items must be unique")
    end
  end

  def validate_string(data, schema, path)
    return unless data.is_a?(String)

    # Validate length
    if schema['minLength'] && data.length < schema['minLength']
      add_error(path, "String length #{data.length} is less than minimum #{schema['minLength']}")
    end

    if schema['maxLength'] && data.length > schema['maxLength']
      add_error(path, "String length #{data.length} is greater than maximum #{schema['maxLength']}")
    end

    # Validate pattern
    if schema['pattern'] && !data.match?(Regexp.new(schema['pattern']))
      add_error(path, "String does not match pattern #{schema['pattern']}")
    end

    # Validate format
    validate_string_format(data, schema, path) if schema['format']
  end

  def validate_number(data, schema, path)
    return unless data.is_a?(Numeric)

    # Validate type specifics
    if schema['type'] == 'integer' && !data.is_a?(Integer)
      add_error(path, "Expected integer, got #{data.class.name.downcase}")
    end

    # Validate range
    if schema['minimum']
      exclusive = schema['exclusiveMinimum']
      if exclusive ? data <= schema['minimum'] : data < schema['minimum']
        operator = exclusive ? '<=' : '<'
        add_error(path, "Number #{data} is #{operator} minimum #{schema['minimum']}")
      end
    end

    if schema['maximum']
      exclusive = schema['exclusiveMaximum']
      if exclusive ? data >= schema['maximum'] : data > schema['maximum']
        operator = exclusive ? '>=' : '>'
        add_error(path, "Number #{data} is #{operator} maximum #{schema['maximum']}")
      end
    end

    # Validate multiple of
    if schema['multipleOf'] && (data % schema['multipleOf']) != 0
      add_error(path, "Number #{data} is not a multiple of #{schema['multipleOf']}")
    end
  end

  def validate_boolean(data, schema, path)
    unless data.is_a?(TrueClass) || data.is_a?(FalseClass)
      add_error(path, "Expected boolean, got #{get_json_type(data)}")
    end
  end

  def validate_null(data, schema, path)
    unless data.nil?
      add_error(path, "Expected null, got #{get_json_type(data)}")
    end
  end

  def validate_enum(data, schema, path)
    unless schema['enum'].include?(data)
      add_error(path, "Value must be one of #{schema['enum'].inspect}, got #{data.inspect}")
    end
  end

  def validate_const(data, schema, path)
    unless data == schema['const']
      add_error(path, "Value must be #{schema['const'].inspect}, got #{data.inspect}")
    end
  end

  def validate_conditionals(data, schema, path)
    # Validate if/then/else
    if schema['if']
      temp_validator = JsonSchemaValidator.new(schema['if'])
      if temp_validator.valid?(data)
        # If condition is true, validate against 'then' schema
        if schema['then']
          validate_recursive(data, schema['then'], path)
        end
      else
        # If condition is false, validate against 'else' schema
        if schema['else']
          validate_recursive(data, schema['else'], path)
        end
      end
    end

    # Validate allOf
    if schema['allOf']
      schema['allOf'].each do |sub_schema|
        validate_recursive(data, sub_schema, path)
      end
    end

    # Validate anyOf
    if schema['anyOf']
      valid_schemas = schema['anyOf'].count do |sub_schema|
        temp_validator = JsonSchemaValidator.new(sub_schema)
        temp_validator.valid?(data)
      end

      if valid_schemas == 0
        add_error(path, "Data does not match any of the anyOf schemas")
      end
    end

    # Validate oneOf
    if schema['oneOf']
      valid_schemas = schema['oneOf'].count do |sub_schema|
        temp_validator = JsonSchemaValidator.new(sub_schema)
        temp_validator.valid?(data)
      end

      if valid_schemas != 1
        add_error(path, "Data must match exactly one of the oneOf schemas, matched #{valid_schemas}")
      end
    end

    # Validate not
    if schema['not']
      temp_validator = JsonSchemaValidator.new(schema['not'])
      if temp_validator.valid?(data)
        add_error(path, "Data must not match the 'not' schema")
      end
    end
  end

  def validate_property_count(data, schema, path)
    property_count = data.size

    if schema['minProperties'] && property_count < schema['minProperties']
      add_error(path, "Object has #{property_count} properties, minimum is #{schema['minProperties']}")
    end

    if schema['maxProperties'] && property_count > schema['maxProperties']
      add_error(path, "Object has #{property_count} properties, maximum is #{schema['maxProperties']}")
    end
  end

  def validate_array_length(data, schema, path)
    array_length = data.size

    if schema['minItems'] && array_length < schema['minItems']
      add_error(path, "Array has #{array_length} items, minimum is #{schema['minItems']}")
    end

    if schema['maxItems'] && array_length > schema['maxItems']
      add_error(path, "Array has #{array_length} items, maximum is #{schema['maxItems']}")
    end
  end

  def validate_string_format(data, schema, path)
    format = schema['format']

    case format
    when 'email'
      unless data.match?(/\A[^@\s]+@[^@\s]+\z/)
        add_error(path, "String is not a valid email format")
      end
    when 'uri'
      begin
        URI.parse(data)
      rescue URI::InvalidURIError
        add_error(path, "String is not a valid URI format")
      end
    when 'date'
      begin
        Date.parse(data)
      rescue ArgumentError
        add_error(path, "String is not a valid date format")
      end
    when 'date-time'
      begin
        DateTime.parse(data)
      rescue ArgumentError
        add_error(path, "String is not a valid date-time format")
      end
    when 'uuid'
      unless data.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        add_error(path, "String is not a valid UUID format")
      end
    when 'ipv4'
      unless data.match?(/\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z/)
        add_error(path, "String is not a valid IPv4 format")
      end
    when 'ipv6'
      # Simplified IPv6 validation
      unless data.match?(/:/)
        add_error(path, "String is not a valid IPv6 format")
      end
    end
  end

  def get_json_type(data)
    case data
    when Hash
      'object'
    when Array
      'array'
    when String
      'string'
    when Integer, Float
      data.is_a?(Integer) ? 'integer' : 'number'
    when TrueClass, FalseClass
      'boolean'
    when NilClass
      'null'
    else
      'unknown'
    end
  end

  def add_error(path, message)
    @errors << {
      path: path,
      message: message,
      expected: nil,
      actual: nil
    }
  end
end