# frozen_string_literal: true

# Centralized Logging Configuration
# Provides structured logging, log aggregation integration, and custom log levels

module Powernode
  module Logging
    # =========================================================================
    # LOG LEVELS
    # =========================================================================

    LEVELS = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3,
      fatal: 4,
      security: 5,  # Custom level for security events
      audit: 6      # Custom level for audit events
    }.freeze

    # =========================================================================
    # STRUCTURED LOGGER
    # =========================================================================

    class StructuredLogger < ActiveSupport::Logger
      def initialize(*args)
        super
        @application = 'powernode'
        @service = ENV.fetch('SERVICE_NAME', 'backend')
        @environment = Rails.env
      end

      def structured_log(level, message, context = {})
        entry = build_log_entry(level, message, context)

        case level
        when :debug then debug(entry.to_json)
        when :info then info(entry.to_json)
        when :warn then warn(entry.to_json)
        when :error then error(entry.to_json)
        when :fatal then fatal(entry.to_json)
        else info(entry.to_json)
        end
      end

      def security_event(event_type, message, context = {})
        structured_log(:warn, message, context.merge(
          log_type: 'security',
          security_event: event_type,
          severity: context[:severity] || 'medium'
        ))
      end

      def audit_event(action, resource, context = {})
        structured_log(:info, "Audit: #{action} on #{resource}", context.merge(
          log_type: 'audit',
          audit_action: action,
          audit_resource: resource
        ))
      end

      def performance_metric(metric_name, value, context = {})
        structured_log(:info, "Performance: #{metric_name}", context.merge(
          log_type: 'performance',
          metric_name: metric_name,
          metric_value: value
        ))
      end

      private

      def build_log_entry(level, message, context)
        {
          '@timestamp': Time.current.iso8601(3),
          '@version': '1',
          level: level.to_s.upcase,
          message: message,
          application: @application,
          service: @service,
          environment: @environment,
          host: Socket.gethostname,
          pid: Process.pid,
          thread_id: Thread.current.object_id,
          **context
        }.compact
      end
    end

    # =========================================================================
    # JSON FORMATTER
    # =========================================================================

    class JsonFormatter < ::Logger::Formatter
      def call(severity, time, progname, msg)
        entry = {
          '@timestamp': time.utc.iso8601(3),
          '@version': '1',
          level: severity,
          logger: progname,
          message: msg.to_s.strip,
          application: ENV.fetch('APPLICATION_NAME', 'powernode'),
          service: ENV.fetch('SERVICE_NAME', 'backend'),
          environment: Rails.env,
          host: Socket.gethostname,
          pid: Process.pid
        }

        "#{entry.to_json}\n"
      end
    end

    # =========================================================================
    # LOG AGGREGATION HELPERS
    # =========================================================================

    class << self
      # Log with structured context
      def log(level, message, context = {})
        Rails.logger.tagged(context[:tags] || []) do
          entry = format_entry(level, message, context)
          Rails.logger.send(level, entry)
        end
      end

      # Log security-related events
      def security(event_type, message, context = {})
        log(:warn, message, context.merge(
          log_type: 'security',
          security_event: event_type,
          severity: context[:severity] || 'medium'
        ))

        # Also write to dedicated security log in production
        write_to_security_log(event_type, message, context) if Rails.env.production?
      end

      # Log audit events
      def audit(action, resource_type, resource_id, context = {})
        log(:info, "Audit: #{action} on #{resource_type}##{resource_id}", context.merge(
          log_type: 'audit',
          audit_action: action,
          resource_type: resource_type,
          resource_id: resource_id
        ))
      end

      # Log performance metrics
      def performance(metric_name, value, unit: 'ms', context: {})
        log(:info, "Performance: #{metric_name} = #{value}#{unit}", context.merge(
          log_type: 'performance',
          metric_name: metric_name,
          metric_value: value,
          metric_unit: unit
        ))
      end

      # Log external service interactions
      def external_service(service_name, operation, context = {})
        log(:info, "External: #{service_name}##{operation}", context.merge(
          log_type: 'external_service',
          external_service: service_name,
          operation: operation
        ))
      end

      # Log job execution
      def job(job_name, status, context = {})
        log(:info, "Job: #{job_name} - #{status}", context.merge(
          log_type: 'job',
          job_name: job_name,
          job_status: status
        ))
      end

      # Log API request (for manual logging where lograge doesn't cover)
      def api_request(method, path, context = {})
        log(:info, "API: #{method} #{path}", context.merge(
          log_type: 'api_request',
          http_method: method,
          path: path
        ))
      end

      private

      def format_entry(level, message, context)
        if Rails.env.production? || ENV['LOGRAGE_JSON_ENABLED'] == 'true'
          {
            '@timestamp': Time.current.iso8601(3),
            level: level.to_s.upcase,
            message: message,
            **context.except(:tags)
          }.to_json
        else
          # More readable format for development
          parts = ["[#{level.to_s.upcase}] #{message}"]
          context.except(:tags).each { |k, v| parts << "#{k}=#{v.inspect}" }
          parts.join(' ')
        end
      end

      def write_to_security_log(event_type, message, context)
        security_log_path = Rails.root.join('log', 'security.log')
        entry = {
          timestamp: Time.current.iso8601(3),
          event_type: event_type,
          message: message,
          **context
        }.to_json

        File.open(security_log_path, 'a') { |f| f.puts(entry) }
      rescue StandardError => e
        Rails.logger.error("Failed to write security log: #{e.message}")
      end
    end
  end
end

# =========================================================================
# RAILS CONFIGURATION (via initializer callback)
# =========================================================================

Rails.application.config.after_initialize do
  # Log slow queries in production
  if Rails.env.production?
    ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, start, finish, _id, payload|
      duration_ms = ((finish - start) * 1000).round(2)

      # Log queries slower than threshold
      slow_query_threshold_ms = ENV.fetch('SLOW_QUERY_THRESHOLD_MS', 100).to_i
      if duration_ms > slow_query_threshold_ms
        Powernode::Logging.performance(
          'slow_query',
          duration_ms,
          context: {
            sql: payload[:sql].truncate(500),
            name: payload[:name],
            cached: payload[:cached]
          }
        )
      end
    end
  end

  # Configure Sidekiq logging if available
  if defined?(Sidekiq) && Rails.env.production?
    Sidekiq.configure_server do |config|
      config.logger.formatter = Powernode::Logging::JsonFormatter.new
    end
  end
end

# =========================================================================
# GLOBAL HELPER
# =========================================================================

# Make logging easily accessible
def Plog
  Powernode::Logging
end
