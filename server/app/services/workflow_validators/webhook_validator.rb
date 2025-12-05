# frozen_string_literal: true

module WorkflowValidators
  # Validates Webhook nodes
  class WebhookValidator < BaseValidator
    protected

    def validate_node_specific
      validate_required_fields(:url)
      validate_webhook_url
      validate_webhook_method
      validate_timeout
      validate_retry_config
      validate_payload_configuration
    end

    private

    def validate_webhook_url
      return unless node.configuration.present?

      url = node.configuration['url'] || node.configuration[:url]
      return if url.blank?

      unless url =~ URI::DEFAULT_PARSER.make_regexp
        add_issue(
          code: 'invalid_webhook_url',
          severity: 'error',
          category: 'configuration',
          message: "Webhook URL '#{url}' is not valid",
          suggestion: 'Provide a valid HTTP/HTTPS webhook URL'
        )
      end
    end

    def validate_webhook_method
      return unless node.configuration.present?

      method = node.configuration['method'] || node.configuration[:method] || 'POST'
      valid_methods = %w[POST PUT PATCH]

      unless valid_methods.include?(method.upcase)
        add_issue(
          code: 'invalid_webhook_method',
          severity: 'warning',
          category: 'configuration',
          message: "Webhook method '#{method}' is unusual",
          suggestion: "Webhooks typically use POST, PUT, or PATCH methods"
        )
      end
    end

    def validate_payload_configuration
      return unless node.configuration.present?

      payload_template = node.configuration['payload_template'] || node.configuration[:payload_template]
      payload_mapping = node.configuration['payload_mapping'] || node.configuration[:payload_mapping]

      if payload_template.blank? && payload_mapping.blank?
        add_issue(
          code: 'missing_webhook_payload',
          severity: 'info',
          category: 'configuration',
          message: 'No webhook payload configured',
          suggestion: 'Configure payload_template or payload_mapping to send data'
        )
      end
    end
  end
end
