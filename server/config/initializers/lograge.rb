# frozen_string_literal: true

# Lograge Configuration for Centralized Logging
# Provides structured JSON logs optimized for ELK Stack, CloudWatch, Datadog, etc.
#
# Only enabled in production/staging to avoid issues with Rails 8 frozen arrays in test/development

# Only configure lograge for production-like environments
return unless Rails.env.production? || Rails.env.staging? || ENV["LOGRAGE_ENABLED"] == "true"

# Require the gems since they're set to require: false in Gemfile
require "lograge"
require "logstash-event"

Rails.application.config.lograge.enabled = true
Rails.application.config.lograge.formatter = Lograge::Formatters::Logstash.new

# Include custom data in each log entry
Rails.application.config.lograge.custom_options = lambda do |event|
  payload = event.payload

  # Base custom fields
  custom = {
    # Timing information
    time: Time.current.iso8601(3),
    timestamp: Time.current.to_i,

    # Request identification
    request_id: payload[:request_id] || SecureRandom.uuid,
    correlation_id: payload[:correlation_id],

    # Environment info
    environment: Rails.env,
    host: payload[:host] || Socket.gethostname,

    # User context (if authenticated)
    user_id: payload[:user_id],
    account_id: payload[:account_id],

    # API versioning
    api_version: payload[:api_version] || "v1",

    # Additional metrics
    db_runtime_ms: payload[:db_runtime]&.round(2),
    view_runtime_ms: payload[:view_runtime]&.round(2),
    allocations: payload[:allocations],

    # Request details
    content_length: payload[:content_length],
    remote_ip: payload[:remote_ip],
    user_agent: payload[:user_agent],

    # Application name for multi-service environments
    application: "powernode-api",
    service: "backend"
  }

  # Add rate limit info if present
  if payload[:rate_limit_tier]
    custom[:rate_limit_tier] = payload[:rate_limit_tier]
    custom[:rate_limit_remaining] = payload[:rate_limit_remaining]
  end

  # Add error information if present
  if payload[:exception]
    custom[:exception] = {
      class: payload[:exception].first,
      message: payload[:exception].last
    }
  end

  # Add custom tags for filtering
  custom[:tags] = payload[:tags] if payload[:tags].present?

  # Remove nil values to reduce log size
  custom.compact
end

# Include custom payload in controllers
Rails.application.config.lograge.custom_payload do |controller|
  {
    # Add user context from controllers
    user_id: controller.try(:current_user)&.id,
    account_id: controller.try(:current_account)&.id,

    # Request metadata
    request_id: controller.request.request_id,
    correlation_id: controller.request.headers["X-Correlation-ID"],
    host: controller.request.host,
    remote_ip: controller.request.remote_ip,
    user_agent: controller.request.user_agent&.truncate(200),
    content_length: controller.request.content_length,

    # API version from path
    api_version: controller.request.path.match(%r{/api/(v\d+)/})&.captures&.first
  }
end

# Reduce noise by filtering common healthcheck paths
Rails.application.config.lograge.ignore_actions = %w[
  HealthController#show
  HealthController#index
  StatusController#show
  Api::V1::Public::StatusController#show
  Rails::HealthController#show
]

# Ignore specific paths (healthchecks, metrics, etc.)
Rails.application.config.lograge.ignore_custom = lambda do |event|
  # Ignore healthcheck and metrics endpoints
  event.payload[:path] =~ %r{^/(health|ready|live|metrics|up|favicon)}
end
