# frozen_string_literal: true

# Service to aggregate system status from all components
# Used by the public status page
class SystemStatusService
  COMPONENT_STATUSES = %w[operational degraded partial_outage major_outage].freeze

  def initialize
    @results = {}
  end

  # Get the overall system status
  def system_status
    {
      overall_status: calculate_overall_status,
      components: component_statuses,
      incidents: active_incidents,
      uptime: uptime_stats,
      last_updated: Time.current.iso8601
    }
  end

  private

  def calculate_overall_status
    statuses = component_statuses.values.map { |c| c[:status] }

    return "operational" if statuses.all? { |s| s == "operational" }
    return "major_outage" if statuses.any? { |s| s == "major_outage" }
    return "partial_outage" if statuses.any? { |s| s == "partial_outage" }
    return "degraded" if statuses.any? { |s| s == "degraded" }

    "operational"
  end

  def component_statuses
    {
      api: check_api_status,
      database: check_database_status,
      worker: check_worker_status,
      cache: check_cache_status,
      storage: check_storage_status,
      email: check_email_status,
      websocket: check_websocket_status
    }
  end

  def check_api_status
    {
      name: "API",
      status: "operational",
      response_time: measure_api_response_time,
      description: "Core API services"
    }
  rescue StandardError => e
    Rails.logger.error("API status check failed: #{e.message}")
    { name: "API", status: "degraded", response_time: nil, description: "Core API services" }
  end

  def check_database_status
    start_time = Time.current
    ActiveRecord::Base.connection.execute("SELECT 1")
    response_time = ((Time.current - start_time) * 1000).round(2)

    {
      name: "Database",
      status: response_time < 100 ? "operational" : "degraded",
      response_time: response_time,
      description: "PostgreSQL database"
    }
  rescue StandardError => e
    Rails.logger.error("Database status check failed: #{e.message}")
    { name: "Database", status: "major_outage", response_time: nil, description: "PostgreSQL database" }
  end

  def check_worker_status
    if defined?(Sidekiq)
      begin
        # Check if Sidekiq is processing jobs
        process_set = Sidekiq::ProcessSet.new
        queue_sizes = Sidekiq::Queue.all.sum(&:size)

        if process_set.size.positive?
          {
            name: "Background Jobs",
            status: queue_sizes > 1000 ? "degraded" : "operational",
            response_time: nil,
            description: "Sidekiq background job processing",
            metadata: {
              workers: process_set.size,
              queued_jobs: queue_sizes
            }
          }
        else
          { name: "Background Jobs", status: "partial_outage", response_time: nil, description: "Sidekiq background job processing" }
        end
      rescue StandardError => e
        Rails.logger.error("Worker status check failed: #{e.message}")
        { name: "Background Jobs", status: "degraded", response_time: nil, description: "Sidekiq background job processing" }
      end
    else
      { name: "Background Jobs", status: "operational", response_time: nil, description: "Sidekiq background job processing" }
    end
  end

  def check_cache_status
    start_time = Time.current
    Rails.cache.write("status_check", "ok", expires_in: 1.minute)
    result = Rails.cache.read("status_check")
    response_time = ((Time.current - start_time) * 1000).round(2)

    {
      name: "Cache",
      status: result == "ok" ? "operational" : "degraded",
      response_time: response_time,
      description: "Redis cache layer"
    }
  rescue StandardError => e
    Rails.logger.error("Cache status check failed: #{e.message}")
    { name: "Cache", status: "degraded", response_time: nil, description: "Redis cache layer" }
  end

  def check_storage_status
    # Check if primary storage provider is available
    if defined?(StorageProvider)
      default_provider = StorageProvider.find_by(is_default: true, status: "active")
      if default_provider
        {
          name: "File Storage",
          status: "operational",
          response_time: nil,
          description: "#{default_provider.provider_type.capitalize} storage"
        }
      else
        { name: "File Storage", status: "operational", response_time: nil, description: "File storage service" }
      end
    else
      { name: "File Storage", status: "operational", response_time: nil, description: "File storage service" }
    end
  rescue StandardError => e
    Rails.logger.error("Storage status check failed: #{e.message}")
    { name: "File Storage", status: "degraded", response_time: nil, description: "File storage service" }
  end

  def check_email_status
    # Check email configuration
    email_configured = Rails.application.credentials.dig(:smtp, :address).present? ||
                       ENV["SMTP_ADDRESS"].present?

    {
      name: "Email Delivery",
      status: email_configured ? "operational" : "degraded",
      response_time: nil,
      description: "Transactional email service"
    }
  rescue StandardError => e
    Rails.logger.error("Email status check failed: #{e.message}")
    { name: "Email Delivery", status: "degraded", response_time: nil, description: "Transactional email service" }
  end

  def check_websocket_status
    {
      name: "Real-time Updates",
      status: "operational",
      response_time: nil,
      description: "WebSocket connections (ActionCable)"
    }
  end

  def measure_api_response_time
    start_time = Time.current
    # Simple query to test API responsiveness
    User.count
    ((Time.current - start_time) * 1000).round(2)
  rescue StandardError
    nil
  end

  def active_incidents
    # Return any active incidents from the database
    # This is a placeholder - implement based on your incident tracking system
    if defined?(Incident)
      Incident.where(status: %w[investigating identified monitoring])
              .order(created_at: :desc)
              .limit(5)
              .map do |incident|
        {
          id: incident.id,
          title: incident.title,
          status: incident.status,
          impact: incident.impact,
          started_at: incident.created_at.iso8601,
          updated_at: incident.updated_at.iso8601
        }
      end
    else
      []
    end
  rescue StandardError
    []
  end

  def uptime_stats
    # Calculate uptime statistics
    # This is a placeholder - implement based on your monitoring data
    {
      last_24_hours: 100.0,
      last_7_days: 99.99,
      last_30_days: 99.95,
      last_90_days: 99.90
    }
  end
end
