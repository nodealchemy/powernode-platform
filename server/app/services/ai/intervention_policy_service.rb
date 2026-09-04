# frozen_string_literal: true

module Ai
  class InterventionPolicyService
    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Resolve the effective policy for a given action category and context.
    #
    # Most-specific-wins, decided LEXICOGRAPHICALLY by
    # Ai::InterventionPolicy#specificity_key. The total order, highest first:
    #
    #   1. user_id present            — user+agent > user > agent > global
    #   2. ai_agent_id present        —   (elements 1-2 together)
    #   3. action_category is not "*" — a row naming the category beats a wildcard
    #   4. priority                   — operator's tie-break WITHIN a tier
    #
    # `priority` ranks rows that are otherwise equal and NOTHING more. It cannot
    # promote a row into a tier above its own at any value, which is the whole
    # of IMP-6430e3a8c4a1: while these were additive weights, an unbounded
    # operator-settable `priority` outranked the hierarchy this docstring
    # describes, and the promise above stopped holding as soon as two rows'
    # priorities differed by 5.
    #
    # Orthogonal to all of it, and applied FIRST: the audience cut below, which
    # decides which rows an agent caller may be ranked against at all.
    #
    # @param action_category [String] e.g. "approval", "proposal", "escalation"
    # @param agent [Ai::Agent, nil]
    # @param user [User, nil]
    # @param severity [String, nil] "info", "warning", "critical"
    # @return [Hash] { policy: String, channels: Array, conditions: Hash, record: InterventionPolicy|nil }
    #
    # `record` is the matched InterventionPolicy row (or nil if the default
    # policy was applied). Callers that need to read `record.approval_chain`
    # for chain assignment use this; everyone else can ignore it.
    def resolve(action_category:, agent: nil, user: nil, severity: nil)
      policies = Ai::InterventionPolicy
        .active
        .for_account(account.id)
        .for_category(action_category)
        .by_specificity

      matching = policies.select { |p| p.matches?(action_category: action_category, agent: agent, user: user) }

      return default_policy if matching.empty?

      # CONTRACT (IMP-cb36021d4094, superseding IMP-bfbf8052e179): an agent
      # caller resolves against its OWN rows plus the scope-"global" audience,
      # and never against the operator path.
      #
      # Ai::InterventionPolicy#agent_matches? admits a nil-agent row for ANY
      # caller, so some cut has to happen here. IMP-bfbf8052e179 made it on
      # `ai_agent_id` nil-ness, which is the wrong discriminator:
      # `Ai::InterventionPolicy::SCOPES` names THREE audiences and nil-ness
      # collapses them into two.
      #
      #   scope "agent"       — binds only the agent it names.
      #   scope "action_type" — the operator path (the shape the system
      #                         extension's operator policy sets are written
      #                         at). Agent-less
      #                         callers only: admitting these is what let a
      #                         human-intent row widen agent autonomy, and that
      #                         separation is the part of IMP-bfbf8052e179 that
      #                         was right and must keep holding.
      #   scope "global"      — the account-wide floor. Agent-BINDING by design:
      #                         db/seeds/autonomy_data_seed.rb seeds
      #                         status_update / issue_alert / feedback /
      #                         escalation / proposal / approval here, and
      #                         Ai::AgentOutreachService#notify resolves
      #                         status_update with an agent ALWAYS set.
      #
      # Discarding the global audience broke it in BOTH directions, and the
      # restrictive direction is the one that mattered: a global `auto_approve`
      # degraded to require_approval (fail-safe, merely inconvenient), while a
      # global `block` stopped binding agents at all. That is fail-OPEN even
      # though it looks like a stricter verb — require_approval is not a denial.
      # Ai::AutonomyGate parks it as an ApprovalRequest, and the default chain's
      # ["*"] resolves to every active user, so an operator row meaning "never"
      # became "any user in the account may authorise this".
      #
      # `user_id` is deliberately absent from this test. It narrows the audience
      # a row's `scope` already names rather than naming one of its own
      # (#user_matches? applies it for every caller), and that is what keeps the
      # precedence documented above — user+agent > user > agent > global — true
      # when the caller is an agent.
      #
      # Written as an allowlist on "global" rather than a denylist on
      # "action_type" so that a scope added to SCOPES later is non-binding until
      # someone decides otherwise, and so a malformed scope-"agent" row with a
      # nil ai_agent_id cannot bind every agent in the account.
      if agent
        audience = matching.select { |p| p.ai_agent_id == agent.id || p.scope == "global" }
        return default_policy if audience.empty?

        matching = audience
      end

      # Most specific wins. `by_specificity` above only orders the QUERY (by
      # priority); #specificity_key decides the winner.
      #
      # Exactly one case still falls through to the query order: rows whose keys
      # are IDENTICAL, for which `max_by` keeps the first enumerated. Those rows
      # necessarily share a priority, `by_specificity` has no secondary key, and
      # the table carries no unique index — so the winner between two identical
      # rows with different verbs is whatever Postgres returns first. Pre-existing
      # and narrowed by IMP-6430e3a8c4a1 rather than introduced: while the key was
      # additive, ties spanned DIFFERENT shapes (an agent row at priority 0 scored
      # 7 and tied a global row at priority 5, which `order(priority: :desc)` then
      # handed to the global row) and now they can only span structurally
      # identical ones.
      best = matching.max_by(&:specificity_key)

      # Check severity override: critical always requires_approval unless explicitly auto_approved
      if severity == "critical" && best.policy == "silent"
        return {
          policy: "require_approval",
          channels: best.preferred_channels.presence || %w[notification],
          conditions: best.conditions,
          record: best
        }
      end

      # Check daily notification limit.
      #
      # CONTRACT (IMP-73dff8186c1e): "max_daily_notifications" is a DELIVERY
      # budget, never an authorisation verb. Exhausting it used to return
      # "silent", which Ai::AutonomyGate, System::Fleet::FleetAutonomyService
      # and System::CveOps::CveResponderService each fold into their "block"
      # branch — so a condition reading "stop notifying me this often" turned
      # into a hard 422 refusal of every gated write in the category for the
      # rest of the day, and only on policies an operator had deliberately
      # RELAXED to notify_and_proceed.
      #
      # Degrading to require_approval parks the write for a human (202) on the
      # next-strictest REAL verb.
      #
      # `notifications_suppressed` carries the delivery half to
      # Ai::AgentOutreachService — the one consumer for which "silent" was
      # already doing the right thing. Read the FLAG there, never `channels`: an
      # empty array cannot signal suppression on its own, because every reader
      # applies `.presence || %w[notification]` and would deliver anyway.
      #
      # SCOPE, precisely — the flag suppresses the OUTREACH delivery path only;
      # it does not make the platform quiet, and parking emits a notification of
      # its own. Ai::AutonomyGate#require_approval_or_proceed creates an
      # ApprovalRequest, whose after_create fan-out sends one category-"ai"
      # Notification per approver, and the default chain's ["*"] resolves to
      # every active user. So over the cap a gated write emits MORE
      # notifications than the healthy under-cap path, which emits none (the
      # gate never notifies on :proceed). That one-per-write amplification is
      # ACCEPTED (IMP-e75e843bd42b, weighed and decided): an approval demands
      # action, and suppressing the fan-out would strand the operator's own
      # write in a silent park — worse than the 422 this verb replaced.
      #
      # What is NOT accepted is the feedback: those approval rows used to feed
      # `notification_limit_reached?`'s own count, so the budget was exhausted
      # by traffic it has no way to suppress. Consent traffic is now OUTSIDE
      # the budget on both sides — never throttled by it (unchanged; the
      # notifier does not consult the cap) and never counted toward it (the
      # `approval_request_id` metadata exclusion in the count below). The
      # budget governs outreach; approvals are the product of the verb the
      # budget degrades to, not chatter.
      #
      # Core-mode fork worth knowing: when Ai::ApprovalChain is absent,
      # require_approval falls through to execute_now!, so an over-cap write
      # EXECUTES there instead of parking. Intent-consistent, since the matched
      # row said notify_and_proceed, but it is the one place this verb is less
      # restrictive than "silent" was.
      #
      # CRITICALITY OUTRANKS QUIETNESS (IMP-34beef811fdf). A volume budget may
      # reduce routine chatter; it may never withhold a CRITICAL notification.
      # This branch used to set `notifications_suppressed` without consulting
      # `severity` at all, which contradicted the override directly above it —
      # whose whole stated intent is that a critical event never resolves
      # silently — and Ai::AgentOutreachService#notify honours the flag before
      # it reaches a channel, so a critical event raised over the cap was
      # dropped with no delivery on any channel.
      #
      # The exemption lives HERE, in the producer, rather than in that
      # consumer's flag test: `notifications_suppressed: true` is now
      # unexpressible for a critical severity, so no present or future reader
      # of the flag can re-create the inversion by forgetting to re-check.
      #
      # Only the DELIVERY half is exempted. The verb still degrades to
      # require_approval for every severity, so IMP-73dff8186c1e's
      # authorisation contract — a notification budget parks a gated write, it
      # never refuses one — is unchanged, and the shape returned for a critical
      # event is now exactly the shape the override above returns: a real verb
      # plus audible channels.
      #
      # `reason` distinguishes the two, because
      # Api::V1::Ai::InterventionPoliciesController#resolve renders this hash
      # straight back to an operator previewing a policy: an unqualified "limit
      # reached" next to audible channels and notifications_suppressed:false
      # reads as a contradiction.
      if best.policy == "notify_and_proceed" && notification_limit_reached?(best, user)
        suppress = severity != "critical"

        return {
          policy: "require_approval",
          channels: suppress ? [] : (best.preferred_channels.presence || %w[notification]),
          conditions: best.conditions,
          reason: suppress ? "Daily notification limit reached" : "Daily notification limit reached (critical severity exempt from suppression)",
          notifications_suppressed: suppress,
          record: best
        }
      end

      {
        policy: best.policy,
        channels: best.preferred_channels.presence || %w[notification],
        conditions: best.conditions,
        record: best
      }
    end

    # Check if an action should be auto-approved based on intervention policies.
    # Used by ExecutionGateService to override requires_approval decisions.
    #
    # @return [Boolean]
    def auto_approve?(action_category:, agent: nil, user: nil)
      result = resolve(action_category: action_category, agent: agent, user: user)
      result[:policy] == "auto_approve"
    end

    # Check if an action should be blocked.
    def blocked?(action_category:, agent: nil, user: nil)
      result = resolve(action_category: action_category, agent: agent, user: user)
      result[:policy] == "block"
    end

    private

    def default_policy
      {
        policy: "require_approval",
        channels: %w[notification],
        conditions: {},
        record: nil
      }
    end

    # The count measures what the budget can govern: agent OUTREACH.
    #
    # Approval consent traffic is excluded (IMP-e75e843bd42b) — the
    # `approval_request_id` metadata key marks it, written unconditionally by
    # Ai::ApprovalRequestNotifier#notify_current_step! at the single fan-out
    # site. That key is the PRODUCER's declaration; the handler-supplied
    # notification_type ("autonomy_approval_required" from the default
    # content provider) is deliberately not the discriminator, because
    # SOURCE_HANDLERS lets an extension substitute its own type and its
    # fan-out must stay excluded too. `->>` because the column is json, not
    # jsonb.
    #
    # Why excluded: the budget cannot SUPPRESS those rows — the notifier
    # never consults it, by design (an approval demands action; suppressing
    # it strands the parked write) — so counting them let traffic the cap
    # has no lever over exhaust it. Worst at the default policy
    # (require_approval, no cap involvement at all): a day of ordinary
    # consent activity burned the outreach budget of users who had received
    # no outreach, and past the cap the parking fan-out inflated the very
    # count that keeps the cap exhausted.
    def notification_limit_reached?(policy, user)
      max_daily = policy.conditions["max_daily_notifications"]
      return false unless max_daily && user

      today_count = Notification
        .where(account_id: account.id, user_id: user.id)
        .where("created_at >= ?", Time.current.beginning_of_day)
        .where(category: "ai")
        .where("(metadata ->> 'approval_request_id') IS NULL")
        .count

      today_count >= max_daily
    end
  end
end
