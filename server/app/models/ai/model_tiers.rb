# frozen_string_literal: true

module Ai
  # Single home for model capability-tier classification and supported_models
  # entry normalization. Shared by Ai::AgentModelSelector, Ai::Agent,
  # Ai::ModelRouterService, Ai::Finops::TokenAnalyticsService, and
  # Devops::AiConfig so the tier data, the price ladder, and the Hash-vs-String
  # handling live in exactly one place.
  #
  # Four tiers on the price ladder (ascending):
  #   :light     — Haiku-class, cheapest (~$1/MTok in)
  #   :standard  — Sonnet-class everyday workhorse (~$2-3/MTok in)
  #   :reasoning — Opus-class deep reasoning (~$5/MTok in)
  #   :frontier  — Fable/Mythos-class, availability-gated (~$10/MTok in)
  module ModelTiers
    # Prefix → capability-tier FLOOR. This table is the floor: a family is
    # classified AT LEAST at its prefix tier. When a live Ai::ModelPricing row
    # exists, the price band can only ESCALATE a known family above its floor
    # (never demote it) — so a stale / zero / cheap price row can't misclassify a
    # known premium family downward, while a genuine price rise (e.g. Sonnet's
    # +50% on 2026-09-01) rebalances the tier with no deploy. Unknown families (no
    # prefix match) are driven purely by price, defaulting to :standard when no
    # price is known. NO hardcoded model names beyond family PREFIXES.
    TIERS = {
      frontier:  %w[claude-fable claude-mythos],
      reasoning: %w[claude-opus o3 o3-pro gpt-4o grok-3 grok-4],
      standard:  %w[claude-sonnet gpt-4.1-mini gpt-4.1 grok-3-mini o3-mini],
      light:     %w[gpt-4o-mini claude-haiku llama qwen codellama]
    }.freeze

    # Ascending capability/price order — used to pick the more demanding tier when
    # merging multiple requirements (e.g. an agent's skills) and as the price floor.
    ORDER = %i[light standard reasoning frontier].freeze

    DEFAULT_TIER = :standard

    # Ladder ⇄ router/finops label vocabulary (economy/standard/premium). The DB
    # enum (Ai::TaskComplexityAssessment::RECOMMENDED_TIERS) is 3-valued and stays
    # unchanged; "premium" covers BOTH :reasoning and :frontier — #from_label
    # returns the base ladder tier (:reasoning) and frontier is admitted separately
    # behind the Fable gate (see Ai::ModelRouterService#models_for_tier).
    LABEL_TO_TIER = { "economy" => :light, "standard" => :standard, "premium" => :reasoning }.freeze
    TIER_TO_LABEL = { light: "economy", standard: "standard", reasoning: "premium", frontier: "premium" }.freeze

    # Input-price bands on $/1k tokens (Ai::ModelPricing#input_per_1k), descending;
    # the first threshold met wins. Below the lowest band ⇒ :light.
    PRICE_BANDS = [
      [0.008, :frontier],   # ≥ ~$8/MTok in
      [0.004, :reasoning],  # ≥ ~$4/MTok in
      [0.0015, :standard]   # ≥ ~$1.5/MTok in
    ].freeze

    # Bounded in-process TTL for the price index. Pricing syncs daily, so a short
    # window keeps #classify cheap in scoring loops (one query per window, never a
    # per-candidate query) while still tracking price changes within minutes.
    PRICE_CACHE_TTL_SECONDS = 300

    module_function

    # Classify a model id onto the price ladder. Precedence:
    #   * known family + live price ⇒ max(prefix floor, price band) — price may
    #     only escalate a known family, never demote it.
    #   * known family, no/zero price ⇒ prefix floor.
    #   * unknown family + live price ⇒ price band.
    #   * otherwise ⇒ :standard.
    # Deterministic and cheap (the price index is memoized per process/window).
    def classify(model_id)
      mid = model_id.to_s
      prefix_tier = prefix_classify(mid)
      price_tier  = price_classify(mid)

      if prefix_tier && price_tier
        max_tier(prefix_tier, price_tier)
      else
        prefix_tier || price_tier || DEFAULT_TIER
      end
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

    # Map a router/finops label (economy/standard/premium) to its base ladder tier.
    def from_label(label)
      LABEL_TO_TIER[label.to_s] || DEFAULT_TIER
    end

    # Map a ladder tier to its router/finops label. :frontier folds into "premium"
    # (the label vocabulary tops out at premium).
    def to_label(tier)
      TIER_TO_LABEL[tier&.to_sym] || "standard"
    end

    # Clear the memoized price index. Bounds staleness in-process and gives specs
    # a deterministic reset point.
    def reset_price_cache!
      @price_index = nil
      @price_index_loaded_at = nil
    end

    # Classify by LONGEST matching prefix (a more specific lower tier beats a
    # shorter higher-tier prefix — e.g. "gpt-4o-mini" is :light via "gpt-4o-mini",
    # not :reasoning via "gpt-4o"). Returns nil when nothing matches so #classify
    # can fall through to price / default.
    def prefix_classify(mid)
      best_tier = nil
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

    # Classify by input price band. nil when no positive price is known.
    def price_classify(mid)
      price = price_for(mid)
      return nil if price.nil? || price <= 0

      PRICE_BANDS.each { |threshold, tier| return tier if price >= threshold }
      :light
    end

    # Cheapest known input_per_1k for a model id: exact match, else longest-prefix
    # match against known pricing ids (mirrors Ai::Autonomy::PricingSyncService).
    def price_for(mid)
      index = price_index
      return nil if index.empty?
      return index[mid] if index.key?(mid)

      best = nil
      best_len = -1
      index.each do |key, value|
        next unless mid.start_with?(key) && key.length > best_len

        best = value
        best_len = key.length
      end
      best
    end

    def price_index
      cached = @price_index
      if cached && @price_index_loaded_at &&
         (monotonic_now - @price_index_loaded_at) < PRICE_CACHE_TTL_SECONDS
        return cached
      end

      @price_index = build_price_index
      @price_index_loaded_at = monotonic_now
      @price_index
    end

    # model_id ⇒ lowest input_per_1k across provider rows (cheapest known price for
    # the id). One query, memoized. Any failure (missing table, DB down) degrades
    # to prefix-only classification.
    def build_price_index
      index = {}
      ::Ai::ModelPricing.pluck(:model_id, :input_per_1k).each do |model_id, input_per_1k|
        next if model_id.blank? || input_per_1k.nil?

        price = input_per_1k.to_f
        existing = index[model_id]
        index[model_id] = price if existing.nil? || price < existing
      end
      index
    rescue StandardError => e
      Rails.logger.warn("[Ai::ModelTiers] price index unavailable, using prefix-only: #{e.class}: #{e.message}")
      {}
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
