# frozen_string_literal: true

# MCP Telemetry Service - Comprehensive monitoring and analytics for MCP protocol operations
class McpTelemetryService
  include ActiveModel::Model

  attr_accessor :account

  def initialize(account: nil, service_name: nil)
    @account = account
    @service_name = service_name
    @logger = Rails.logger
    @metrics = {}
    @connection_metrics = {}
    @tool_metrics = {}
    @performance_data = {}

    # Initialize metrics storage
    initialize_metrics_storage
  end

  # Record a metric - used by BaseAiService
  #
  # @param metric_type [String] Type of metric (e.g., 'operation.success', 'operation.error')
  # @param metric_name [String] Name of the metric/operation
  # @param value [Numeric] Metric value
  # @param metadata [Hash] Additional metadata
  def record_metric(metric_type: nil, metric_name: nil, value: nil, metadata: {})
    persist_metric(metric_type, {
      name: metric_name,
      value: value,
      account_id: @account&.id,
      service_name: @service_name,
      timestamp: Time.current,
      **metadata
    })
  end

  # Record an event - used by BaseAiService
  #
  # @param event_type [String] Type of event
  # @param event_data [Hash] Event data
  def record_event(event_type:, event_data: {})
    persist_metric(event_type, {
      account_id: @account&.id,
      service_name: @service_name,
      timestamp: Time.current,
      **event_data
    })
  end

  # =============================================================================
  # CONNECTION TELEMETRY
  # =============================================================================

  # Track connection initialization
  def track_connection_init(connection_id, client_info)
    @logger.debug "[MCP_TELEMETRY] Tracking connection init: #{connection_id}"

    @connection_metrics[connection_id] = {
      connection_id: connection_id,
      account_id: @account&.id,
      client_info: client_info,
      initialized_at: Time.current,
      total_messages: 0,
      total_errors: 0,
      total_tool_calls: 0,
      last_activity: Time.current
    }

    # Update global metrics
    increment_metric("connections.total")
    increment_metric("connections.active")

    persist_metric("connection_init", {
      connection_id: connection_id,
      account_id: @account&.id,
      timestamp: Time.current
    })
  end

  # Track connection termination
  def track_connection_end(connection_id)
    @logger.debug "[MCP_TELEMETRY] Tracking connection end: #{connection_id}"

    connection_data = @connection_metrics[connection_id]
    return unless connection_data

    # Calculate session duration
    session_duration = Time.current - connection_data[:initialized_at]

    # Update connection metrics
    connection_data[:ended_at] = Time.current
    connection_data[:session_duration] = session_duration

    # Update global metrics
    decrement_metric("connections.active")
    record_histogram("connection.session_duration", session_duration)

    persist_metric("connection_end", {
      connection_id: connection_id,
      session_duration: session_duration,
      total_messages: connection_data[:total_messages],
      total_errors: connection_data[:total_errors],
      timestamp: Time.current
    })
  end

  # =============================================================================
  # TOOL EXECUTION TELEMETRY
  # =============================================================================

  # Track tool registration
  def track_tool_registration(tool_id, tool_manifest)
    @logger.debug "[MCP_TELEMETRY] Tracking tool registration: #{tool_id}"

    @tool_metrics[tool_id] = {
      tool_id: tool_id,
      name: tool_manifest["name"],
      type: tool_manifest["type"],
      version: tool_manifest["version"],
      account_id: @account&.id,
      registered_at: Time.current,
      total_invocations: 0,
      successful_invocations: 0,
      failed_invocations: 0,
      total_execution_time: 0,
      average_execution_time: 0,
      last_invocation: nil
    }

    # Update global metrics
    increment_metric("tools.total")
    increment_metric("tools.by_type.#{tool_manifest['type']}")

    persist_metric("tool_registration", {
      tool_id: tool_id,
      tool_name: tool_manifest["name"],
      tool_type: tool_manifest["type"],
      account_id: @account&.id,
      timestamp: Time.current
    })
  end

  # Track tool invocation start
  def track_tool_invocation_start(execution_id, tool_id, params)
    @logger.debug "[MCP_TELEMETRY] Tracking tool invocation start: #{execution_id}"

    @performance_data[execution_id] = {
      execution_id: execution_id,
      tool_id: tool_id,
      account_id: @account&.id,
      started_at: Time.current,
      input_size: calculate_data_size(params),
      status: "running"
    }

    # Update tool metrics
    tool_data = @tool_metrics[tool_id]
    if tool_data
      tool_data[:total_invocations] += 1
      tool_data[:last_invocation] = Time.current
    end

    # Update global metrics
    increment_metric("tool_invocations.total")
    increment_metric("tool_invocations.active")

    persist_metric("tool_invocation_start", {
      execution_id: execution_id,
      tool_id: tool_id,
      input_size: @performance_data[execution_id][:input_size],
      timestamp: Time.current
    })
  end

  # Track tool invocation completion
  def track_tool_invocation_complete(execution_id, result)
    @logger.debug "[MCP_TELEMETRY] Tracking tool invocation complete: #{execution_id}"

    performance_data = @performance_data[execution_id]
    return unless performance_data

    # Calculate execution metrics
    execution_time = Time.current - performance_data[:started_at]
    output_size = calculate_data_size(result)

    # Update performance data
    performance_data.merge!(
      completed_at: Time.current,
      execution_time: execution_time,
      output_size: output_size,
      status: "completed"
    )

    # Update tool metrics
    tool_data = @tool_metrics[performance_data[:tool_id]]
    if tool_data
      tool_data[:successful_invocations] += 1
      tool_data[:total_execution_time] += execution_time
      tool_data[:average_execution_time] =
        tool_data[:total_execution_time] / tool_data[:total_invocations]
    end

    # Update global metrics
    decrement_metric("tool_invocations.active")
    increment_metric("tool_invocations.successful")
    record_histogram("tool_execution.duration", execution_time)
    record_histogram("tool_execution.output_size", output_size)

    persist_metric("tool_invocation_complete", {
      execution_id: execution_id,
      tool_id: performance_data[:tool_id],
      execution_time: execution_time,
      input_size: performance_data[:input_size],
      output_size: output_size,
      timestamp: Time.current
    })

    # Clean up performance data
    @performance_data.delete(execution_id)
  end

  # Track tool invocation error
  def track_tool_invocation_error(execution_id, error)
    @logger.debug "[MCP_TELEMETRY] Tracking tool invocation error: #{execution_id}"

    performance_data = @performance_data[execution_id]
    return unless performance_data

    # Calculate partial execution metrics
    execution_time = Time.current - performance_data[:started_at]

    # Update performance data
    performance_data.merge!(
      failed_at: Time.current,
      execution_time: execution_time,
      error_message: error.message,
      error_type: error.class.name,
      status: "failed"
    )

    # Update tool metrics
    tool_data = @tool_metrics[performance_data[:tool_id]]
    if tool_data
      tool_data[:failed_invocations] += 1
    end

    # Update global metrics
    decrement_metric("tool_invocations.active")
    increment_metric("tool_invocations.failed")
    increment_metric("errors.by_type.#{error.class.name}")

    persist_metric("tool_invocation_error", {
      execution_id: execution_id,
      tool_id: performance_data[:tool_id],
      execution_time: execution_time,
      error_type: error.class.name,
      error_message: error.message,
      timestamp: Time.current
    })

    # Clean up performance data
    @performance_data.delete(execution_id)
  end

  # =============================================================================
  # MESSAGE TELEMETRY
  # =============================================================================

  # Track MCP message processing
  def track_message(connection_id, message_type, processing_time = nil)
    @logger.debug "[MCP_TELEMETRY] Tracking message: #{message_type}"

    # Update connection metrics
    connection_data = @connection_metrics[connection_id]
    if connection_data
      connection_data[:total_messages] += 1
      connection_data[:last_activity] = Time.current
    end

    # Update global metrics
    increment_metric("messages.total")
    increment_metric("messages.by_type.#{message_type}")

    if processing_time
      record_histogram("message.processing_time", processing_time)
    end

    persist_metric("message_processed", {
      connection_id: connection_id,
      message_type: message_type,
      processing_time: processing_time,
      timestamp: Time.current
    })
  end

  # Track message errors
  def track_message_error(connection_id, message_type, error)
    @logger.debug "[MCP_TELEMETRY] Tracking message error: #{message_type}"

    # Update connection metrics
    connection_data = @connection_metrics[connection_id]
    if connection_data
      connection_data[:total_errors] += 1
    end

    # Update global metrics
    increment_metric("messages.errors")
    increment_metric("errors.by_message_type.#{message_type}")

    persist_metric("message_error", {
      connection_id: connection_id,
      message_type: message_type,
      error_type: error.class.name,
      error_message: error.message,
      timestamp: Time.current
    })
  end

  # =============================================================================
  # METRICS REPORTING
  # =============================================================================

  # Get comprehensive telemetry report
  def get_telemetry_report(time_range = 24.hours)
    @logger.info "[MCP_TELEMETRY] Generating telemetry report"

    {
      generated_at: Time.current.iso8601,
      time_range_hours: time_range / 1.hour,
      account_id: @account&.id,
      summary: generate_summary_metrics,
      connections: generate_connection_metrics,
      tools: generate_tool_metrics,
      performance: generate_performance_metrics,
      errors: generate_error_metrics
    }
  end

  # Get real-time metrics
  def get_real_time_metrics
    {
      timestamp: Time.current.iso8601,
      active_connections: @metrics["connections.active"] || 0,
      active_tool_invocations: @metrics["tool_invocations.active"] || 0,
      total_tools: @metrics["tools.total"] || 0,
      total_messages: @metrics["messages.total"] || 0,
      total_errors: @metrics["messages.errors"] || 0
    }
  end

  # Get tool performance metrics
  def get_tool_performance(tool_id)
    tool_data = @tool_metrics[tool_id]
    return nil unless tool_data

    {
      tool_id: tool_id,
      total_invocations: tool_data[:total_invocations],
      successful_invocations: tool_data[:successful_invocations],
      failed_invocations: tool_data[:failed_invocations],
      success_rate: calculate_success_rate(tool_data),
      average_execution_time: tool_data[:average_execution_time],
      last_invocation: tool_data[:last_invocation]
    }
  end

  # Export metrics for external monitoring systems
  def export_metrics_prometheus
    prometheus_metrics = []

    @metrics.each do |metric_name, value|
      prometheus_metrics << "powernode_mcp_#{metric_name.gsub('.', '_')} #{value}"
    end

    prometheus_metrics.join("\n")
  end

  # =============================================================================
  # PRIVATE HELPER METHODS
  # =============================================================================

  private

  def initialize_metrics_storage
    @metrics = {
      "connections.total" => 0,
      "connections.active" => 0,
      "tools.total" => 0,
      "tool_invocations.total" => 0,
      "tool_invocations.active" => 0,
      "tool_invocations.successful" => 0,
      "tool_invocations.failed" => 0,
      "messages.total" => 0,
      "messages.errors" => 0
    }

    @histograms = {
      "connection.session_duration" => [],
      "tool_execution.duration" => [],
      "tool_execution.output_size" => [],
      "message.processing_time" => []
    }
  end

  def increment_metric(metric_name)
    @metrics[metric_name] = (@metrics[metric_name] || 0) + 1
  end

  def decrement_metric(metric_name)
    @metrics[metric_name] = [ (@metrics[metric_name] || 0) - 1, 0 ].max
  end

  def record_histogram(histogram_name, value)
    @histograms[histogram_name] ||= []
    @histograms[histogram_name] << {
      value: value,
      timestamp: Time.current
    }

    # Limit histogram size to prevent memory issues
    max_size = 10000
    if @histograms[histogram_name].size > max_size
      @histograms[histogram_name].shift
    end
  end

  def calculate_data_size(data)
    return 0 if data.blank?

    case data
    when String
      data.bytesize
    when Hash, Array
      data.to_json.bytesize
    else
      data.to_s.bytesize
    end
  end

  def calculate_success_rate(tool_data)
    total = tool_data[:total_invocations]
    return 0 if total.zero?

    (tool_data[:successful_invocations].to_f / total * 100).round(2)
  end

  def generate_summary_metrics
    {
      total_connections: @metrics["connections.total"],
      active_connections: @metrics["connections.active"],
      total_tools: @metrics["tools.total"],
      total_tool_invocations: @metrics["tool_invocations.total"],
      successful_invocations: @metrics["tool_invocations.successful"],
      failed_invocations: @metrics["tool_invocations.failed"],
      overall_success_rate: calculate_overall_success_rate,
      total_messages: @metrics["messages.total"],
      total_errors: @metrics["messages.errors"]
    }
  end

  def generate_connection_metrics
    {
      total_connections: @connection_metrics.size,
      average_session_duration: calculate_average_histogram("connection.session_duration"),
      connection_breakdown: @connection_metrics.values.map do |conn|
        {
          connection_id: conn[:connection_id],
          total_messages: conn[:total_messages],
          total_errors: conn[:total_errors],
          session_duration: conn[:ended_at] ?
            conn[:ended_at] - conn[:initialized_at] :
            Time.current - conn[:initialized_at]
        }
      end
    }
  end

  def generate_tool_metrics
    {
      total_tools: @tool_metrics.size,
      average_execution_time: calculate_average_histogram("tool_execution.duration"),
      tools_breakdown: @tool_metrics.values.map do |tool|
        {
          tool_id: tool[:tool_id],
          name: tool[:name],
          type: tool[:type],
          total_invocations: tool[:total_invocations],
          success_rate: calculate_success_rate(tool),
          average_execution_time: tool[:average_execution_time]
        }
      end
    }
  end

  def generate_performance_metrics
    {
      average_tool_execution_time: calculate_average_histogram("tool_execution.duration"),
      average_message_processing_time: calculate_average_histogram("message.processing_time"),
      average_output_size: calculate_average_histogram("tool_execution.output_size"),
      performance_percentiles: calculate_percentiles("tool_execution.duration")
    }
  end

  def generate_error_metrics
    error_metrics = {}

    @metrics.each do |metric_name, value|
      if metric_name.start_with?("errors.")
        error_metrics[metric_name] = value
      end
    end

    error_metrics
  end

  def calculate_overall_success_rate
    total = @metrics["tool_invocations.total"] || 0
    return 0 if total.zero?

    successful = @metrics["tool_invocations.successful"] || 0
    (successful.to_f / total * 100).round(2)
  end

  def calculate_average_histogram(histogram_name)
    values = @histograms[histogram_name] || []
    return 0 if values.empty?

    values.sum { |entry| entry[:value] } / values.size.to_f
  end

  def calculate_percentiles(histogram_name)
    values = @histograms[histogram_name]&.map { |entry| entry[:value] } || []
    return {} if values.empty?

    sorted_values = values.sort

    {
      p50: percentile(sorted_values, 50),
      p90: percentile(sorted_values, 90),
      p95: percentile(sorted_values, 95),
      p99: percentile(sorted_values, 99)
    }
  end

  def percentile(sorted_array, percentile)
    return 0 if sorted_array.empty?

    index = (percentile / 100.0 * (sorted_array.length - 1)).round
    sorted_array[index]
  end

  def persist_metric(metric_type, data)
    # In a production environment, this would write to a time-series database
    # For now, we'll log the metrics
    @logger.info "[MCP_TELEMETRY] #{metric_type}: #{data.to_json}"

    # Could also send to external monitoring services like Datadog, New Relic, etc.
    send_to_external_monitoring(metric_type, data) if Rails.env.production?
  end

  def send_to_external_monitoring(metric_type, data)
    # Implementation would depend on monitoring service
    # Example: send to Datadog, New Relic, CloudWatch, etc.
  end
end
