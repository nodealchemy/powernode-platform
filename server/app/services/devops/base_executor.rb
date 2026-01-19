# frozen_string_literal: true

module Devops
  class BaseExecutor
    attr_reader :instance, :execution, :context

    # Error classes for executor operations
    class ExecutionError < StandardError; end
    class ConfigurationError < StandardError; end
    class CredentialError < StandardError; end
    class TimeoutError < StandardError; end
    class RateLimitError < StandardError; end

    def initialize(instance:, execution: nil, context: {})
      @instance = instance
      @execution = execution
      @context = context
      @start_time = nil
      @metrics = {}
    end

    # Main execution entry point - subclasses should not override this
    def execute(input = {})
      @start_time = Time.current

      validate_configuration!
      validate_credentials!

      result = perform_execution(input)

      record_success(result)
      result
    rescue ExecutionError, ConfigurationError, CredentialError, TimeoutError, RateLimitError => e
      record_failure(e)
      raise
    rescue StandardError => e
      record_failure(e)
      raise ExecutionError, "Unexpected error: #{e.message}"
    end

    # Subclasses must implement this method
    def perform_execution(_input)
      raise NotImplementedError, "#{self.class.name} must implement #perform_execution"
    end

    # Test connection without full execution
    def test_connection
      validate_configuration!
      validate_credentials!

      perform_connection_test
    rescue StandardError => e
      { success: false, error: e.message }
    end

    # Subclasses should implement this for connection testing
    def perform_connection_test
      { success: true, message: "Connection test not implemented" }
    end

    # Get health status of the integration
    def health_check
      {
        status: determine_health_status,
        last_execution: instance.last_executed_at,
        success_rate: calculate_success_rate,
        avg_response_time: calculate_avg_response_time,
        checked_at: Time.current
      }
    end

    protected

    # Configuration accessors
    def configuration
      @configuration ||= instance.configuration.with_indifferent_access
    end

    def template
      @template ||= instance.integration_template
    end

    def template_configuration
      @template_configuration ||= template.default_configuration.with_indifferent_access
    end

    # Merged configuration (template defaults + instance overrides)
    def effective_configuration
      @effective_configuration ||= template_configuration.deep_merge(configuration)
    end

    # Credential accessors
    def credential
      @credential ||= instance.integration_credential
    end

    def decrypted_credentials
      return {} unless credential.present?

      @decrypted_credentials ||= Devops::CredentialEncryptionService.decrypt(credential)
    end

    # Validation methods
    def validate_configuration!
      return if configuration_valid?

      raise ConfigurationError, configuration_errors.join(", ")
    end

    def configuration_valid?
      configuration_errors.empty?
    end

    def configuration_errors
      errors = []

      required_fields = template.configuration_schema["required"] || []
      required_fields.each do |field|
        errors << "Missing required configuration: #{field}" unless effective_configuration[field].present?
      end

      errors
    end

    def validate_credentials!
      return unless template.credential_requirements.present?
      return if credentials_valid?

      raise CredentialError, credential_errors.join(", ")
    end

    def credentials_valid?
      credential_errors.empty?
    end

    def credential_errors
      errors = []

      return ["No credentials configured"] unless credential.present?

      required_fields = template.credential_requirements["required"] || []
      required_fields.each do |field|
        errors << "Missing required credential: #{field}" unless decrypted_credentials[field].present?
      end

      errors
    end

    # HTTP client helpers
    def http_client
      @http_client ||= build_http_client
    end

    def build_http_client
      HTTP.timeout(connect: connect_timeout, read: read_timeout)
          .headers(default_headers)
    end

    def connect_timeout
      effective_configuration.fetch(:connect_timeout, 10)
    end

    def read_timeout
      effective_configuration.fetch(:read_timeout, 30)
    end

    def default_headers
      {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "User-Agent" => "Powernode-Integration/1.0"
      }
    end

    # Retry logic
    def with_retry(max_attempts: 3, backoff_base: 2)
      attempts = 0

      begin
        attempts += 1
        yield
      rescue StandardError => e
        if attempts < max_attempts && retryable_error?(e)
          sleep(backoff_base ** attempts)
          retry
        end
        raise
      end
    end

    def retryable_error?(error)
      case error
      when TimeoutError, RateLimitError
        true
      when ExecutionError
        error.message.include?("timeout") || error.message.include?("connection")
      else
        false
      end
    end

    # Execution recording
    def record_success(result)
      return unless execution.present?

      execution_time = Time.current - @start_time

      execution.update!(
        status: "completed",
        completed_at: Time.current,
        execution_time_ms: (execution_time * 1000).round,
        output_data: sanitize_output(result),
        response_code: result[:status_code],
        response_size_bytes: result.to_json.bytesize
      )

      update_instance_metrics(success: true, execution_time: execution_time)
    end

    def record_failure(error)
      return unless execution.present?

      execution_time = @start_time ? Time.current - @start_time : 0

      execution.update!(
        status: "failed",
        completed_at: Time.current,
        execution_time_ms: (execution_time * 1000).round,
        error_message: error.message,
        error_class: error.class.name
      )

      update_instance_metrics(success: false, execution_time: execution_time)
    end

    def update_instance_metrics(success:, execution_time:)
      instance.increment!(:execution_count)

      if success
        instance.increment!(:success_count)
      else
        instance.increment!(:failure_count)
      end

      # Update health metrics
      metrics = instance.health_metrics || {}
      metrics["last_execution_time_ms"] = (execution_time * 1000).round
      metrics["last_execution_at"] = Time.current.iso8601
      metrics["last_execution_success"] = success

      instance.update!(
        health_metrics: metrics,
        last_executed_at: Time.current
      )
    end

    def sanitize_output(result)
      # Remove sensitive data from output
      result.except(:credentials, :tokens, :secrets, :api_key)
    end

    # Health calculation helpers
    def determine_health_status
      return "unknown" if instance.execution_count.zero?

      success_rate = calculate_success_rate
      if success_rate >= 0.95
        "healthy"
      elsif success_rate >= 0.80
        "degraded"
      else
        "unhealthy"
      end
    end

    def calculate_success_rate
      return 0.0 if instance.execution_count.zero?

      (instance.success_count.to_f / instance.execution_count).round(4)
    end

    def calculate_avg_response_time
      recent_executions = Devops::IntegrationExecution
        .where(devops_integration_instance_id: instance.id)
        .where(status: "completed")
        .order(created_at: :desc)
        .limit(100)

      return nil if recent_executions.empty?

      recent_executions.average(:execution_time_ms)&.round(2)
    end

    # Logging helpers
    def log_info(message, **metadata)
      Rails.logger.info("[Integration:#{instance.id}] #{message}", **metadata)
    end

    def log_error(message, **metadata)
      Rails.logger.error("[Integration:#{instance.id}] #{message}", **metadata)
    end

    def log_debug(message, **metadata)
      Rails.logger.debug("[Integration:#{instance.id}] #{message}", **metadata)
    end
  end
end
