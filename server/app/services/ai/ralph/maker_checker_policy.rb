# frozen_string_literal: true

module Ai
  module Ralph
    # G3 — maker/checker policy for a Ralph loop.
    #
    # Resolves the (maker, checker) model pair for the semantic output gate and
    # enforces the SELF-REVIEW BAN: the checker model must NOT be the same as the
    # maker's (the loop executor). This mirrors the agent-team self-review ban in
    # Ai::TeamAuthorityService#authorize_review! — a verifier may not judge its own
    # work — but at the model level for the autonomous loop.
    #
    # Model selection reuses Ai::AgentModelSelector tiers (Ai::ModelTiers) — model
    # names are NEVER hardcoded; the concrete (provider, model) is resolved from the
    # account's credentialed providers per the requested capability tier.
    #
    # All config lives in the loop's `configuration` hash (no migration):
    #   "maker_checker"    => true        # opt-in: run the semantic checker gate
    #   "preset"           => "cheap_explore_strong_verify"  # cheap maker / strong checker
    #   "checker_model"    => "<model-id>" # explicit checker override (optional)
    #   "checker_criteria" => [ ... ]      # optional evaluation criteria for the checker
    class MakerCheckerPolicy
      # The "cheap-explore / strong-verify" preset: the maker (executor) uses a
      # cheap, exploration-friendly tier while the checker uses a strong reasoning
      # tier. Keeps exploration cheap and verification rigorous.
      CHEAP_EXPLORE_STRONG_VERIFY = "cheap_explore_strong_verify"

      # Tiers resolved to concrete models via the selector (never hardcoded ids).
      MAKER_TIER   = :light
      CHECKER_TIER = :reasoning

      # Agent-type profiles to drive the selector's tier preference (see
      # Ai::AgentModelSelector::AGENT_TYPE_PROFILES). The explicit tier requirement
      # overrides the profile default; the agent_type only shapes the soft scoring.
      MAKER_AGENT_TYPE   = "assistant"
      CHECKER_AGENT_TYPE = "code_assistant"

      # @param served_maker_model [String, nil] the model that ACTUALLY served the
      #   maker's (executor's) call for this iteration. When the maker refused and
      #   fell back (e.g. Fable→Opus), this is the fallback model — and it, not the
      #   configured model, is what the self-review ban must compare against.
      def initialize(ralph_loop, served_maker_model: nil)
        @ralph_loop = ralph_loop
        @config = ralph_loop.configuration || {}
        @served_maker_model = served_maker_model.presence
      end

      # Opt-in: the semantic checker gate only runs when explicitly enabled, so
      # flat-rate and metered loops are not forced into extra LLM cost by default.
      def enabled?
        @config["maker_checker"] ? true : false
      end

      def preset
        @config["preset"].to_s
      end

      def cheap_explore_strong_verify?
        preset == CHEAP_EXPLORE_STRONG_VERIFY
      end

      # The maker (executor) model the self-review ban compares against. When the
      # maker's call fell back to another model this iteration, the SERVED-BY model
      # wins — so a Fable→Opus maker fallback can't silently collide with an Opus
      # checker. Absent a served-by signal, falls back to the configured resolution
      # (preset cheap-tier, else the loop executor's resolved model).
      def maker_model
        @maker_model ||= @served_maker_model || configured_maker_model
      end

      def configured_maker_model
        if cheap_explore_strong_verify?
          tier_model(MAKER_TIER, MAKER_AGENT_TYPE) || executor_model
        else
          executor_model
        end
      end

      # The checker (verifier) model. Precedence: explicit config override →
      # a strong (reasoning) tier model. MUST differ from the maker — see
      # #distinct_checker? (the self-review ban).
      def checker_model
        @checker_model ||= (@config["checker_model"].presence || tier_model(CHECKER_TIER, CHECKER_AGENT_TYPE)).presence
      end

      # SELF-REVIEW BAN: a checker may only gate the maker's output when it is a
      # DIFFERENT model. Returns false when no distinct checker can be resolved,
      # in which case the caller must skip the gate rather than let a model grade
      # its own work.
      def distinct_checker?
        checker_model.present? && checker_model != maker_model
      end

      # Agent whose worker LLM client (provider + credentials) backs the checker
      # call. Reuses the loop's executor agent's credentials; the DISTINCT checker
      # MODEL is what satisfies the self-review ban (a different model, same keys).
      def checker_agent_id
        @ralph_loop.default_agent_id
      end

      # Optional evaluation criteria; the evaluator falls back to its own default
      # set (completeness/accuracy/format_compliance/safety) when empty.
      def criteria
        Array(@config["checker_criteria"]).map(&:to_s)
      end

      private

      def executor_model
        @ralph_loop.default_agent&.resolved_model
      end

      # Resolve a concrete model id for a capability tier via the shared selector,
      # so the preset/checker never hardcodes a provider-specific model name.
      def tier_model(tier, agent_type)
        rec = ::Ai::AgentModelSelector.recommend(
          account: @ralph_loop.account,
          agent_type: agent_type,
          requirements: { tier: tier }
        )
        rec && rec[:model]
      rescue StandardError => e
        Rails.logger.warn("[MakerCheckerPolicy] tier model selection failed (#{tier}): #{e.message}")
        nil
      end
    end
  end
end
