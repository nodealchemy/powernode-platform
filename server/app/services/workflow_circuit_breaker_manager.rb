# frozen_string_literal: true

class WorkflowCircuitBreakerManager
  # Service categories for circuit breakers
  SERVICE_CATEGORIES = {
    ai_providers: %w[openai anthropic ollama],
    external_apis: %w[stripe paypal sendgrid twilio],
    internal_services: %w[database redis storage],
    workflow_nodes: [] # Dynamic based on workflow configuration
  }.freeze

  class << self
    # Execute a block with circuit breaker protection for a specific service
    def protect(service_name:, config: {}, &block)
      breaker = get_or_create_breaker(service_name, config)
      breaker.execute(&block)
    end

    # Check if a service is available (circuit closed or half-open)
    def service_available?(service_name)
      breaker = get_breaker(service_name)
      return true unless breaker # No breaker = always available

      breaker.allow_request?
    end

    # Get circuit breaker for a service
    def get_breaker(service_name)
      @breakers ||= {}
      @breakers[service_name]
    end

    # Get or create circuit breaker for a service
    def get_or_create_breaker(service_name, config = {})
      @breakers ||= {}
      @breakers[service_name] ||= WorkflowCircuitBreakerService.new(
        service_name: service_name,
        config: config
      )
    end

    # Get all circuit breaker states
    def all_states
      WorkflowCircuitBreakerService.all_states
    end

    # Get states for a specific category
    def category_states(category)
      services = SERVICE_CATEGORIES[category.to_sym] || []
      services.map do |service_name|
        breaker = get_breaker(service_name)
        breaker ? breaker.stats : nil
      end.compact
    end

    # Get health summary across all circuit breakers
    def health_summary
      states = all_states

      {
        total_services: states.length,
        healthy: states.count { |s| s[:state] == 'closed' },
        degraded: states.count { |s| s[:state] == 'half_open' },
        unhealthy: states.count { |s| s[:state] == 'open' },
        services_by_state: states.group_by { |s| s[:state] },
        last_updated: Time.current.iso8601
      }
    end

    # Reset all circuit breakers
    def reset_all!
      all_states.each do |state|
        breaker = get_or_create_breaker(state[:service_name])
        breaker.reset!
      end

      Rails.logger.info '[CircuitBreakerManager] Reset all circuit breakers'
    end

    # Reset circuit breakers for a specific category
    def reset_category!(category)
      services = SERVICE_CATEGORIES[category.to_sym] || []
      services.each do |service_name|
        breaker = get_or_create_breaker(service_name)
        breaker.reset!
      end

      Rails.logger.info "[CircuitBreakerManager] Reset circuit breakers for category: #{category}"
    end

    # Execute node with circuit breaker protection
    def execute_node_with_protection(node_execution, &block)
      node_type = node_execution.ai_workflow_node.node_type
      service_name = determine_service_name(node_execution)
      config = extract_circuit_breaker_config(node_execution)

      Rails.logger.info "[CircuitBreakerManager] Executing node #{node_execution.node_id} " \
                        "with circuit breaker protection for #{service_name}"

      protect(service_name: service_name, config: config) do
        block.call
      end
    rescue WorkflowCircuitBreakerService::CircuitOpenError => e
      handle_circuit_open_error(node_execution, service_name, e)
    rescue StandardError => e
      Rails.logger.error "[CircuitBreakerManager] Error executing node with protection: #{e.message}"
      raise
    end

    # Monitor circuit breakers and trigger alerts
    def monitor_and_alert
      summary = health_summary

      # Alert if too many services are unhealthy
      if summary[:unhealthy] > 0
        alert_unhealthy_services(summary)
      end

      # Alert if services are degraded
      if summary[:degraded] > 0
        alert_degraded_services(summary)
      end

      summary
    end

    private

    def determine_service_name(node_execution)
      node = node_execution.ai_workflow_node
      node_type = node.node_type

      case node_type
      when 'ai_agent'
        # Use AI provider as service name
        agent_id = node.configuration['agent_id']
        agent = AiAgent.find_by(id: agent_id)
        provider = agent&.ai_provider&.provider_type || 'unknown_ai_provider'
        "ai_provider:#{provider}"

      when 'api_call'
        # Use API endpoint domain
        url = node.configuration['url']
        domain = extract_domain(url)
        "external_api:#{domain}"

      when 'webhook'
        # Use webhook target
        "webhook:#{node.configuration['webhook_name']}"

      else
        # Generic node type service
        "workflow_node:#{node_type}"
      end
    end

    def extract_domain(url)
      uri = URI.parse(url)
      uri.host || 'unknown'
    rescue StandardError
      'unknown'
    end

    def extract_circuit_breaker_config(node_execution)
      node = node_execution.ai_workflow_node
      workflow = node_execution.ai_workflow_run.ai_workflow

      # Node-level configuration overrides workflow-level
      node_config = node.configuration['circuit_breaker'] || {}
      workflow_config = workflow.configuration['circuit_breaker'] || {}

      workflow_config.merge(node_config).symbolize_keys
    end

    def handle_circuit_open_error(node_execution, service_name, error)
      Rails.logger.error "[CircuitBreakerManager] Circuit open for #{service_name}: #{error.message}"

      # Update node execution with circuit breaker error
      node_execution.update(
        status: 'failed',
        error_type: 'circuit_breaker_open',
        error_details: {
          message: error.message,
          service: service_name,
          circuit_state: 'open',
          timestamp: Time.current.iso8601
        }
      )

      # Check if workflow should be paused due to circuit breaker
      workflow_run = node_execution.ai_workflow_run
      if should_pause_workflow?(workflow_run, service_name)
        pause_workflow(workflow_run, service_name)
      end

      # Re-raise the error
      raise error
    end

    def should_pause_workflow?(workflow_run, service_name)
      # Check workflow configuration for circuit breaker pause policy
      config = workflow_run.ai_workflow.configuration['circuit_breaker'] || {}
      pause_on_open = config['pause_on_open'] != false # Default true

      pause_on_open
    end

    def pause_workflow(workflow_run, service_name)
      Rails.logger.warn "[CircuitBreakerManager] Pausing workflow #{workflow_run.run_id} " \
                        "due to open circuit for #{service_name}"

      workflow_run.update(
        status: 'paused',
        metadata: (workflow_run.metadata || {}).merge(
          'paused_reason' => 'circuit_breaker_open',
          'paused_service' => service_name,
          'paused_at' => Time.current.iso8601
        )
      )

      # Broadcast pause event
      ActionCable.server.broadcast(
        "ai_workflow_run_#{workflow_run.run_id}",
        {
          type: 'workflow_paused',
          reason: 'circuit_breaker_open',
          service: service_name,
          timestamp: Time.current.iso8601
        }
      )
    end

    def alert_unhealthy_services(summary)
      unhealthy = summary[:services_by_state]['open'] || []

      Rails.logger.error "[CircuitBreakerManager] ALERT: #{unhealthy.length} services unhealthy"

      # Broadcast alert
      ActionCable.server.broadcast(
        'ai_monitoring_channel',
        {
          type: 'circuit_breaker_alert',
          severity: 'high',
          message: "#{unhealthy.length} services have open circuit breakers",
          services: unhealthy.map { |s| s[:service_name] },
          timestamp: Time.current.iso8601
        }
      )
    end

    def alert_degraded_services(summary)
      degraded = summary[:services_by_state]['half_open'] || []

      Rails.logger.warn "[CircuitBreakerManager] WARNING: #{degraded.length} services degraded"

      # Broadcast warning
      ActionCable.server.broadcast(
        'ai_monitoring_channel',
        {
          type: 'circuit_breaker_warning',
          severity: 'medium',
          message: "#{degraded.length} services in degraded state",
          services: degraded.map { |s| s[:service_name] },
          timestamp: Time.current.iso8601
        }
      )
    end
  end
end
