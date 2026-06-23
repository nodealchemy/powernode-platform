# frozen_string_literal: true

module Ai
  # Single home for model capability-tier classification and supported_models
  # entry normalization. Shared by Ai::AgentModelSelector, Ai::Agent, and
  # Devops::AiConfig so the tier data and the Hash-vs-String handling live in
  # exactly one place (previously duplicated across all three, with Devops and
  # the selector reaching into a constant private to Ai::Agent).
  module ModelTiers
    # Prefix → tier. Tier 1 reasoning (full-power), tier 2 standard
    # (cost-effective), tier 3 light (cheap/local).
    TIERS = {
      reasoning: %w[claude-opus claude-sonnet o3 o3-pro gpt-4o grok-3 grok-4],
      standard:  %w[gpt-4.1-mini gpt-4.1 claude-haiku grok-3-mini o3-mini],
      light:     %w[gpt-4o-mini llama qwen codellama]
    }.freeze

    # Ascending capability order — used to pick the more demanding tier when
    # merging multiple requirements (e.g. an agent's skills).
    ORDER = %i[light standard reasoning].freeze

    module_function

    # Classify a model id by its LONGEST matching prefix, so a more specific lower
    # tier beats a shorter higher-tier prefix — e.g. "gpt-4o-mini" is :light (via
    # "gpt-4o-mini"), not :reasoning (via the shorter "gpt-4o"); likewise
    # "grok-3-mini"/"o3-mini" are :standard, not :reasoning. Unknowns → :standard.
    def classify(model_id)
      mid = model_id.to_s
      best_tier = :standard
      best_len  = -1
      TIERS.each do |tier, prefixes|
        prefixes.each do |prefix|
          next unless mid.start_with?(prefix) && prefix.length > best_len

          best_tier = tier
          best_len  = prefix.length
        end
      end
      best_tier
    end

    # Normalize a supported_models entry (Hash with "id"/"name", or a String)
    # to its model id string. Returns nil for unusable entries.
    def id_for(entry)
      entry.is_a?(Hash) ? (entry["id"] || entry["name"]) : entry
    end

    # The more capable of two tiers (nil-safe), for merging requirements.
    def max_tier(tier_a, tier_b)
      return tier_b&.to_sym if tier_a.nil?
      return tier_a.to_sym if tier_b.nil?

      ORDER.index(tier_a.to_sym).to_i >= ORDER.index(tier_b.to_sym).to_i ? tier_a.to_sym : tier_b.to_sym
    end
  end
end
