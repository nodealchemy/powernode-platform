# frozen_string_literal: true

require 'sidekiq'
require 'digest'
require 'json'

# Base job class for all Powernode worker jobs
# Provides common functionality, error handling, and API client access
class BaseJob
  include Sidekiq::Job

  # Common job configuration
  sidekiq_options retry: 3, 
                  dead: true,
                  queue: 'default'

  # Exponential backoff retry strategy
  sidekiq_retry_in do |count, exception|
    case exception
    when BackendApiClient::ApiError
      # API errors get shorter retry intervals
      [30, 60, 180][count - 1] || 300
    else
      # Other errors use exponential backoff
      (count ** 4) + 15 + (rand(30) * (count + 1))
    end
  end

  # Job arguments are written to the log in several places here, in the worker's
  # JobsController, and by Sidekiq's OWN default error handler (which logs the
  # whole job hash on every raised exception — wrapped in a redacting handler in
  # config/application.rb). Sidekiq also persists args VERBATIM in the Redis job
  # payload and in the retry/dead sets, which Sidekiq::Web renders.
  #
  # A job that has no choice but to carry a secret declares its positions here,
  # which masks it at the LOG sinks — NOT in Redis.
  #
  # This does NOT scrub Redis — nothing at this layer can. Prefer not putting a
  # secret in args at all: if the value is readable from the server's internal
  # API, pass an id and let the worker fetch it.
  def self.sensitive_arg_indexes
    []
  end

  # Hash-arg keys whose VALUE is masked wherever they appear, regardless of
  # position. Positional declaration cannot cover jobs whose payload is an
  # options hash (Notifications::NotificationEmailJob), and a future producer
  # dropping a token into such a hash would otherwise be logged verbatim.
  SENSITIVE_ARG_KEY = /token|secret|password|passwd|credential|api[_-]?key\z/i

  REDACTED = "[REDACTED]"

  # Positional args with the declared indexes replaced by a placeholder, and any
  # hash arg's sensitive-looking keys masked. Safe to call on any job class,
  # including ones that declare nothing.
  def self.redact_args(args)
    indexes = sensitive_arg_indexes

    args.each_with_index.map do |value, i|
      next REDACTED if indexes.include?(i) && !value.nil?

      redact_value(value)
    end
  end

  # Masks sensitive-looking keys in hashes, recursing through nested hashes and
  # arrays. Non-collection values are returned untouched.
  def self.redact_value(value)
    case value
    when Hash
      value.each_with_object({}) do |(k, v), out|
        out[k] = k.to_s.match?(SENSITIVE_ARG_KEY) && !v.nil? ? REDACTED : redact_value(v)
      end
    when Array
      value.map { |v| redact_value(v) }
    else
      value
    end
  end

  def perform(*args)
    @started_at = Time.current

    # Check for runaway loops before executing.
    # catch(:skip_job) allows disabled jobs to exit cleanly without triggering
    # Sidekiq retries or dead queue — the disable is temporary (5min TTL).
    catch(:skip_job) do
      check_runaway_loop(*args)

      logger.info "Starting #{self.class.name} with args: #{self.class.redact_args(args).inspect}"

      result = execute(*args)

      # Record execution attempt AFTER execute — only for jobs that actually
      # ran (not skipped by locks). Skipped jobs return { skipped: true }.
      unless result.is_a?(Hash) && result[:skipped]
        record_execution_attempt(*args)
      end

      @finished_at = Time.current
      duration = @finished_at - @started_at
      logger.info "Completed #{self.class.name} in #{duration.round(2)}s"

      # Record successful execution
      record_execution_success(*args)

      return result
    end
  rescue StandardError => e
    @finished_at = Time.current
    duration = @finished_at - @started_at
    logger.error "Failed #{self.class.name} after #{duration.round(2)}s: #{e.message}"
    logger.error e.backtrace.join("\n") if logger.level <= Logger::DEBUG

    # Record execution failure
    record_execution_failure(*args, e)

    raise
  end

  protected

  # Override this method in subclasses to implement job logic
  def execute(*args)
    raise NotImplementedError, "Subclasses must implement the execute method"
  end

  # API client for backend communication
  def api_client
    @api_client ||= BackendApiClient.new
  end

  # Alias for backward compatibility with reports job
  alias_method :backend_api_client, :api_client

  # Logger instance
  def logger
    PowernodeWorker.application.logger
  end

  # Helper to safely parse JSON
  def safe_parse_json(json_string, default = {})
    return default if json_string.nil? || json_string.empty?
    
    JSON.parse(json_string)
  rescue JSON::ParserError => e
    logger.warn "Failed to parse JSON: #{e.message}, using default: #{default}"
    default
  end

  # Helper to format currency amounts
  def format_currency(cents, currency = 'USD')
    return '$0.00' unless cents&.positive?
    
    dollars = cents.to_f / 100
    "$#{'%.2f' % dollars}"
  end

  # Helper to validate required parameters
  def validate_required_params(params, *required_keys)
    missing_keys = required_keys - params.keys.map(&:to_s)
    
    if missing_keys.any?
      raise ArgumentError, "Missing required parameters: #{missing_keys.join(', ')}"
    end
  end

  # The runaway-loop diagnostics dump the job's arguments. Extracted so the
  # masking on this sink is reachable from a spec — every job spec stubs
  # check_runaway_loop, so the inline form was never executed anywhere.
  def log_runaway_args(args, severity: :error)
    logger.public_send(severity, "Job args: #{self.class.redact_args(args).inspect}")
  end

  # Standardized logging methods (consistent with BaseWorkerService)
  def log_info(message, **metadata)
    logger.info format_log_message(message, **metadata)
  end

  def log_error(message, exception = nil, **metadata)
    error_details = {
      message: message,
      exception: exception&.class&.name,
      exception_message: exception&.message,
      backtrace: exception&.backtrace&.first(5)
    }.merge(metadata).compact

    logger.error format_log_message(message, **error_details)
  end

  def log_warn(message, **metadata)
    logger.warn format_log_message(message, **metadata)
  end

  # Metrics tracking methods (for monitoring and analytics)
  def increment_counter(metric_name, tags = {})
    # Track counter metric - can be enhanced with actual metrics service
    log_info("[METRIC] increment: #{metric_name}", **tags)
    record_metric(:counter, metric_name, 1, tags)
  end

  def track_performance_metric(metric_name, value, tags = {})
    # Track performance/timing metric
    log_info("[METRIC] performance: #{metric_name}=#{value}", **tags)
    record_metric(:gauge, metric_name, value, tags)
  end

  def track_cleanup_metrics(metrics = {})
    # Track cleanup-related metrics
    log_info("[METRIC] cleanup: #{metrics.to_json}")
    metrics.each do |key, value|
      record_metric(:gauge, "cleanup_#{key}", value, {})
    end
  end

  def track_error_metric(error_type, context = {})
    # Track error occurrences
    log_info("[METRIC] error: #{error_type}", **context)
    record_metric(:counter, "error_#{error_type}", 1, context)
  end

  private

  def record_metric(type, name, value, tags)
    # Store metrics in Redis for later aggregation
    # This provides a foundation for metrics collection
    begin
      metric_data = {
        type: type,
        name: name,
        value: value,
        tags: tags,
        job_class: self.class.name,
        timestamp: Time.current.to_f
      }

      Sidekiq.redis do |conn|
        conn.lpush("job_metrics:#{name}", metric_data.to_json)
        conn.ltrim("job_metrics:#{name}", 0, 999) # Keep last 1000 entries
        conn.expire("job_metrics:#{name}", 86400) # Expire after 24 hours
      end
    rescue StandardError => e
      # Don't fail the job if metrics recording fails
      logger.debug "Failed to record metric #{name}: #{e.message}"
    end
  end

  public

  # Format log messages with consistent structure
  def format_log_message(message, **metadata)
    if metadata.any?
      "#{message} | #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    else
      message
    end
  end

  # Idempotency helpers for preventing duplicate processing
  # Check if a job with the given idempotency key has already been processed
  def already_processed?(idempotency_key, ttl: 86400)
    Sidekiq.redis { |conn| conn.exists("idempotency:#{idempotency_key}") == 1 }
  end

  # Mark a job as processed with the given idempotency key
  def mark_processed(idempotency_key, ttl: 86400)
    Sidekiq.redis { |conn| conn.set("idempotency:#{idempotency_key}", Time.current.to_f, ex: ttl) }
  end

  # Helper to handle API errors with retry logic
  def with_api_retry(max_attempts: 3, &block)
    attempts = 0
    
    begin
      attempts += 1
      yield
    rescue BackendApiClient::ApiError => e
      if attempts < max_attempts && retryable_error?(e)
        logger.warn "API call failed (attempt #{attempts}/#{max_attempts}): #{e.message}, retrying..."
        sleep(2 ** attempts) # Exponential backoff
        retry
      else
        logger.error "API call failed after #{attempts} attempts: #{e.message}"
        raise
      end
    end
  end

  private

  # Loop detection and prevention methods
  def check_runaway_loop(*args)
    job_key = generate_job_key(*args)
    execution_key = "job_executions:#{job_key}"
    now = Time.current.to_f
    recent_window = 60 # 1 minute
    failure_window = 300 # 5 minutes

    # All Redis operations must happen inside the block — the connection is
    # only valid while checked out from the pool.
    recent_executions, disabled_reason = Sidekiq.redis do |conn|
      executions = conn.lrange(execution_key, 0, -1).map(&:to_f)
      reason = conn.get("job_disabled:#{job_key}")
      [executions, reason]
    end

    # Check if this job is currently disabled — skip silently instead of raising,
    # because retries just hit the same disabled check and waste cycles.
    if disabled_reason && !disabled_reason.empty?
      logger.info "#{self.class.name} skipped: disabled (#{disabled_reason}), will auto-resume in ≤5min"
      throw :skip_job
    end

    # Count executions in the last minute
    recent_count = recent_executions.count { |timestamp| (now - timestamp) <= recent_window }

    # Count total executions in the last 5 minutes
    total_count = recent_executions.count { |timestamp| (now - timestamp) <= failure_window }

    # Detect runaway loop conditions.
    # Subclasses can override thresholds via RUNAWAY_LOOP_THRESHOLD / RUNAWAY_LOOP_WARN_THRESHOLD
    # constants (e.g., continuous self-scheduling jobs need higher limits).
    threshold_min = self.class.const_defined?(:RUNAWAY_LOOP_THRESHOLD) ? self.class::RUNAWAY_LOOP_THRESHOLD : 5
    threshold_5min = self.class.const_defined?(:RUNAWAY_LOOP_WARN_THRESHOLD) ? self.class::RUNAWAY_LOOP_WARN_THRESHOLD : 15

    if recent_count >= threshold_min
      logger.error "RUNAWAY LOOP DETECTED: #{recent_count} executions of #{self.class.name} in last #{recent_window}s"
      log_runaway_args(args)
      logger.error "Recent timestamps: #{recent_executions.last(10).inspect}"

      Sidekiq.redis { |conn| conn.set("job_disabled:#{job_key}", "runaway_loop_detected", ex: 300) }

      raise StandardError, "Runaway loop detected: #{recent_count} executions in #{recent_window}s. Job disabled for 5 minutes."
    elsif total_count >= threshold_5min
      logger.warn "HIGH FREQUENCY EXECUTION: #{total_count} executions of #{self.class.name} in last #{failure_window}s"
      log_runaway_args(args, severity: :warn)

      # Add a delay to slow down execution
      sleep(5)
    end

    # Execution recording is deferred to perform() — only counts jobs that
    # actually ran (not duplicates skipped by locks or other early returns).
  end

  def record_execution_attempt(*args)
    job_key = generate_job_key(*args)
    execution_key = "job_executions:#{job_key}"
    now = Time.current.to_f

    Sidekiq.redis do |conn|
      conn.lpush(execution_key, now)
      conn.ltrim(execution_key, 0, 20) # Keep only last 20 executions
      conn.expire(execution_key, 360) # Auto-expire after 6 minutes
    end
  end

  def record_execution_success(*args)
    job_key = generate_job_key(*args)
    success_key = "job_success:#{job_key}"

    Sidekiq.redis { |conn| conn.set(success_key, Time.current.to_f, ex: 300) }
  end

  def record_execution_failure(*args, exception)
    job_key = generate_job_key(*args)
    failure_key = "job_failures:#{job_key}"

    failure_data = {
      timestamp: Time.current.to_f,
      error_class: exception.class.name,
      error_message: exception.message,
      job_class: self.class.name
    }

    Sidekiq.redis do |conn|
      conn.lpush(failure_key, failure_data.to_json)
      conn.ltrim(failure_key, 0, 9) # Keep only last 10 failures
      conn.expire(failure_key, 3600) # Auto-expire after 1 hour
    end
  end

  def generate_job_key(*args)
    # Create a consistent key for the same job + arguments combination
    # For jobs with UUID arguments, use the UUID as the key component
    if args.first.is_a?(String) && args.first.match?(/^[0-9a-f-]+$/)
      # Assume first argument is a UUID (execution ID, etc.)
      "#{self.class.name}:#{args.first}"
    else
      # For other jobs, create a hash of the arguments
      args_hash = Digest::SHA256.hexdigest(args.to_json)[0..15]
      "#{self.class.name}:#{args_hash}"
    end
  end

  def retryable_error?(error)
    # 502/503/504 (and connection/timeout) are retried at the transport layer by the
    # BackendApiClient Faraday retry middleware. Re-retrying them here would multiply the
    # attempts (Faraday's 5x * this layer's Nx). Only retry statuses Faraday does NOT:
    # 408 (request timeout), 429 (rate limit), 500 (server error). See A-W9c.
    case error.status
    when 408, 429, 500
      true
    else
      false
    end
  end
end