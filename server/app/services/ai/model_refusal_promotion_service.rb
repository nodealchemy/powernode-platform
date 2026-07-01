# frozen_string_literal: true

module Ai
  # LEARN step of the refusal framework: once a Fable/Mythos (model, agent_type,
  # category) combo has refused often enough within a window, pre-route that
  # (agent_type, category) to the non-Fable fallback by upserting an
  # Ai::ModelRoutingRule — so repeat cases skip Fable entirely instead of paying
  # the refusal→fallback round-trip every time.
  #
  # Runs at RECORD TIME (no cron): invoked from WorkerLlmClient#record_refusal!
  # right after the refusal event is written. Threshold + window are DB-driven
  # (Account#settings) per the config-driven-config convention, with constant
  # fallbacks so it works out of the box.
  class ModelRefusalPromotionService
    DEFAULT_THRESHOLD    = 5
    DEFAULT_WINDOW_HOURS = 24

    def initialize(account_id:)
      @account_id = account_id
      @account = Account.find_by(id: account_id)
    end

    # Upsert a pre-route rule when the refusal count crosses the threshold.
    # Returns the rule when promoted, else nil. Best-effort — never raises into
    # the LLM call path.
    def maybe_promote(model:, agent_type:, category: nil, fallback_model: nil)
      return nil if @account_id.blank?
      return nil if fallback_model.blank? # nothing concrete to pre-route to yet
      # Never pre-route toward the model that just refused — that would send
      # traffic straight back to the refuser.
      return nil if fallback_model.to_s == model.to_s

      count = recent_refusal_count(model: model, agent_type: agent_type, category: category)
      return nil if count < threshold

      upsert_routing_rule(model: model, agent_type: agent_type, category: category, fallback_model: fallback_model)
    rescue StandardError => e
      Rails.logger.warn("[ModelRefusalPromotionService] promote failed: #{e.class}: #{e.message}")
      nil
    end

    # Exposed for observability/tests.
    def threshold
      raw = setting("fable_refusal_promotion_threshold")
      (raw.presence || DEFAULT_THRESHOLD).to_i.clamp(1, 10_000)
    end

    private

    def window
      hours = setting("fable_refusal_promotion_window_hours")
      (hours.presence || DEFAULT_WINDOW_HOURS).to_f.hours
    end

    def setting(key)
      s = @account&.settings
      return nil unless s.is_a?(Hash)

      s[key] || s[key.to_sym]
    end

    def recent_refusal_count(model:, agent_type:, category:)
      Ai::ModelRefusalEvent
        .where(account_id: @account_id, model: model, agent_type: agent_type, category: category)
        .where("created_at >= ?", Time.current - window)
        .count
    end

    # Deterministic name (INCLUDES the refused model so Fable-5 and Mythos-5 don't
    # collapse into one rule) → idempotent upsert. Race-safe: a concurrent insert
    # that wins the unique (account_id, name) index is caught and re-found.
    def upsert_routing_rule(model:, agent_type:, category:, fallback_model:)
      name = "fable-refusal-preroute:#{model}:#{agent_type}:#{category.presence || 'any'}"
      rule = Ai::ModelRoutingRule.find_or_initialize_by(account_id: @account_id, name: name)
      rule.rule_type = "quality_based"
      rule.priority = rule.priority.presence || 100
      rule.is_active = true
      rule.conditions = {
        "request_types" => [agent_type],
        "model_patterns" => [Regexp.escape(model.to_s)],
        "refusal_category" => category.presence
      }.compact
      rule.target = { "model_names" => [fallback_model], "strategy" => "quality_optimized" }
      rule.save!
      Rails.logger.warn(
        "[ModelRefusalPromotionService] pre-routed model=#{model} agent_type=#{agent_type} " \
        "category=#{category || 'any'} → #{fallback_model} (rule=#{name})"
      )
      rule
    rescue ActiveRecord::RecordNotUnique
      # A sibling worker created the same rule concurrently — re-find and refresh.
      existing = Ai::ModelRoutingRule.find_by(account_id: @account_id, name: name)
      existing&.update(target: { "model_names" => [fallback_model], "strategy" => "quality_optimized" })
      existing
    end
  end
end
