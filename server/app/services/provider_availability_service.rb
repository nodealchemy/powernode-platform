# frozen_string_literal: true

# Service to check if AI providers are available and configured before allowing operations
class ProviderAvailabilityService
  class ProviderUnavailableError < StandardError
    attr_reader :provider, :reason

    def initialize(provider, reason)
      @provider = provider
      @reason = reason
      super("Provider '#{provider&.name || 'Unknown'}' is unavailable: #{reason}")
    end
  end

  # Check if a single provider is available for use
  # @param provider [AiProvider] The provider to check
  # @param auto_refresh_health [Boolean] Whether to auto-refresh stale health checks
  # @return [Hash] { available: Boolean, reason: String }
  def self.check_provider(provider, auto_refresh_health: true)
    return { available: false, reason: "Provider not found" } if provider.nil?

    # Check if provider is active
    unless provider.is_active?
      return { available: false, reason: "Provider is inactive" }
    end

    # Check if provider has actual credentials configured (not just schema)
    # Must check ai_provider_credentials, not the credentials method which returns schema as fallback
    unless provider.ai_provider_credentials.where(is_active: true).exists?
      return { available: false, reason: "Provider credentials not configured" }
    end

    # Check if provider is healthy (passed recent health check)
    # Auto-refresh stale health checks before validation
    unless provider.healthy?
      if auto_refresh_health && health_check_stale?(provider)
        Rails.logger.info "Auto-refreshing stale health check for provider: #{provider.name}"
        provider.perform_health_check
      end

      # Re-check after potential refresh
      unless provider.healthy?
        health_error = provider.health_error || "Unknown health issue"
        return { available: false, reason: "Provider is unhealthy: #{health_error}" }
      end
    end

    # Check if provider has available models
    unless provider.available_models.any?
      return { available: false, reason: "No models configured for provider" }
    end

    { available: true, reason: "Provider is available" }
  end

  # Check if a provider's health check is stale (older than 1 hour)
  # @param provider [AiProvider] The provider to check
  # @return [Boolean]
  def self.health_check_stale?(provider)
    health_metrics = provider.metadata&.dig("health_metrics") || {}
    last_check_timestamp = health_metrics["last_check_timestamp"]

    return true unless last_check_timestamp

    last_check = Time.parse(last_check_timestamp) rescue nil
    return true unless last_check

    last_check < 1.hour.ago
  end

  # Check if a provider is available and raise an error if not
  # @param provider [AiProvider] The provider to validate
  # @raise [ProviderUnavailableError] if provider is not available
  def self.validate_provider!(provider)
    result = check_provider(provider)
    raise ProviderUnavailableError.new(provider, result[:reason]) unless result[:available]

    true
  end

  # Check if all providers required by a workflow are available
  # @param workflow [AiWorkflow] The workflow to check
  # @return [Hash] { available: Boolean, unavailable_providers: Array, reasons: Hash }
  def self.check_workflow_providers(workflow)
    # Get all ai_agent nodes from the workflow
    agent_nodes = workflow.ai_workflow_nodes.where(node_type: "ai_agent")

    return { available: true, unavailable_providers: [], reasons: {} } if agent_nodes.empty?

    # Collect all unique provider IDs from agents
    agent_ids = agent_nodes.map { |node| node.configuration["agent_id"] }.compact.uniq
    agents = AiAgent.where(id: agent_ids).includes(:ai_provider)

    unavailable_providers = []
    reasons = {}

    agents.each do |agent|
      provider = agent.ai_provider
      result = check_provider(provider)

      unless result[:available]
        unavailable_providers << {
          provider_id: provider&.id,
          provider_name: provider&.name || "Unknown",
          agent_id: agent.id,
          agent_name: agent.name
        }
        reasons[provider&.id] = result[:reason] if provider
      end
    end

    {
      available: unavailable_providers.empty?,
      unavailable_providers: unavailable_providers,
      reasons: reasons
    }
  end

  # Validate all providers for a workflow and raise error if any are unavailable
  # @param workflow [AiWorkflow] The workflow to validate
  # @raise [ProviderUnavailableError] if any required providers are unavailable
  def self.validate_workflow_providers!(workflow)
    result = check_workflow_providers(workflow)

    unless result[:available]
      first_unavailable = result[:unavailable_providers].first
      provider_name = first_unavailable[:provider_name]
      reason = result[:reasons][first_unavailable[:provider_id]]
      raise ProviderUnavailableError.new(nil, "#{provider_name}: #{reason}")
    end

    true
  end

  # Check if an agent's provider is available
  # @param agent [AiAgent] The agent to check
  # @return [Hash] { available: Boolean, reason: String }
  def self.check_agent_provider(agent)
    return { available: false, reason: "Agent not found" } if agent.nil?
    return { available: false, reason: "Agent has no provider configured" } if agent.ai_provider.nil?

    check_provider(agent.ai_provider)
  end

  # Validate an agent's provider and raise error if unavailable
  # @param agent [AiAgent] The agent to validate
  # @raise [ProviderUnavailableError] if provider is not available
  def self.validate_agent_provider!(agent)
    result = check_agent_provider(agent)
    raise ProviderUnavailableError.new(agent.ai_provider, result[:reason]) unless result[:available]

    true
  end
end
