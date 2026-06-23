# frozen_string_literal: true

module Ai
  # Picks the best (provider, model) pair for a new agent based on its
  # agent_type, the account's enabled providers, each model's declared
  # capabilities (from Ai::Provider#supported_models JSONB), and — when
  # data is available — historical success_rate from Ai::ProviderMetric.
  #
  # Used by Ai::ConciergeService#create_agent_from_spec when persisting
  # new agents proposed by DesignAgentTeamFromIntentExecutor.
  #
  # Scoring blend (per candidate model):
  #   * +1.0 if all required capabilities present (else 0; eligible set
  #          falls back to all when nothing matches required strictly).
  #   * +0.5 × preferred_capability_match_ratio
  #   * +0.25 tier_bonus when model's capability tier matches profile's
  #          desired tier (reasoning / standard / light — see Ai::ModelTiers).
  #   * +cost_bonus (cheaper is better; capped at +0.3).
  #   * +0.4 × empirical_success_rate from ProviderMetric.model_breakdown
  #          (30-day window, min 5 requests). Defaults to 0.5 when absent
  #          so cold-start doesn't permanently disadvantage new models.
  class AgentModelSelector
    AGENT_TYPE_PROFILES = {
      "assistant"         => { required: %w[text_generation chat], preferred: %w[function_calling],                              tier: :standard },
      "code_assistant"    => { required: %w[text_generation chat], preferred: %w[code_generation extended_thinking function_calling], tier: :reasoning },
      "data_analyst"      => { required: %w[text_generation chat], preferred: %w[function_calling extended_thinking vision],     tier: :reasoning },
      "content_generator" => { required: %w[text_generation chat], preferred: %w[],                                              tier: :standard },
      "image_generator"   => { required: %w[image_generation],     preferred: %w[],                                              tier: :standard },
      "monitor"           => { required: %w[text_generation chat], preferred: %w[function_calling],                              tier: :standard },
      "mcp_client"        => { required: %w[function_calling],     preferred: %w[chat extended_thinking],                        tier: :standard }
    }.freeze

    EMPIRICAL_WINDOW    = 30.days
    EMPIRICAL_MIN_RUNS  = 5
    EMPIRICAL_DEFAULT   = 0.5

    def self.recommend(account:, agent_type:, role: nil, description: nil, requirements: {}, provider: nil)
      new(account: account, agent_type: agent_type, role: role, description: description,
          requirements: requirements, provider: provider).recommend
    end

    def initialize(account:, agent_type:, role: nil, description: nil, requirements: {}, provider: nil)
      @account = account
      @agent_type = agent_type.to_s
      @role = role.to_s
      @description = description.to_s
      # Per-skill/context model fit (e.g. Ai::Skill#model_requirements):
      # { capabilities: [hard gates], preferred: [...], tier: :reasoning }.
      @requirements = (requirements || {}).symbolize_keys
      # Optional provider constraint — an Ai::Provider or provider_type string.
      # When set, selection is confined to that provider (e.g. Devops::AiConfig,
      # which is provider-specific); nil ⇒ pick across all credentialed providers.
      @provider = provider
    end

    def recommend
      profile = merge_requirements(AGENT_TYPE_PROFILES[@agent_type] || AGENT_TYPE_PROFILES["assistant"])
      candidates = enumerate_candidates
      return fallback if candidates.empty?

      scored = candidates.map { |c| score(c, profile) }

      # Hard-filter to candidates satisfying required capabilities; degrade
      # gracefully to the full set when nothing matches (e.g. no model in
      # the account declares function_calling, but we still want to pick
      # *something* rather than crash).
      eligible = scored.select { |c| c[:req_satisfied] }
      eligible = scored if eligible.empty?

      best = eligible.max_by { |c| c[:total_score] }
      {
        provider:      best[:provider],
        model:         best[:model_id],
        provider_type: best[:provider].provider_type,
        reason:        build_reason(best, profile),
        score_details: best.except(:provider)
      }
    end

    private

    # Fold per-skill/context model_requirements into the agent_type profile:
    # the skill's required capabilities ADD to the hard gate (an incapable model
    # gets filtered out), preferred capabilities add to the soft preference, and
    # an explicit tier overrides the profile default. No requirements => unchanged.
    def merge_requirements(profile)
      return profile if @requirements.blank?

      {
        required:  (Array(profile[:required])  + Array(@requirements[:capabilities])).uniq,
        preferred: (Array(profile[:preferred]) + Array(@requirements[:preferred])).uniq,
        tier:      (@requirements[:tier].presence&.to_sym || profile[:tier])
      }
    end

    def enumerate_candidates
      candidate_providers.flat_map do |provider|
        Array(provider.supported_models).filter_map do |entry|
          model_id = ::Ai::ModelTiers.id_for(entry)
          next nil if model_id.blank?

          hash = entry.is_a?(Hash) ? entry : {}
          {
            provider:     provider,
            model_id:     model_id,
            capabilities: Array(hash["capabilities"]),
            cost_input:   hash.dig("cost_per_1k_tokens", "input").to_f,
            tier:         ::Ai::ModelTiers.classify(model_id)
          }
        end
      end
    end

    # Providers to score: the constrained provider when one is given
    # (Devops::AiConfig), else all active providers that have an active credential
    # — falling back to all active providers when none are credentialed yet
    # (fresh setup), so a brand-new account can still get a recommendation.
    def candidate_providers
      if @provider
        prov = constraint_provider
        return prov ? [ prov ] : []
      end

      providers = @account.ai_providers.where(is_active: true).to_a
      credentialed = ::Ai::ProviderCredential.where(account_id: @account.id, is_active: true)
                                             .distinct.pluck(:ai_provider_id).to_set
      providers.select { |p| credentialed.include?(p.id) }.presence || providers
    end

    def constraint_provider
      return @provider if @provider.is_a?(::Ai::Provider)

      @account.ai_providers.active.find_by(provider_type: @provider.to_s) ||
        @account.ai_providers.find_by(provider_type: @provider.to_s)
    end

    # Confidence-weighted scoring. Static priors (tier match, cost, profile
    # fit) dominate when we have no empirical signal; empirical evidence
    # progressively overrides priors as the sample size grows. By N=30
    # runs the empirical signal carries up to ~1.2 score weight — enough
    # to swing decisions away from the cold-start default even when a
    # rival candidate has tier and cost advantages.
    EMPIRICAL_FULL_CONFIDENCE_SAMPLE = 30

    def score(c, profile)
      req_satisfied = (profile[:required] - c[:capabilities]).empty?
      pref_match    = profile[:preferred].empty? ? 0.5 : (profile[:preferred] & c[:capabilities]).size.to_f / profile[:preferred].size
      tier_bonus    = c[:tier] == profile[:tier] ? 0.25 : 0.0
      cost_bonus    = c[:cost_input].positive? ? (0.005 / c[:cost_input]).clamp(0.0, 0.3) : 0.1

      empirical_data = empirical_signal(c[:provider], c[:model_id])
      empirical      = empirical_data[:rate] || EMPIRICAL_DEFAULT
      confidence     = empirical_data[:confidence]  # 0..1
      empirical_weight = 0.4 + (confidence * 1.0)   # 0.4 cold-start → 1.4 fully confident

      total = (req_satisfied ? 1.0 : 0.0) +
              (pref_match * 0.5) +
              tier_bonus +
              cost_bonus +
              (empirical * empirical_weight)

      c.merge(
        req_satisfied:    req_satisfied,
        pref_match_score: pref_match.round(3),
        tier_bonus:       tier_bonus,
        cost_bonus:       cost_bonus.round(3),
        empirical_score:  empirical.round(3),
        empirical_n:      empirical_data[:n],
        empirical_weight: empirical_weight.round(3),
        total_score:      total.round(3)
      )
    end

    # Reads from Ai::AgentModelPerformance — populated by
    # Ai::AgentExecution#record_model_performance after each agent run
    # completes or fails. Returns the rate AND the sample count so the
    # caller can confidence-weight the signal (cold-start should not let
    # a 1-run 100%-success record override a 50-run 65% record).
    # Strictly same-agent_type empirical history. Cross-type transfer is
    # deliberately not used — a model that handles code_assistant work
    # well may struggle on data_analyst or content_generator, and we
    # don't want false-positive signals biasing the selector.
    def empirical_signal(provider, model_id)
      record = ::Ai::AgentModelPerformance
               .find_by(account: @account, provider: provider, model: model_id, agent_type: @agent_type)
      return { rate: nil, n: 0, confidence: 0.0 } unless record

      n    = record.total_runs
      rate = record.success_rate  # nil if n < MIN_SAMPLE_FOR_SIGNAL

      # Confidence stays at 0 until we cross MIN_SAMPLE_FOR_SIGNAL — otherwise
      # a record with 1–4 runs would partially bias toward 0.5 with non-zero
      # weight, contaminating the cold-start default for a model that
      # genuinely lacks signal.
      confidence = if rate.nil?
                     0.0
                   else
                     (n.to_f / EMPIRICAL_FULL_CONFIDENCE_SAMPLE).clamp(0.0, 1.0)
                   end
      { rate: rate, n: n, confidence: confidence }
    end

    def fallback
      provider = candidate_providers.first ||
                 @account.ai_providers.where(is_active: true).order(priority_order: :asc).first ||
                 @account.ai_providers.order(priority_order: :asc).first
      {
        provider:      provider,
        model:         provider&.default_model,
        provider_type: provider&.provider_type,
        reason:        "fallback: no candidate models for agent_type=#{@agent_type}",
        score_details: nil
      }
    end

    def build_reason(best, profile)
      [
        "agent_type=#{@agent_type}",
        "→ #{best[:provider].provider_type}/#{best[:model_id]}",
        "tier=#{best[:tier]}(want=#{profile[:tier]})",
        "req=#{best[:req_satisfied] ? 'OK' : 'PARTIAL'}",
        "pref_match=#{best[:pref_match_score]}",
        "empirical=#{best[:empirical_score]}",
        "score=#{best[:total_score]}"
      ].join(" ")
    end
  end
end
