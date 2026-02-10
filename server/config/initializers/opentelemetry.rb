# frozen_string_literal: true

# OpenTelemetry instrumentation for distributed tracing
# Enable by setting OTEL_ENABLED=true in environment
#
# Required environment variables:
#   OTEL_ENABLED=true
#   OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 (default)
#   OTEL_SERVICE_NAME=powernode-backend (default)
#
# Optional:
#   OTEL_LOG_LEVEL=info
#   OTEL_TRACES_SAMPLER=parentbased_traceidratio
#   OTEL_TRACES_SAMPLER_ARG=1.0

if ENV["OTEL_ENABLED"] == "true"
  begin
    require "opentelemetry/sdk"
    require "opentelemetry/exporter/otlp"
  rescue LoadError => e
    Rails.logger.warn("[OpenTelemetry] OTEL_ENABLED=true but gems not installed: #{e.message}")
    Rails.logger.warn("[OpenTelemetry] Install with: bundle install --with opentelemetry")
    return
  end

  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "powernode-backend")
    c.service_version = ENV.fetch("OTEL_SERVICE_VERSION", "0.1.0")

    # Auto-instrument Rails, ActiveRecord, HTTP, Redis, Rack, PG
    c.use_all(
      "OpenTelemetry::Instrumentation::Rails" => {
        enable_recognize_route: true
      },
      "OpenTelemetry::Instrumentation::ActiveRecord" => {
        db_statement: :obfuscate
      },
      "OpenTelemetry::Instrumentation::Rack" => {
        allowed_request_headers: %w[x-request-id x-correlation-id],
        allowed_response_headers: %w[x-request-id]
      },
      "OpenTelemetry::Instrumentation::Pg" => {
        db_statement: :obfuscate,
        peer_service: "postgresql"
      }
    )

    # Configure OTLP exporter
    c.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
        OpenTelemetry::Exporter::OTLP::Exporter.new(
          endpoint: ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
        )
      )
    )
  end

  Rails.logger.info("[OpenTelemetry] Initialized with service_name=#{ENV.fetch('OTEL_SERVICE_NAME', 'powernode-backend')}")
end
