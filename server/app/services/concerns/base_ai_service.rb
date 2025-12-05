# frozen_string_literal: true

# BaseAiService - Core abstraction for all AI-related services
#
# Provides common functionality for AI services including:
# - Error handling and recovery
# - Monitoring and telemetry
# - Logging and debugging
# - Cost tracking
#
# Usage:
#   class MyAiService
#     include BaseAiService
#
#     def execute
#       with_monitoring('operation_name') do
#         # Your service logic here
#       end
#     end
#   end
#
module BaseAiService
  extend ActiveSupport::Concern

  included do
    include ActiveModel::Model
    include ActiveModel::Attributes

    attr_accessor :account, :user
    attr_reader :logger, :telemetry

    class ServiceError < StandardError; end
    class ValidationError < ServiceError; end
    class ExecutionError < ServiceError; end
  end

  # =============================================================================
  # INITIALIZATION
  # =============================================================================

  def initialize(account: nil, user: nil, **options)
    @account = account
    @user = user
    @logger = Rails.logger
    @telemetry = initialize_telemetry
    @options = options
  end

  # =============================================================================
  # MONITORING & TELEMETRY
  # =============================================================================

  # Execute block with comprehensive monitoring
  #
  # @param operation_name [String] Name of the operation for tracking
  # @param metadata [Hash] Additional metadata to track
  # @yield Block to execute with monitoring
  # @return Result of the block execution
  def with_monitoring(operation_name, metadata = {})
    start_time = Time.current

    log_operation_start(operation_name, metadata)

    result = nil
    error = nil

    begin
      result = yield

      record_success_metrics(operation_name, start_time, result, metadata)
      result

    rescue StandardError => e
      error = e
      record_error_metrics(operation_name, start_time, e, metadata)
      handle_service_error(e, operation_name, metadata)
      raise
    ensure
      log_operation_complete(operation_name, start_time, error, metadata)
    end
  end

  # =============================================================================
  # ERROR HANDLING
  # =============================================================================

  # Handle service errors with contextual information
  #
  # @param error [StandardError] The error that occurred
  # @param operation [String] Operation name
  # @param context [Hash] Additional context
  def handle_service_error(error, operation, context = {})
    error_details = {
      service: self.class.name,
      operation: operation,
      error_class: error.class.name,
      error_message: error.message,
      account_id: @account&.id,
      user_id: @user&.id,
      context: context,
      backtrace: error.backtrace&.first(10)
    }

    @logger.error "[#{self.class.name}] Error in #{operation}: #{error.message}"
    @logger.debug "[#{self.class.name}] Error details: #{error_details.to_json}"

    # Record error for monitoring
    record_error_event(error_details)

    # Trigger alerts if needed
    trigger_error_alerts(error, operation, context) if should_alert?(error, operation)
  end

  # Validate required parameters
  #
  # @param params [Hash] Parameters to validate
  # @param required [Array<Symbol>] Required parameter keys
  # @raise [ValidationError] if validation fails
  def validate_params!(params, *required)
    missing = required.select { |key| params[key].blank? }

    if missing.any?
      raise ValidationError, "Missing required parameters: #{missing.join(', ')}"
    end
  end

  # =============================================================================
  # COST TRACKING
  # =============================================================================

  # Track operation cost
  #
  # @param operation [String] Operation name
  # @param cost [Float] Cost in USD
  # @param metadata [Hash] Additional cost metadata
  def track_cost(operation, cost, metadata = {})
    return unless cost.present? && cost > 0

    cost_data = {
      service: self.class.name,
      operation: operation,
      cost_usd: cost,
      account_id: @account&.id,
      user_id: @user&.id,
      timestamp: Time.current,
      metadata: metadata
    }

    record_cost_metric(cost_data)
  end

  # =============================================================================
  # LOGGING HELPERS
  # =============================================================================

  def log_info(message, data = {})
    @logger.info "[#{self.class.name}] #{message} #{format_log_data(data)}"
  end

  def log_warn(message, data = {})
    @logger.warn "[#{self.class.name}] #{message} #{format_log_data(data)}"
  end

  def log_error(message, data = {})
    @logger.error "[#{self.class.name}] #{message} #{format_log_data(data)}"
  end

  def log_debug(message, data = {})
    @logger.debug "[#{self.class.name}] #{message} #{format_log_data(data)}"
  end

  private

  # =============================================================================
  # INITIALIZATION HELPERS
  # =============================================================================

  def initialize_telemetry
    McpTelemetryService.new(
      service_name: self.class.name,
      account: @account
    )
  end

  # =============================================================================
  # METRICS RECORDING
  # =============================================================================

  def record_success_metrics(operation, start_time, result, metadata)
    duration_ms = ((Time.current - start_time) * 1000).round

    @telemetry.record_metric(
      metric_type: 'operation.success',
      metric_name: operation,
      value: duration_ms,
      metadata: {
        service: self.class.name,
        duration_ms: duration_ms,
        account_id: @account&.id,
        **metadata
      }
    )
  end

  def record_error_metrics(operation, start_time, error, metadata)
    duration_ms = ((Time.current - start_time) * 1000).round

    @telemetry.record_metric(
      metric_type: 'operation.error',
      metric_name: operation,
      value: 1,
      metadata: {
        service: self.class.name,
        duration_ms: duration_ms,
        error_class: error.class.name,
        error_message: error.message,
        account_id: @account&.id,
        **metadata
      }
    )
  end

  def record_cost_metric(cost_data)
    @telemetry.record_metric(
      metric_type: 'cost.incurred',
      metric_name: cost_data[:operation],
      value: cost_data[:cost_usd],
      metadata: cost_data
    )
  end

  def record_error_event(error_details)
    @telemetry.record_event(
      event_type: 'service.error',
      event_data: error_details
    )
  end

  # =============================================================================
  # LOGGING HELPERS
  # =============================================================================

  def log_operation_start(operation, metadata)
    log_info "Starting #{operation}", metadata
  end

  def log_operation_complete(operation, start_time, error, metadata)
    duration_ms = ((Time.current - start_time) * 1000).round
    status = error ? 'failed' : 'completed'

    log_info "#{operation.capitalize} #{status}", {
      duration_ms: duration_ms,
      **metadata
    }
  end

  def format_log_data(data)
    return '' if data.empty?

    "| #{data.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end

  # =============================================================================
  # ALERT HELPERS
  # =============================================================================

  def should_alert?(error, operation)
    # Alert on critical errors or specific operation failures
    error.is_a?(ExecutionError) ||
      critical_operations.include?(operation) ||
      @options[:alert_on_error]
  end

  def critical_operations
    %w[
      workflow_execution
      agent_execution
      provider_request
      payment_processing
    ]
  end

  def trigger_error_alerts(error, operation, context)
    alerting_service.ai_execution_error(error, operation, context)
  rescue StandardError => e
    # Don't let alerting failures propagate
    log_error "Failed to send alert", { alert_error: e.message, original_error: error.message }
  end

  def alerting_service
    @alerting_service ||= AlertingService.new
  end
end
