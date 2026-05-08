# frozen_string_literal: true

module Ai
  module Provisioning
    # Per-account daily LLM spend cap.
    #
    # Provisioning's chat experience can fan out into many LLM round-trips
    # (intent capture, refinement, plan composition). On a free tier or a
    # misconfigured account that adds up to runaway tokens fast. CostCapGuard
    # is the single seam every LLM-touching service in this slice consults
    # before making a call.
    #
    # ## Cap resolution
    #
    # 1. Explicit `max_spend_usd_per_day:` argument (test/override).
    # 2. `account.active_subscription.plan.limits["max_llm_spend_per_day_usd"]`
    #    — populated by Slice C's billing limits work.
    # 3. Hard fallback of $0.50/day (free-tier default; matches the M1
    #    "fast bootstrapping with safety rails" goal in the plan).
    #
    # ## Spend lookup
    #
    # We sum `Ai::CostAttribution#amount_usd` for the account on the current
    # `attribution_date`. This already covers every LLM round-trip the
    # platform attributes today (workflow / agent / execution / etc.).
    #
    # ## Result
    #
    #   ok?           — call may proceed; payload[:remaining] is what's left
    #   cap_exceeded? — caller should bail out and surface an upgrade prompt;
    #                   payload[:spent] / payload[:cap] feed UpgradeRequiredCard.
    class CostCapGuard
      DEFAULT_DAILY_CAP_USD = 0.50

      Result = Struct.new(:status, :payload, keyword_init: true) do
        def cap_exceeded?
          status == :cap_exceeded
        end

        def ok?
          status == :ok
        end
      end

      # @param account [Account]
      # @param max_spend_usd_per_day [Float, nil] explicit override; bypasses
      #   plan-limit resolution when present.
      # @return [Result]
      def self.allow?(account:, max_spend_usd_per_day: nil)
        cap = resolve_cap(account, max_spend_usd_per_day)
        spent = spent_today(account)

        if spent >= cap
          Result.new(status: :cap_exceeded, payload: { spent: spent, cap: cap, remaining: 0.0 })
        else
          Result.new(status: :ok, payload: { spent: spent, cap: cap, remaining: cap - spent })
        end
      end

      def self.resolve_cap(account, override)
        return override.to_f if override

        plan_cap = account
                   &.try(:active_subscription)
                   &.try(:plan)
                   &.try(:limits)
                   &.dig("max_llm_spend_per_day_usd")
                   .to_f

        plan_cap.zero? ? DEFAULT_DAILY_CAP_USD : plan_cap
      end
      private_class_method :resolve_cap

      def self.spent_today(account)
        return 0.0 unless account&.id

        ::Ai::CostAttribution
          .where(account_id: account.id, attribution_date: Date.current)
          .sum(:amount_usd)
          .to_f
      end
      private_class_method :spent_today
    end
  end
end
