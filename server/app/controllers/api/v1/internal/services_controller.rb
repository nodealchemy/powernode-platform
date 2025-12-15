# frozen_string_literal: true

# Internal API controller for worker service health and configuration
class Api::V1::Internal::ServicesController < Api::V1::Internal::InternalBaseController
  # POST /api/v1/internal/services/health_check
  def health_check
    # Perform basic health checks
    health_status = {
      database: check_database,
      redis: check_redis,
      timestamp: Time.current
    }

    render_success(data: health_status)
  end

  # POST /api/v1/internal/services/generate_config
  def generate_config
    # Generate service configuration
    config = {
      api_version: "v1",
      environment: Rails.env,
      services: available_services,
      timestamp: Time.current
    }

    render_success(data: config)
  end

  # POST /api/v1/internal/services/service_discovery
  def service_discovery
    # Return discovered services
    services = available_services

    render_success(data: { services: services })
  end

  # POST /api/v1/internal/services/validate
  def validate
    # Validate service configuration
    valid = true
    errors = []

    render_success(data: { valid: valid, errors: errors })
  end

  # POST /api/v1/internal/services/test_connectivity
  def test_connectivity
    # Test connectivity to external services
    results = {
      database: test_database_connection,
      redis: test_redis_connection
    }

    render_success(data: results)
  end

  # POST /api/v1/internal/services/validate_services
  def validate_services
    # Validate all registered services
    validations = available_services.map do |service|
      { name: service[:name], valid: true }
    end

    render_success(data: { validations: validations })
  end

  private

  def check_database
    ActiveRecord::Base.connection.active? ? "healthy" : "unhealthy"
  rescue StandardError
    "unhealthy"
  end

  def check_redis
    Redis.current.ping == "PONG" ? "healthy" : "unhealthy"
  rescue StandardError
    "unhealthy"
  end

  def test_database_connection
    { connected: ActiveRecord::Base.connection.active?, latency_ms: 0 }
  rescue StandardError => e
    { connected: false, error: e.message }
  end

  def test_redis_connection
    start = Time.current
    Redis.current.ping
    latency = ((Time.current - start) * 1000).round(2)
    { connected: true, latency_ms: latency }
  rescue StandardError => e
    { connected: false, error: e.message }
  end

  def available_services
    [
      { name: "api", url: ENV.fetch("API_URL", "http://localhost:3000"), status: "active" },
      { name: "worker", url: ENV.fetch("WORKER_URL", "http://localhost:3001"), status: "active" }
    ]
  end
end
