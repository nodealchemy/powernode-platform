# frozen_string_literal: true

module Ai
  # Master switch for Fable-5 CANDIDACY + routing preference (Track A / 2b).
  #
  # DEFAULT OFF. While off, Ai::AgentModelSelector AND Ai::ModelRouterService
  # EXCLUDE claude-fable/claude-mythos from the candidate set entirely — so Fable
  # can never be selected by preference, UCB exploration, empirical score, or a
  # cost tie, even though inc0 registered it in supported_models. (The zero-trial
  # UCB exploration term could otherwise let a not-yet-available model win and hit
  # a failing API.) This keeps Fable NON-SELECTABLE until it is available; an
  # operator flips the switch ON — DB-driven, no deploy — after the live smoke
  # test, which BOTH admits Fable to the candidate pool AND enables the gated
  # preference bonus for allowlisted reasoning agent_types.
  #
  # NOTE: effort mapping (output_config.effort) is LIVE and NOT gated by this
  # switch — it engages for every effort-capable model on deploy.
  #
  # Resolution order (config-driven-config convention):
  #   1. Account#settings["fable_routing_enabled"]  (per-account override)
  #   2. SiteSetting "fable_routing_enabled"        (global default)
  #   3. DEFAULT_ENABLED (false)
  #
  # Thin toggle + settings-reader + model-family detector; selection POLICY
  # (allowlist, bonus, budget/pre-route gates) lives with Ai::AgentModelSelector.
  module FableRouting
    DEFAULT_ENABLED = false
    ENABLED_KEY = "fable_routing_enabled"

    # Fable/Mythos model families — the refusal-classifier, premium-priced,
    # availability-gated models this switch governs. Single source of truth,
    # shared by Ai::AgentModelSelector and Ai::ModelRouterService.
    FABLE_MODEL_PREFIXES = %w[claude-fable claude-mythos].freeze

    module_function

    # Whether a model id belongs to the Fable/Mythos family (prefix-based,
    # mirroring Ai::ModelTiers / Ai::Llm::ModelCapabilities).
    def fable_model?(model_id)
      mid = model_id.to_s
      FABLE_MODEL_PREFIXES.any? { |prefix| mid.start_with?(prefix) }
    end

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
