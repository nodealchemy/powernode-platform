# frozen_string_literal: true

module Ai
  # Master switch for the Fable-5 runtime onboarding framework (Track A:
  # model-routing preference + effort mapping).
  #
  # DEFAULT OFF — the framework deploys INERT. With the switch off, model
  # selection (Ai::AgentModelSelector) and request effort (output_config.effort)
  # behave EXACTLY as before Fable onboarding: no agent routes to Fable, no
  # effort param is populated anywhere. An operator flips it ON — DB-driven, no
  # deploy — after the live Fable smoke test once Fable is available.
  #
  # Resolution order (config-driven-config convention):
  #   1. Account#settings["fable_routing_enabled"]  (per-account override)
  #   2. SiteSetting "fable_routing_enabled"        (global default)
  #   3. DEFAULT_ENABLED (false)
  #
  # This is a thin toggle + settings-reader module; selection POLICY (allowlist,
  # bonus, budget/pre-route gates) lives with Ai::AgentModelSelector, and effort
  # POLICY lives with Ai::Ralph::TaskExecutor — both consult this switch first.
  module FableRouting
    DEFAULT_ENABLED = false
    ENABLED_KEY = "fable_routing_enabled"

    module_function

    # Whether the Fable-5 framework is enabled for the given account. Nil-safe
    # (a nil/settings-less account resolves to the global default, then false).
    def enabled_for?(account)
      val = account_setting(account, ENABLED_KEY)
      return truthy?(val) unless val.nil?

      global = global_setting(ENABLED_KEY)
      return global unless global.nil?

      DEFAULT_ENABLED
    end

    # Read an arbitrary Account#settings key (string OR symbol), nil when absent.
    # Used by the selector for the operator-overridable agent-type allowlist.
    def setting(account, key)
      account_setting(account, key)
    end

    def account_setting(account, key)
      settings = account.respond_to?(:settings) ? account.settings : nil
      return nil unless settings.is_a?(Hash)

      settings.key?(key.to_s) ? settings[key.to_s] : settings[key.to_sym]
    end

    def global_setting(key)
      SiteSetting.get(key)
    rescue StandardError
      nil
    end

    def truthy?(value)
      return value if value == true || value == false

      %w[true 1 yes on].include?(value.to_s.strip.downcase)
    end
  end
end
