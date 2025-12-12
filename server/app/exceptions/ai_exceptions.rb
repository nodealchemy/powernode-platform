# frozen_string_literal: true

# Unified exception hierarchy for all AI-related errors
# This module provides consistent error handling across:
# - Backend services (server/app/services/)
# - Worker jobs (worker/app/jobs/)
# - API controllers (server/app/controllers/)
#
# Usage:
#   raise AiExceptions::ValidationError.new("Invalid configuration", details: { field: 'model' })
#   raise AiExceptions::ProviderError.new("API rate limited", provider: 'openai')
#   raise AiExceptions::TimeoutError.new("Request timed out", timeout_seconds: 30)
#
module AiExceptions
  # Base class for all AI-related exceptions
  # All AI exceptions should inherit from this class
  class ServiceError < StandardError
    attr_reader :code, :details, :recoverable

    def initialize(message, code: nil, details: {}, recoverable: true)
      super(message)
      @code = code || "SERVICE_ERROR"
      @details = details
      @recoverable = recoverable
    end

    # Convert exception to hash for API responses
    def to_h
      {
        code: code,
        message: message,
        details: details,
        recoverable: recoverable
      }
    end

    # Convert to JSON for logging
    def to_json(*_args)
      to_h.to_json
    end
  end

  # Validation errors (user input, configuration, schema violations)
  # These are NOT recoverable - user must fix their input
  class ValidationError < ServiceError
    def initialize(message, details: {})
      super(message, code: "VALIDATION_ERROR", details: details, recoverable: false)
    end
  end

  # General execution errors (workflow, agent, processing failures)
  # These may be recoverable with retry
  class ExecutionError < ServiceError
    def initialize(message, details: {})
      super(message, code: "EXECUTION_ERROR", details: details, recoverable: true)
    end
  end

  # Node-specific execution errors within workflows
  # Includes node context for debugging
  class NodeExecutionError < ExecutionError
    attr_reader :node_id, :node_type

    def initialize(message, node_id: nil, node_type: nil, details: {})
      @node_id = node_id
      @node_type = node_type
      super(message, details: details.merge(node_id: node_id, node_type: node_type))
      @code = "NODE_EXECUTION_ERROR"
    end
  end

  # Provider errors (API failures, rate limits, authentication issues)
  # Usually recoverable with backoff/retry
  class ProviderError < ServiceError
    attr_reader :provider

    def initialize(message, provider: nil, details: {})
      @provider = provider
      super(message, code: "PROVIDER_ERROR", details: details.merge(provider: provider), recoverable: true)
    end
  end

  # Timeout errors for long-running operations
  # Usually recoverable with increased timeout
  class TimeoutError < ServiceError
    attr_reader :timeout_seconds

    def initialize(message, timeout_seconds: nil, details: {})
      @timeout_seconds = timeout_seconds
      super(message, code: "TIMEOUT_ERROR", details: details.merge(timeout_seconds: timeout_seconds), recoverable: true)
    end
  end

  # Circuit breaker is open - service is temporarily unavailable
  # Recoverable after circuit breaker timeout
  class CircuitOpenError < ServiceError
    attr_reader :service

    def initialize(message, service: nil, details: {})
      @service = service
      super(message, code: "CIRCUIT_OPEN_ERROR", details: details.merge(service: service), recoverable: true)
    end
  end

  # Recovery operation failed
  # NOT recoverable - manual intervention may be needed
  class RecoveryError < ServiceError
    attr_reader :recovery_strategy

    def initialize(message, recovery_strategy: nil, details: {})
      @recovery_strategy = recovery_strategy
      super(message, code: "RECOVERY_ERROR", details: details.merge(recovery_strategy: recovery_strategy), recoverable: false)
    end
  end

  # Configuration errors (missing credentials, invalid settings)
  # NOT recoverable - requires configuration fix
  class ConfigurationError < ServiceError
    def initialize(message, details: {})
      super(message, code: "CONFIGURATION_ERROR", details: details, recoverable: false)
    end
  end

  # Resource not found errors
  # NOT recoverable - resource doesn't exist
  class NotFoundError < ServiceError
    attr_reader :resource_type, :resource_id

    def initialize(message, resource_type: nil, resource_id: nil, details: {})
      @resource_type = resource_type
      @resource_id = resource_id
      super(
        message,
        code: "NOT_FOUND_ERROR",
        details: details.merge(resource_type: resource_type, resource_id: resource_id),
        recoverable: false
      )
    end
  end

  # Authorization/permission errors
  # NOT recoverable - user needs different permissions
  class AuthorizationError < ServiceError
    attr_reader :required_permission

    def initialize(message, required_permission: nil, details: {})
      @required_permission = required_permission
      super(
        message,
        code: "AUTHORIZATION_ERROR",
        details: details.merge(required_permission: required_permission),
        recoverable: false
      )
    end
  end
end
