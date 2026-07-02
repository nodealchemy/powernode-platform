# frozen_string_literal: true

module Ai
  # Resolves a NON-Fable reasoning-tier fallback model for a Fable/Mythos refusal,
  # dynamically — model ids are NEVER hardcoded (honors the no-hardcoded-model-names
  # convention). Reuses the shared tier classifier (Ai::ModelTiers) and the cost/
  # capability selector (Ai::AgentModelSelector), keeping only :reasoning-tier
  # candidates and dropping the refused model. Fable/Mythos are now :frontier, so
  # the reasoning-tier filter already excludes them; EXCLUDE_PREFIXES stays as a
  # belt-and-suspenders guard (they run the refusal classifier and would just
  # re-trigger it) and to exclude the refused model itself.
  #
  # Called SERVER-side from the provider_config endpoint; the resolved list rides
  # along to the worker's Ai::Llm::RefusalHandler as `fallback_models`.
  class ModelFallbackResolver
    # Fable/Mythos run the refusal classifier — never a valid fallback TARGET.
    # (Also :frontier, so already outside the reasoning-tier candidate set.)
    EXCLUDE_PREFIXES = %w[claude-fable claude-mythos].freeze

    def self.reasoning_fallbacks(account:, agent_type: nil, exclude: nil)
      new(account: account, agent_type: agent_type, exclude: exclude).reasoning_fallbacks
    end

    def initialize(account:, agent_type: nil, exclude: nil)
      @account = account
      @agent_type = (agent_type.presence || "assistant").to_s
      @exclude = Array(exclude).map(&:to_s).reject(&:blank?)
    end

    # Ordered list of non-Fable reasoning-tier model ids to fall back to. The
    # shared selector's top reasoning pick is preferred (so fallback honors the
    # same cost/capability logic as normal selection) when it survives the
    # exclusion filter; the remaining reasoning candidates follow.
    def reasoning_fallbacks
      return [] unless @account

      candidates = enumerate_reasoning_candidates
      return [] if candidates.empty?

      preferred = selector_pick
      ordered = candidates.dup
      ordered.unshift(preferred) if preferred && candidates.include?(preferred)
      ordered.uniq
    end

    private

    def excluded?(model)
      @exclude.include?(model) || EXCLUDE_PREFIXES.any? { |p| model.start_with?(p) }
    end

    def enumerate_reasoning_candidates
      candidate_providers
        .flat_map { |p| Array(p.supported_models) }
        .filter_map { |entry| ::Ai::ModelTiers.id_for(entry) }
        .uniq
        .select { |m| ::Ai::ModelTiers.classify(m) == :reasoning }
        .reject { |m| excluded?(m) }
    end

    # Active, credentialed providers (fall back to all active providers when none
    # are credentialed yet — mirrors Ai::AgentModelSelector#candidate_providers).
    def candidate_providers
      creds = ::Ai::ProviderCredential.where(account_id: @account.id, is_active: true)
                                      .distinct.pluck(:ai_provider_id).to_set
      providers = @account.ai_providers.where(is_active: true).to_a
      providers.select { |p| creds.include?(p.id) }.presence || providers
    end

    def selector_pick
      rec = ::Ai::AgentModelSelector.recommend(
        account: @account, agent_type: @agent_type, requirements: { tier: :reasoning }
      )
      model = rec && rec[:model]
      model.to_s if model.present? && !excluded?(model.to_s)
    rescue StandardError => e
      Rails.logger.warn("[ModelFallbackResolver] selector pick failed: #{e.message}")
      nil
    end
  end
end
