# frozen_string_literal: true

module Ai
  # Resolves WHICH ENVIRONMENT a gated operation acts on (Environment campaign,
  # increment 3), so the autonomy gate can vary its verdict by plane.
  #
  # CORE PURITY. The rows that carry an environment — node instances, nodes,
  # templates, pools — belong to an extension, and core cannot name them. The
  # extension therefore registers a resolver under the generic
  # `environment_resolver` provider key (Powernode::ExtensionRegistry) that
  # maps a params hash (`instance_id`, `node_id`, `template_id`, ...) to an
  # Ai::Environment. Core only knows the contract: `.call(account:, params:)`
  # returning an Ai::Environment or nil. No resolver ⇒ nil ⇒ the gate applies
  # no environment overlay, exactly as before this increment.
  #
  # An explicit environment always wins over resolution, so a caller that
  # already knows (a controller acting on one instance, the fleet decision
  # engine acting on a signal) never pays for a lookup or risks a mismatch.
  # An explicit environment that is NOT this account's (a foreign record, an
  # unknown slug) is a ResolverError, not a fall-through to params: a caller
  # that named a plane and got the wrong one must not be gated as if it had
  # named none.
  module EnvironmentResolution
    PROVIDER_KEY = :environment_resolver

    # Raised when the registered resolver itself fails. Deliberately NOT
    # swallowed into nil: "no environment" is exactly the state in which no
    # escalation applies, so a resolver bug that returned nil would silently
    # switch the protected-plane rules off. Every caller's rescue treats this
    # as a refusal (the gate answers :blocked, the executors and fleet gates
    # park for approval).
    class ResolverError < StandardError; end

    module_function

    # @param account [Account]
    # @param params [Hash, nil] the executor params of the operation
    # @param environment [Ai::Environment, String, nil] explicit id/slug/record
    # @return [Ai::Environment, nil]
    def resolve(account:, params: nil, environment: nil)
      unless environment.nil?
        explicit = coerce(account, environment)
        raise ResolverError, "environment #{describe(environment)} is not in this account" if explicit.nil?

        return explicit
      end

      resolver = ::Powernode::ExtensionRegistry.provider(PROVIDER_KEY)
      return nil if resolver.nil? || account.nil?

      found = resolver.call(account: account, params: (params || {}).to_h.with_indifferent_access)
      found.is_a?(::Ai::Environment) && found.account_id == account.id ? found : nil
    rescue ResolverError
      raise
    rescue StandardError => e
      Rails.logger.error("[Ai::EnvironmentResolution] resolver failed: #{e.class}: #{e.message}")
      raise ResolverError, "environment resolver failed: #{e.class}: #{e.message}"
    end

    def describe(value)
      value.is_a?(::Ai::Environment) ? value.slug.inspect : value.to_s.inspect
    end
    private_class_method :describe

    def coerce(account, value)
      case value
      when ::Ai::Environment then value.account_id == account&.id ? value : nil
      when String, Symbol then account && ::Ai::Environment.find_for_account(account.id, value.to_s)
      end
    end
    private_class_method :coerce
  end
end
