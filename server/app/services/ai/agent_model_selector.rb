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
  #          desired tier (light / standard / reasoning / frontier — see Ai::ModelTiers).
  #   * +cost_bonus (cheaper is better; capped at +0.3).
  #   * +(0.4..1.4) × empirical_success_rate from Ai::AgentModelPerformance,
  #          confidence-weighted by sample size. Defaults to 0.5 when absent
  #          so cold-start doesn't permanently disadvantage new models.
  #   * +exploration_bonus — a deterministic UCB term that rewards
  #          under-sampled candidates (see EXPLORATION_COEFFICIENT). This is the
  #          DISCOVERY half of the learning loop: empirical_success_rate exploits
  #          what's proven; the UCB term explores under-tried models (newly added,
  #          newly credentialed, or never selected) so a genuinely better/cheaper
  #          model gets sampled and can win once its own empirical signal grows —
  #          instead of the selector greedily locking onto an early winner.
  #
  # Learning loop: Ai::AgentExecution#record_model_performance feeds outcomes
  # (success / cost / latency) into Ai::AgentModelPerformance after every run;
  # this selector reads that signal (exploit) and adds UCB (explore). Over time
  # the per-(account, agent_type, provider, model) record converges to the best
  # available model for each agent profile without manual model pinning.
  class AgentModelSelector
    # Per-profile desired tier on the 4-tier ladder (Ai::ModelTiers). code_assistant
    # and data_analyst stay :reasoning: the Fable-preference allowlist is DERIVED
    # from the reasoning-tier profiles (see .default_fable_preferred_agent_types),
    # so lowering them to :standard would empty that allowlist and disable frontier
    # routing. Moving everyday profiles to a :standard default (with per-task
    # escalation to reasoning/frontier) is a routing-policy change deferred to the
    # per-task escalation increment, so standard-default agents are never stranded
    # below reasoning in the interim.
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

    # UCB exploration coefficient — how strongly to favor under-sampled models
    # so new / under-tried (possibly better or cheaper) models get DISCOVERED
    # instead of the selector greedily exploiting an early winner. Kept near the
    # tier/cost-bonus magnitude (~0.25–0.3) so it nudges discovery without
    # overriding capability fit or a confident empirical signal. Set to 0 to
    # disable exploration (pure exploitation). ENV-tunable per deployment.
    EXPLORATION_COEFFICIENT = (ENV["AI_MODEL_SELECTOR_EXPLORATION_C"] || 0.3).to_f

    # ---- Fable-5 candidacy + routing preference (gated by Ai::FableRouting) ----
    # Fable/Mythos model-family detection lives in Ai::FableRouting.fable_model?
    # (single source of truth, shared with Ai::ModelRouterService).

    # Agent_types we NEVER steer to Fable even when reasoning-tier: security- or
    # refusal-prone work stays on a non-Fable reasoning model (the inc1 refusal
    # framework handles any refusals; we don't pay the premium to eat a refusal
    # round-trip). Empty today — no profile is security-typed — a forward guard.
    FABLE_SECURITY_EXCLUDED_AGENT_TYPES = %w[].freeze

    # Additive score bump for a Fable/Mythos candidate on an allowlisted
    # agent_type when the framework is enabled. Sized to clear the reasoning-tier
    # field at cold-start yet stay small enough that a sustained empirical-failure
    # signal (or a learned pre-route rule) can still pull selection back off
    # Fable. ENV-tunable per deployment.
    FABLE_PREFERENCE_BONUS = (ENV["AI_FABLE_PREFERENCE_BONUS"] || 0.5).to_f

    # Operator override for the default (derived) Fable-preferred agent_type
    # allowlist — Account#settings[FABLE_AGENT_TYPES_SETTING] = ["code_assistant", ...].
    FABLE_AGENT_TYPES_SETTING = "fable_routing_agent_types"

    # Default Fable-preferred agent_types: DERIVED from the reasoning-tier
    # profiles (so a future reasoning-tier agent_type is auto-included), minus the
    # security/refusal-prone exclusions. Never hardcoded.
    def self.default_fable_preferred_agent_types
      AGENT_TYPE_PROFILES.select { |_type, profile| profile[:tier] == :reasoning }.keys -
        FABLE_SECURITY_EXCLUDED_AGENT_TYPES
    end

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

      # Fable-5 CANDIDACY gate. When the framework is OFF (default), Fable/Mythos
      # are EXCLUDED from the candidate set entirely — so they can't be selected by
      # preference, UCB exploration, empirical score, or a cost tie (inc0 put Fable
      # in supported_models, and the zero-trial UCB term could otherwise let an
      # unavailable model win). The toggle is read ONLY when a Fable candidate is
      # actually present, so non-Fable providers pay nothing and stay unchanged.
      has_fable = candidates.any? { |c| ::Ai::FableRouting.fable_model?(c[:model_id]) }
      if has_fable && !fable_enabled?
        candidates = candidates.reject { |c| ::Ai::FableRouting.fable_model?(c[:model_id]) }
        has_fable = false
      end
      return fallback if candidates.empty?

      # UCB exploration baseline: total observed runs across all candidate arms
      # (this account + agent_type). Under-sampled arms earn an exploration bonus
      # relative to this total — at true cold-start (no arm has any runs) the
      # term is 0 for everyone and the static priors decide.
      total_observed = candidates.sum { |c| empirical_signal(c[:provider], c[:model_id])[:n] }

      # Preference bonus is only relevant when Fable survived into the pool (i.e.
      # the framework is ON). Computed once; nil ⇒ score() adds 0.0.
      fable_ctx = has_fable ? fable_preference_context : nil

      scored = candidates.map { |c| score(c, profile, total_observed: total_observed, fable_ctx: fable_ctx) }

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

      # platform_routable: never the Claude Code-only scope
      # (Ai::ClaudeExport::ExecutionRecorder) — its statistics are real, but no
      # platform credential can serve a run there.
      providers = @account.ai_providers.platform_routable.where(is_active: true).to_a
      credentialed = ::Ai::ProviderCredential.where(account_id: @account.id, is_active: true)
                                             .distinct.pluck(:ai_provider_id).to_set
      providers.select { |p| credentialed.include?(p.id) }.presence || providers
    end

    def constraint_provider
      return @provider if @provider.is_a?(::Ai::Provider)

      @account.ai_providers.platform_routable.active.find_by(provider_type: @provider.to_s) ||
        @account.ai_providers.platform_routable.find_by(provider_type: @provider.to_s)
    end

    # Confidence-weighted scoring. Static priors (tier match, cost, profile
    # fit) dominate when we have no empirical signal; empirical evidence
    # progressively overrides priors as the sample size grows. By N=30
    # runs the empirical signal carries up to ~1.2 score weight — enough
    # to swing decisions away from the cold-start default even when a
    # rival candidate has tier and cost advantages.
    EMPIRICAL_FULL_CONFIDENCE_SAMPLE = 30

    def score(c, profile, total_observed: 0, fable_ctx: nil)
      req_satisfied = (profile[:required] - c[:capabilities]).empty?
      pref_match    = profile[:preferred].empty? ? 0.5 : (profile[:preferred] & c[:capabilities]).size.to_f / profile[:preferred].size
      tier_bonus    = c[:tier] == profile[:tier] ? 0.25 : 0.0
      cost_bonus    = c[:cost_input].positive? ? (0.005 / c[:cost_input]).clamp(0.0, 0.3) : 0.1

      empirical_data = empirical_signal(c[:provider], c[:model_id])
      empirical      = empirical_data[:rate] || EMPIRICAL_DEFAULT
      confidence     = empirical_data[:confidence]  # 0..1
      empirical_weight = 0.4 + (confidence * 1.0)   # 0.4 cold-start → 1.4 fully confident

      exploration = exploration_bonus(empirical_data[:n], total_observed)

      # Fable-5 preference: 0.0 unless the (memoized) context is present AND this
      # candidate is a Fable/Mythos model. Additive — never a hard pick — so the
      # empirical signal / a learned pre-route rule can still overrule it. When the
      # framework is off (default), fable_ctx is nil ⇒ 0.0 ⇒ total is unchanged.
      fable_bonus = (fable_ctx && fable_model?(c[:model_id])) ? fable_ctx[:bonus] : 0.0

      total = (req_satisfied ? 1.0 : 0.0) +
              (pref_match * 0.5) +
              tier_bonus +
              cost_bonus +
              (empirical * empirical_weight) +
              exploration +
              fable_bonus

      result = c.merge(
        req_satisfied:      req_satisfied,
        pref_match_score:   pref_match.round(3),
        tier_bonus:         tier_bonus,
        cost_bonus:         cost_bonus.round(3),
        empirical_score:    empirical.round(3),
        empirical_n:        empirical_data[:n],
        empirical_weight:   empirical_weight.round(3),
        exploration_bonus:  exploration.round(3),
        total_score:        total.round(3)
      )
      # Only surface the key when it actually applied, so the toggle-off path
      # returns exactly the same score_details shape as before.
      result[:fable_bonus] = fable_bonus.round(3) if fable_bonus.positive?
      result
    end

    # UCB1-style exploration term: high for under-sampled arms, decaying as a
    # candidate accrues runs (and rising slowly with the total observed across
    # all arms). Deterministic — no RNG — so selection stays reproducible and
    # testable. Returns 0 at true cold-start (total_observed == 0) so the static
    # priors decide the first pick; thereafter an unsampled arm (candidate_runs
    # == 0) gets the largest bonus, letting it be tried and gather its own
    # empirical signal. A capability-incapable model is never promoted by this:
    # eligibility is filtered on req_satisfied BEFORE the max_by, so exploration
    # only moves selection among models that already clear the hard gate.
    def exploration_bonus(candidate_runs, total_observed)
      return 0.0 if EXPLORATION_COEFFICIENT <= 0.0 || total_observed.to_i <= 0

      EXPLORATION_COEFFICIENT * Math.sqrt(Math.log(total_observed + 1) / (candidate_runs.to_i + 1))
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
      # Memoized — called once for the total_observed sum and once per candidate
      # in score; one DB read per (provider, model) per recommend().
      (@empirical_cache ||= {})[[ provider.id, model_id ]] ||=
        compute_empirical_signal(provider, model_id)
    end

    def compute_empirical_signal(provider, model_id)
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

    # The Fable-5 preference context for this recommend() — memoized so the gate
    # queries run at most once. nil = no preference (add 0.0 in score()).
    def fable_preference_context
      return @fable_preference_context if defined?(@fable_preference_context)

      @fable_preference_context = compute_fable_preference_context
    end

    # Gate order (cheapest first, short-circuiting): master switch → allowlist →
    # budget backstop. When the switch is OFF (default) NOTHING below it runs, so
    # the inert deploy issues zero extra queries and selection is unchanged.
    def compute_fable_preference_context
      return nil unless fable_enabled?
      return nil unless fable_preferred_agent_type?
      # (3) Learned-routing HARD override — an active inc1 pre-route rule that
      # steers this agent_type's Fable usage to a fallback suppresses the
      # preference (checked before the pricier budget SUM).
      return nil if fable_preroute_suppressed?
      # (2c) Cost backstop — account budget >90% consumed ⇒ suppress the premium.
      return nil if fable_budget_exhausted?

      { bonus: FABLE_PREFERENCE_BONUS }
    end

    # (3) Compose with inc1 learned-routing. The refusal framework writes
    # `fable-refusal-preroute:*` Ai::ModelRoutingRule records once a (Fable model,
    # agent_type[, category]) combo refuses past threshold — but those rules had
    # NO consumer on the agent-resolution path. This gives them teeth: an active
    # pre-route rule whose conditions target this agent_type AND match a
    # Fable/Mythos model hard-suppresses the preference, so a learned "Fable keeps
    # refusing this agent_type" always overrides the static preference. Read-only
    # consumption — the rules stay owned by inc1. We match the rule's request_types
    # + model_patterns precisely; refusal_category is intentionally NOT matched
    # (the request's category is unknown at selection time), so suppression spans
    # all categories for that (agent_type, Fable) pair. It is ALSO intentionally
    # Fable-FAMILY-level, not model-exact: a Mythos-refusal rule suppresses the
    # Fable preference and vice-versa (the preference bonus is itself family-wide),
    # erring toward not using a family that has been refusing. The name prefix is
    # backed by a partial unique index, so the scan is cheap.
    def fable_preroute_suppressed?
      self.class.fable_preroute_suppressed?(account: @account, agent_type: @agent_type)
    end

    # Class-level twin of the instance check, so the governed per-task tier router
    # (Ai::Routing::TaskTierResolver) enforces the SAME learned-routing suppression
    # when deciding whether frontier is admissible — one source of truth, no drift.
    def self.fable_preroute_suppressed?(account:, agent_type:)
      matching_fable_preroute_rule(account: account, agent_type: agent_type).present?
    end

    # Returns the actual matched rule (not just the boolean above) so a caller that
    # suppresses on it — Ai::Routing::TaskTierResolver — can link its persisted
    # Ai::RoutingDecision back to the rule via routing_rule_id. Without this link
    # Ai::ModelRoutingRule#record_match!/success_rate never accrued for these
    # rules (nothing ever called RoutingDecision#record_outcome! against them),
    # so the promotion service's own re-evaluation machinery was starved of data.
    def self.matching_fable_preroute_rule(account:, agent_type:)
      ::Ai::ModelRoutingRule.for_account(account).active
                            .where("name LIKE ?", "fable-refusal-preroute:%")
                            .to_a
                            .find { |rule| preroute_rule_targets_fable_for_agent_type?(rule, agent_type) }
    rescue StandardError => e
      Rails.logger.warn("[AgentModelSelector] Fable pre-route check failed: #{e.class}: #{e.message}")
      nil
    end

    def self.preroute_rule_targets_fable_for_agent_type?(rule, agent_type)
      conditions = rule.conditions || {}
      return false unless Array(conditions["request_types"]).map(&:to_s).include?(agent_type.to_s)

      # model_patterns are stored Regexp.escape'd (e.g. "claude\\-fable\\-5"); strip
      # the escapes and prefix-test the Fable/Mythos family.
      Array(conditions["model_patterns"]).any? { |pattern| ::Ai::FableRouting.fable_model?(pattern.to_s.delete("\\")) }
    end

    # Allowlist membership: operator override (Account#settings) when present,
    # else the derived reasoning-tier default.
    def fable_preferred_agent_type?
      self.class.fable_preferred_agent_type?(account: @account, agent_type: @agent_type)
    end

    # Class-level allowlist membership (operator override → derived default), shared
    # with Ai::Routing::TaskTierResolver so frontier admission and Fable-candidacy
    # use the exact same allowlist.
    def self.fable_preferred_agent_type?(account:, agent_type:)
      override = ::Ai::FableRouting.setting(account, FABLE_AGENT_TYPES_SETTING)
      allowlist = override.present? ? Array(override).map(&:to_s) : default_fable_preferred_agent_types
      allowlist.include?(agent_type.to_s)
    end

    # Whether the Fable-5 framework is enabled for this account — memoized so the
    # toggle (and any SiteSetting fallback read) resolves at most once per recommend.
    def fable_enabled?
      return @fable_enabled if defined?(@fable_enabled)

      @fable_enabled = ::Ai::FableRouting.enabled_for?(@account)
    end

    def fable_model?(model_id)
      ::Ai::FableRouting.fable_model?(model_id)
    end

    # Account-level cost backstop, mirroring ModelRouterService#budget_aware_downgrade.
    # Runs ONLY on the otherwise-Fable-eligible path (never on the inert deploy),
    # so the monthly-cost SUM is not paid on every resolution. Best-effort.
    def fable_budget_exhausted?
      self.class.fable_budget_exhausted?(@account)
    end

    # Class-level twin, shared with Ai::Routing::TaskTierResolver's frontier gate.
    def self.fable_budget_exhausted?(account)
      monthly_budget = account.settings&.dig("ai_monthly_budget")
      return false if monthly_budget.blank?

      month_cost = ::Ai::AgentExecution.joins(:agent)
                                       .where(ai_agents: { account_id: account.id })
                                       .where("ai_agent_executions.created_at >= ?", Time.current.beginning_of_month)
                                       .sum(:cost_usd).to_f
      month_cost >= monthly_budget.to_f * 0.9
    rescue StandardError => e
      Rails.logger.warn("[AgentModelSelector] Fable budget check failed: #{e.class}: #{e.message}")
      false
    end

    def fallback
      provider = candidate_providers.first ||
                 @account.ai_providers.platform_routable.where(is_active: true).order(priority_order: :asc).first ||
                 @account.ai_providers.platform_routable.order(priority_order: :asc).first
      model = provider&.default_model
      # Fable-5 candidacy gate (mirrors models_for_tier): never fall back to a
      # Fable/Mythos default_model when the framework is off — pick the provider's
      # first non-Fable supported model instead, so an unavailable model can't leak
      # in through the fallback path.
      if model.present? && ::Ai::FableRouting.fable_model?(model) && !fable_enabled?
        model = first_non_fable_supported_model(provider)
      end
      {
        provider:      provider,
        model:         model,
        provider_type: provider&.provider_type,
        reason:        "fallback: no candidate models for agent_type=#{@agent_type}",
        score_details: nil
      }
    end

    def first_non_fable_supported_model(provider)
      return nil unless provider

      Array(provider.supported_models)
        .filter_map { |entry| ::Ai::ModelTiers.id_for(entry) }
        .reject { |model_id| model_id.blank? || ::Ai::FableRouting.fable_model?(model_id) }
        .first
    end

    def build_reason(best, profile)
      [
        "agent_type=#{@agent_type}",
        "→ #{best[:provider].provider_type}/#{best[:model_id]}",
        "tier=#{best[:tier]}(want=#{profile[:tier]})",
        "req=#{best[:req_satisfied] ? 'OK' : 'PARTIAL'}",
        "pref_match=#{best[:pref_match_score]}",
        "empirical=#{best[:empirical_score]}(n=#{best[:empirical_n]})",
        "explore=#{best[:exploration_bonus]}",
        "score=#{best[:total_score]}"
      ].join(" ")
    end
  end
end
