# frozen_string_literal: true

module Platform
  module Remediation
    # THE LANE CONTRACT (design §5.1) — the generic seam through which a
    # signal kind acquires something that can actually act on it.
    #
    # A lane is registered against a signal kind by whoever owns that kind:
    #
    #   Platform::Remediation::Registry.register_lane("instance.silent", MyLane.new)
    #
    # Like Platform::Status::Contributor this is a DUCK-TYPE BASE, not a
    # required superclass: the registry accepts anything answering #describe.
    # Subclassing buys the documented defaults and nothing else.
    #
    # ── CORE NEVER CONSTRUCTS A PROCEED ─────────────────────────────────────
    # This is the whole point of the seam, and it is the one rule that cannot
    # be relaxed later without re-opening the hole it exists to close.
    #
    # `Platform::RemediationRouter` RESOLVES a lane and REPORTS what that lane
    # says. It never decides that an action may happen, never computes a
    # budget, never invents a policy, and never calls #proceed!. Everything in
    # its result except the runbook comes back verbatim from #describe.
    #
    # The reason is that the gate a lane runs is not expressible in core. The
    # system extension's lane proceeds by calling its own fleet gate — the
    # same entry its autonomy tick uses — which applies the routed-lane
    # refusal, the consent budget and the INV-1 self-management fence (an
    # instance may not remediate the node that is hosting the control plane
    # deciding to remediate it). Core knows about none of those and must not
    # approximate them: a core-side "can_proceed" computed from a lane's
    # numbers would be a second, weaker gate sitting in front of the real one,
    # and the weaker one is the one that would be trusted.
    #
    # So #proceed! is declared here as documentation of what a lane offers ITS
    # OWN caller, and core has no call site for it. A spec asserts core never
    # calls it.
    #
    # ── WHAT #describe MUST RETURN ──────────────────────────────────────────
    # A Hash. String or symbol keys; the router normalizes. Every key is the
    # lane's statement about itself:
    #
    #   state                 one of Platform::ComponentStatus::REMEDIATION_STATES.
    #                         A state outside that set is refused by the router
    #                         (`LaneReportedUnknownState`) rather than passed on:
    #                         the value is written to a validated jsonb column,
    #                         and an unknown state would fail the model's
    #                         validation at the far end of the pipe, where
    #                         nothing can say which lane produced it.
    #   lane_key              the lane's own identifier, for the drawer and the
    #                         report. Falls back to #key.
    #   policy                the resolved intervention policy, as the lane
    #                         resolved it (e.g. "require_approval").
    #   consent               {remaining:, budget:} — headroom in the lane's own
    #                         consent budget. Core does no arithmetic on these.
    #   disruption            the lane's disruption-budget report, shape owned
    #                         by the lane.
    #   environment_ceiling   the plane ceiling the lane resolved, or nil.
    #   blast_radius          the lane's blast-radius report, or nil.
    #   can_proceed           the LANE's answer, never core's.
    #   reason                why not, when can_proceed is false — the string
    #                         the operator reads. Passed through unchanged: an
    #                         INV-1 refusal must reach the screen in the fence's
    #                         own words, not paraphrased by a router that does
    #                         not know what INV-1 is.
    #
    # Anything else the lane returns is carried through untouched.
    class Lane
      # The lane's identifier. Snake_case, stable; it lands in the router
      # result and in the remediation jsonb, so a rename is a data change.
      def key
        raise NotImplementedError, "#{self.class}#key must return the lane key"
      end

      # The signal kinds this lane claims. ADVISORY ONLY — the registry is
      # keyed by whatever kind #register_lane was called with, because a lane
      # may legitimately be registered for a kind it did not enumerate (a
      # catch-all lane, an operator override). Useful for introspection and
      # for a registrar that wants to loop.
      def signal_kinds
        []
      end

      # @param component_status [Platform::ComponentStatus] the component the
      #   signal is about
      # @param signal_kind [String] the kind being routed
      # @param account [Account, nil] the component's account; nil for a
      #   shared (non-account-scoped) component
      # @return [Hash] see "WHAT #describe MUST RETURN" above
      def describe(_component_status, _signal_kind, account: nil)
        raise NotImplementedError, "#{self.class}#describe must report the lane's own gate state"
      end

      # NEVER CALLED BY CORE. Declared so a lane's own caller — the extension
      # that registered it, its autonomy tick, its operator endpoint — has a
      # documented name for the act, and so that this file states plainly
      # where the actuation boundary is.
      #
      # A lane that does not implement it is not broken; it is advisory.
      def proceed!(_component_status, _signal_kind, account: nil, **_options)
        raise NotImplementedError,
              "#{self.class}#proceed! is the LANE's own actuator; core never calls it"
      end
    end
  end
end
