# frozen_string_literal: true

# Ai::CircuitBreakerRegistry - Unified circuit breaker registry
#
# Replaces WorkflowCircuitBreakerManager and provides a single entry point
# for all circuit breaker management across the platform.
#
# Usage:
#   # Protect a service call
#   Ai::CircuitBreakerRegistry.protect(service_name: 'openai') { call_api }
#
#   # Check availability
#   Ai::CircuitBreakerRegistry.service_available?('openai')
#
#   # Get health summary
#   Ai::CircuitBreakerRegistry.health_summary
#
class Ai::CircuitBreakerRegistry
  SERVICE_CATEGORIES = {
    ai_providers: %w[openai anthropic ollama google azure groq mistral cohere grok],
    external_apis: %w[stripe paypal sendgrid twilio],
    internal_services: %w[database redis storage]
  }.freeze

  class << self
    def for_provider(provider)
      Ai::ProviderCircuitBreakerService.new(provider)
    end

    def for_service(service_name, config: {})
      get_or_create(service_name, config)
    end

    def protect(service_name:, config: {}, &block)
      breaker = get_or_create(service_name, config)
      breaker.execute_with_circuit_breaker(&block)
    end

    def service_available?(service_name)
      breaker = breakers[service_name]
      return true unless breaker

      breaker.allow_request?
    end

    def get_breaker(service_name)
      breakers[service_name]
    end

    def get_or_create_breaker(service_name, config = {})
      get_or_create(service_name, config)
    end

    def all_stats
      breakers.values.map(&:circuit_stats)
    end

    # PUBLIC NAME. `all_states` is what the AI monitoring API actually calls
    # (Api::V1::Ai::MonitoringController#circuit_breakers); `all_stats` is the
    # internal implementation name. Removing this alias breaks that endpoint.
    alias_method :all_states, :all_stats

    def health_summary
      stats = all_stats
      {
        total_services: stats.length,
        healthy: stats.count { |s| s[:state] == "closed" },
        degraded: stats.count { |s| s[:state] == "half_open" },
        unhealthy: stats.count { |s| s[:state] == "open" },
        services_by_state: stats.group_by { |s| s[:state] },
        last_updated: Time.current.iso8601
      }
    end

    def category_stats(category)
      services = SERVICE_CATEGORIES[category.to_sym] || []
      services.filter_map do |service_name|
        breaker = breakers[service_name]
        breaker&.circuit_stats
      end
    end

    # PUBLIC NAME. `category_states` is what the AI monitoring API actually
    # calls (MonitoringController#category_status / #reset_category);
    # `category_stats` is the internal implementation name. Removing this alias
    # breaks those endpoints.
    alias_method :category_states, :category_stats

    def unhealthy_services
      all_stats.select { |s| s[:state] == "open" }.map { |s| s[:service_name] }
    end

    def health_check
      states = all_stats
      return {} if states.empty?

      states.each_with_object({}) do |state, result|
        result[state[:service_name]] = {
          state: state[:state],
          healthy: state[:state] == "closed",
          failure_count: state[:failure_count] || 0,
          success_count: state[:success_count] || 0,
          last_failure_at: state[:last_failure_time],
          last_success_at: state[:last_success_time]
        }
      end
    end

    def reset_all!
      breakers.each_value(&:reset_circuit!)
      Rails.logger.info "[CircuitBreakerRegistry] Reset all circuit breakers"
    end

    def reset_service!(service_name)
      breaker = breakers[service_name]
      return false unless breaker

      breaker.reset_circuit!
      Rails.logger.info "[CircuitBreakerRegistry] Reset circuit breaker for service: #{service_name}"
      true
    end

    def reset_category!(category)
      services = SERVICE_CATEGORIES[category.to_sym] || []
      services.each do |service_name|
        breaker = get_or_create(service_name)
        breaker.reset_circuit!
      end

      Rails.logger.info "[CircuitBreakerRegistry] Reset circuit breakers for category: #{category}"
    end

    def clear!
      @breakers = {}
    end

    def monitor_and_alert
      summary = health_summary

      alert_unhealthy_services(summary) if summary[:unhealthy] > 0
      alert_degraded_services(summary) if summary[:degraded] > 0

      summary
    end

    private

    def breakers
      @breakers ||= {}
    end

    def get_or_create(service_name, config = {})
      breakers[service_name] ||= build_breaker(service_name, config)
    end

    def build_breaker(service_name, config)
      breaker = Object.new.extend(CircuitBreakerCore)
      callback = method(:broadcast_state_change)

      breaker.define_singleton_method(:on_state_change) do |old_state, new_state|
        callback.call(service_name, old_state, new_state)
      end

      breaker.send(:setup_circuit_breaker,
        resource_id: service_name,
        service_name: service_name,
        config: config
      )

      breaker
    end

    def broadcast_state_change(service_name, old_state, new_state)
      ActionCable.server.broadcast(
        "ai_monitoring_channel",
        {
          type: "circuit_breaker_state_change",
          service: service_name,
          old_state: old_state,
          new_state: new_state,
          timestamp: Time.current.iso8601
        }
      )
    rescue StandardError => e
      Rails.logger.error "[CircuitBreakerRegistry] Failed to broadcast: #{e.message}"
    end

    def alert_unhealthy_services(summary)
      unhealthy = summary[:services_by_state]["open"] || []
      Rails.logger.error "[CircuitBreakerRegistry] ALERT: #{unhealthy.length} services unhealthy"

      ActionCable.server.broadcast(
        "ai_monitoring_channel",
        {
          type: "circuit_breaker_alert",
          severity: "high",
          message: "#{unhealthy.length} services have open circuit breakers",
          services: unhealthy.map { |s| s[:service_name] },
          timestamp: Time.current.iso8601
        }
      )
    rescue StandardError => e
      Rails.logger.error "[CircuitBreakerRegistry] Failed to alert: #{e.message}"
    end

    def alert_degraded_services(summary)
      degraded = summary[:services_by_state]["half_open"] || []
      Rails.logger.warn "[CircuitBreakerRegistry] WARNING: #{degraded.length} services degraded"

      ActionCable.server.broadcast(
        "ai_monitoring_channel",
        {
          type: "circuit_breaker_warning",
          severity: "medium",
          message: "#{degraded.length} services in degraded state",
          services: degraded.map { |s| s[:service_name] },
          timestamp: Time.current.iso8601
        }
      )
    rescue StandardError => e
      Rails.logger.error "[CircuitBreakerRegistry] Failed to alert: #{e.message}"
    end
  end
end
