# frozen_string_literal: true

module Ai::WorkflowValidators
  # Validates API Call / HTTP Request nodes
  class ApiCallValidator < BaseValidator
    protected

    def validate_node_specific
      validate_required_fields(:url, :method)
      validate_url_format
      validate_http_method
      validate_timeout
      validate_retry_config
      validate_auth_configuration
    end

    private

    def validate_url_format
      return unless node.configuration.present?

      url = node.configuration["url"] || node.configuration[:url]
      return if url.blank?

      unless url =~ URI::DEFAULT_PARSER.make_regexp
        add_issue(
          code: "invalid_url",
          severity: "error",
          category: "configuration",
          message: "URL '#{url}' is not valid",
          suggestion: "Provide a valid HTTP/HTTPS URL"
        )
      end
    end

    def validate_http_method
      valid_methods = %w[GET POST PUT PATCH DELETE HEAD OPTIONS]
      validate_field_options(:method, valid_methods)
    end

    def validate_auth_configuration
      return unless node.configuration.present?

      auth_type = node.configuration["auth_type"] || node.configuration[:auth_type]
      return if auth_type.blank?

      case auth_type
      when "bearer"
        validate_field_not_blank(:auth_token)
      when "basic"
        validate_field_not_blank(:username)
        validate_field_not_blank(:password)
      when "api_key"
        validate_field_not_blank(:api_key)
        validate_field_not_blank(:api_key_header)
      end
    end
  end
end
