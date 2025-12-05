# frozen_string_literal: true

require 'net/http'
require 'timeout'

# Enhanced error tracking and analysis service for AI workflows
# Provides structured error logging, pattern analysis, and recovery recommendations
class AiWorkflowErrorTrackingService
  include Singleton

  ERROR_CATEGORIES = {
    connection: 'Connection and network errors',
    timeout: 'Request timeout errors',
    authentication: 'Authentication and authorization errors',
    validation: 'Data validation errors',
    provider: 'AI provider specific errors',
    processing: 'Message processing errors',
    circuit_breaker: 'Circuit breaker triggered errors',
    unknown: 'Unknown or uncategorized errors'
  }.freeze

  SEVERITY_LEVELS = {
    low: 1,
    medium: 2,
    high: 3,
    critical: 4
  }.freeze

  def initialize
    @errors = []
    @error_patterns = {}
    @mutex = Mutex.new
    @logger = PowernodeWorker.application.logger
  end

  # Track a new error with enhanced context
  def track_error(error, context = {})
    @mutex.synchronize do
      error_record = build_error_record(error, context)
      @errors << error_record

      # Limit stored errors to last 1000
      @errors = @errors.last(1000) if @errors.size > 1000

      # Update patterns
      update_error_patterns(error_record)

      # Log structured error
      log_structured_error(error_record)

      # Check for critical patterns
      check_critical_patterns(error_record)

      error_record
    end
  end

  # Get error analysis for a time period
  def analyze_errors(since: 1.hour.ago)
    @mutex.synchronize do
      recent_errors = @errors.select { |e| e[:timestamp] >= since }

      {
        total_errors: recent_errors.size,
        error_rate: calculate_error_rate(recent_errors, since),
        error_breakdown: categorize_errors(recent_errors),
        severity_breakdown: analyze_severity(recent_errors),
        top_error_patterns: top_error_patterns(recent_errors),
        service_health: analyze_service_health(recent_errors),
        recommendations: generate_recommendations(recent_errors)
      }
    end
  end

  # Get detailed error patterns
  def error_patterns(limit: 10)
    @mutex.synchronize do
      @error_patterns.sort_by { |_, data| -data[:count] }.first(limit).to_h
    end
  end

  # Get errors by category
  def errors_by_category(category, since: 1.hour.ago)
    @mutex.synchronize do
      @errors.select do |error|
        error[:category] == category && error[:timestamp] >= since
      end
    end
  end

  # Get recent critical errors
  def critical_errors(since: 1.hour.ago)
    @mutex.synchronize do
      @errors.select do |error|
        error[:severity] == :critical && error[:timestamp] >= since
      end
    end
  end

  # Clear old errors (useful for testing or memory management)
  def clear_old_errors(older_than: 24.hours.ago)
    @mutex.synchronize do
      old_count = @errors.size
      @errors.reject! { |error| error[:timestamp] < older_than }
      new_count = @errors.size

      @logger.info "[ErrorTracking] Cleared #{old_count - new_count} old error records"
      old_count - new_count
    end
  end

  # Export error data for external analysis
  def export_errors(format: :json, since: 24.hours.ago)
    @mutex.synchronize do
      recent_errors = @errors.select { |e| e[:timestamp] >= since }

      case format
      when :json
        recent_errors.to_json
      when :csv
        export_to_csv(recent_errors)
      else
        recent_errors
      end
    end
  end

  # Get system health status based on error patterns
  def system_health_status
    recent_errors = @errors.select { |e| e[:timestamp] >= 1.hour.ago }

    return :healthy if recent_errors.empty?

    critical_count = recent_errors.count { |e| e[:severity] == :critical }
    high_count = recent_errors.count { |e| e[:severity] == :high }
    total_count = recent_errors.size

    if critical_count > 5 || total_count > 50
      :critical
    elsif critical_count > 2 || high_count > 10 || total_count > 20
      :degraded
    elsif total_count > 10
      :warning
    else
      :healthy
    end
  end

  private

  def build_error_record(error, context)
    {
      id: SecureRandom.uuid,
      timestamp: Time.current,
      error_class: error.class.name,
      error_message: error.message,
      category: categorize_error(error),
      severity: determine_severity(error, context),
      context: sanitize_context(context),
      stack_trace: error.backtrace&.first(10),
      job_class: context[:job_class],
      provider_info: extract_provider_info(context),
      retry_count: context[:retry_count] || 0,
      fingerprint: generate_error_fingerprint(error, context)
    }
  end

  def categorize_error(error)
    case error
    when BackendApiClient::ApiError
      case error.status
      when 401, 403
        :authentication
      when 408, 504
        :timeout
      when 422
        :validation
      when 500..599
        :connection
      else
        :unknown
      end
    when CircuitBreaker::CircuitOpenError
      :circuit_breaker
    when Net::ReadTimeout, Net::OpenTimeout, Timeout::Error
      :timeout
    when Faraday::ConnectionFailed, Errno::ECONNREFUSED
      :connection
    when JSON::ParserError
      :processing
    else
      # Check error message for patterns
      message = error.message.downcase
      if message.include?('connection') || message.include?('network')
        :connection
      elsif message.include?('timeout')
        :timeout
      elsif message.include?('auth') || message.include?('permission')
        :authentication
      elsif message.include?('validation')
        :validation
      elsif message.include?('provider') || message.include?('api key')
        :provider
      else
        :unknown
      end
    end
  end

  def determine_severity(error, context)
    # Base severity on error type and context
    case categorize_error(error)
    when :circuit_breaker
      :high
    when :connection
      context[:retry_count].to_i > 2 ? :high : :medium
    when :authentication
      :high
    when :timeout
      context[:retry_count].to_i > 1 ? :medium : :low
    when :provider
      :high
    when :validation
      :medium
    when :processing
      :medium
    else
      :low
    end
  end

  def sanitize_context(context)
    # Remove sensitive information from context
    sanitized = context.dup
    sanitized.delete(:password)
    sanitized.delete(:api_key)
    sanitized.delete(:token)
    sanitized.delete(:credentials)

    # Truncate large data
    sanitized.transform_values do |value|
      if value.is_a?(String) && value.length > 1000
        "#{value[0..997]}..."
      else
        value
      end
    end
  end

  def extract_provider_info(context)
    return nil unless context[:provider]

    {
      provider_id: context[:provider][:id],
      provider_name: context[:provider][:name],
      provider_type: context[:provider][:provider_type]
    }
  end

  def generate_error_fingerprint(error, context)
    # Create a fingerprint for grouping similar errors
    elements = [
      error.class.name,
      error.message&.gsub(/\d+/, 'N')&.gsub(/[a-f0-9-]{8,}/, 'ID'), # Normalize IDs and numbers
      context[:job_class],
      context[:provider]&.dig(:provider_type)
    ].compact

    Digest::SHA256.hexdigest(elements.join('|'))[0..15]
  end

  def update_error_patterns(error_record)
    fingerprint = error_record[:fingerprint]
    @error_patterns[fingerprint] ||= {
      count: 0,
      first_seen: error_record[:timestamp],
      last_seen: error_record[:timestamp],
      error_class: error_record[:error_class],
      category: error_record[:category],
      sample_message: error_record[:error_message]
    }

    pattern = @error_patterns[fingerprint]
    pattern[:count] += 1
    pattern[:last_seen] = error_record[:timestamp]
  end

  def log_structured_error(error_record)
    log_data = {
      event_type: 'ai_workflow_error',
      error_id: error_record[:id],
      category: error_record[:category],
      severity: error_record[:severity],
      error_class: error_record[:error_class],
      fingerprint: error_record[:fingerprint],
      job_class: error_record[:job_class],
      provider_type: error_record.dig(:provider_info, :provider_type),
      retry_count: error_record[:retry_count]
    }

    case error_record[:severity]
    when :critical
      @logger.error "[AI_ERROR_TRACKING] #{log_data.to_json}"
    when :high
      @logger.error "[AI_ERROR_TRACKING] #{log_data.to_json}"
    when :medium
      @logger.warn "[AI_ERROR_TRACKING] #{log_data.to_json}"
    else
      @logger.info "[AI_ERROR_TRACKING] #{log_data.to_json}"
    end
  end

  def check_critical_patterns(error_record)
    # Check for patterns that indicate critical issues
    fingerprint = error_record[:fingerprint]
    pattern = @error_patterns[fingerprint]

    if pattern[:count] >= 5 && (Time.current - pattern[:first_seen]) < 300 # 5 errors in 5 minutes
      @logger.error "[AI_ERROR_TRACKING] CRITICAL PATTERN DETECTED: #{fingerprint} - #{pattern[:count]} occurrences in #{Time.current - pattern[:first_seen]} seconds"
    end

    # Check for circuit breaker activation
    if error_record[:category] == :circuit_breaker
      @logger.error "[AI_ERROR_TRACKING] CIRCUIT BREAKER ACTIVATED: #{error_record[:error_message]}"
    end
  end

  def calculate_error_rate(errors, since)
    return 0 if errors.empty?

    time_window = Time.current - since
    errors.size.to_f / (time_window / 60) # errors per minute
  end

  def categorize_errors(errors)
    ERROR_CATEGORIES.keys.map do |category|
      count = errors.count { |e| e[:category] == category }
      [category, count]
    end.to_h
  end

  def analyze_severity(errors)
    SEVERITY_LEVELS.keys.map do |severity|
      count = errors.count { |e| e[:severity] == severity }
      [severity, count]
    end.to_h
  end

  def top_error_patterns(errors, limit: 5)
    fingerprints = errors.group_by { |e| e[:fingerprint] }
    fingerprints.sort_by { |_, group| -group.size }
               .first(limit)
               .map do |fingerprint, group|
      {
        fingerprint: fingerprint,
        count: group.size,
        error_class: group.first[:error_class],
        category: group.first[:category],
        sample_message: group.first[:error_message]
      }
    end
  end

  def analyze_service_health(errors)
    services = {}

    errors.each do |error|
      service_key = if error[:category] == :provider
                     error.dig(:provider_info, :provider_type) || 'unknown_provider'
                   elsif error[:category] == :connection
                     'backend_api'
                   else
                     'general'
                   end

      services[service_key] ||= { error_count: 0, categories: Hash.new(0) }
      services[service_key][:error_count] += 1
      services[service_key][:categories][error[:category]] += 1
    end

    services.transform_values do |data|
      data.merge(
        health_status: case data[:error_count]
                      when 0..2 then :healthy
                      when 3..10 then :degraded
                      else :unhealthy
                      end
      )
    end
  end

  def generate_recommendations(errors)
    recommendations = []

    # Connection error recommendations
    connection_errors = errors.count { |e| e[:category] == :connection }
    if connection_errors > 5
      recommendations << {
        priority: :high,
        category: :connection,
        message: "High number of connection errors (#{connection_errors}). Check backend service health and network connectivity.",
        action: 'check_backend_status'
      }
    end

    # Circuit breaker recommendations
    circuit_breaker_errors = errors.count { |e| e[:category] == :circuit_breaker }
    if circuit_breaker_errors > 0
      recommendations << {
        priority: :medium,
        category: :circuit_breaker,
        message: "Circuit breaker activated #{circuit_breaker_errors} times. Investigate underlying service issues.",
        action: 'investigate_service_health'
      }
    end

    # Provider error recommendations
    provider_errors = errors.count { |e| e[:category] == :provider }
    if provider_errors > 3
      recommendations << {
        priority: :medium,
        category: :provider,
        message: "Multiple AI provider errors (#{provider_errors}). Check provider credentials and connectivity.",
        action: 'verify_provider_config'
      }
    end

    # Timeout recommendations
    timeout_errors = errors.count { |e| e[:category] == :timeout }
    if timeout_errors > 10
      recommendations << {
        priority: :medium,
        category: :timeout,
        message: "High number of timeout errors (#{timeout_errors}). Consider increasing timeout values or optimizing requests.",
        action: 'optimize_timeouts'
      }
    end

    recommendations
  end

  def export_to_csv(errors)
    require 'csv'

    CSV.generate do |csv|
      csv << ['Timestamp', 'Error Class', 'Category', 'Severity', 'Message', 'Job Class', 'Provider Type', 'Retry Count']

      errors.each do |error|
        csv << [
          error[:timestamp],
          error[:error_class],
          error[:category],
          error[:severity],
          error[:error_message],
          error[:job_class],
          error.dig(:provider_info, :provider_type),
          error[:retry_count]
        ]
      end
    end
  end
end