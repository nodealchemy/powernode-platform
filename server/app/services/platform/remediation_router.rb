# frozen_string_literal: true

module Platform
  # THE REMEDIATION FRONT DOOR (design §5.1).
  #
  # `route` answers one question about one component and one signal kind:
  # "who, if anyone, has claimed the authority to act on this, and what do
  # they say about acting right now?"
  #
  # ── CORE RESOLVES AND REPORTS. IT DOES NOT DECIDE. ──────────────────────
  # Every value in the result except `runbook` comes back verbatim from the
  # lane's #describe. The router computes no budget, resolves no policy,
  # applies no fence, and never calls #proceed!. See
  # Platform::Remediation::Lane for why that boundary is absolute; the short
  # version is that the real gate (consent budget, disruption budget, the
  # INV-1 self-management fence) lives where the actuator lives, and a
  # core-side approximation of it would be a second, weaker gate in front of
  # the real one.
  #
  # The one thing core adds is the runbook, because a runbook is not an
  # authority to act — it is what an operator reads when nobody has one. It
  # is therefore resolved on BOTH branches, including the no-lane branch:
  # `not_actuatable` with no reading material is the least useful screen the
  # plane can produce.
  #
  # ── THE FOUR WAYS THIS ANSWERS ──────────────────────────────────────────
  #   NoLaneForSignal            nothing claims the kind. The default, and for
  #                              the control plane's own components the only
  #                              answer until an extension lane that runs the
  #                              fence claims them.
  #   LaneReportedUnknownState   the lane answered with a state outside
  #                              Platform::ComponentStatus::REMEDIATION_STATES.
  #                              Refused HERE rather than written through,
  #                              because the value lands in a validated jsonb
  #                              column and would otherwise fail at the far
  #                              end of the pipe with nothing naming the lane
  #                              that produced it.
  #   LaneError                  the lane raised. Reported, never swallowed:
  #                              a front door that renders "nothing to do"
  #                              because its lane crashed is worse than one
  #                              that says the lane crashed.
  #   <the lane's own report>    everything else, passed through unchanged —
  #                              INV-1 refusal text included, in the fence's
  #                              own words.
  module RemediationRouter
    NO_LANE            = "NoLaneForSignal"
    UNKNOWN_STATE      = "LaneReportedUnknownState"
    LANE_ERROR         = "LaneError"

    # The keys a lane's report contributes. `runbook` is deliberately absent:
    # it is core's, and a lane that returns one does not get to overwrite the
    # registry's answer (see #route).
    LANE_KEYS = %i[
      state lane_key policy consent disruption environment_ceiling blast_radius can_proceed reason
    ].freeze

    class << self
      # @param component_status [Platform::ComponentStatus]
      # @param signal_kind [String, Symbol]
      # @return [Hash] state:, lane_key:, policy:, consent:, disruption:,
      #   environment_ceiling:, blast_radius:, runbook:, can_proceed:, reason:
      def route(component_status, signal_kind:)
        kind = signal_kind.to_s.strip
        runbook = ::Platform::Runbook::Registry.render(kind)
        lane = ::Platform::Remediation::Registry.lane_for(kind)

        return not_actuatable(runbook, NO_LANE) if lane.nil?

        report = describe_via_lane(lane, component_status, kind)
        return not_actuatable(runbook, LANE_ERROR, lane_key: lane_key_of(lane)) if report == :error

        merge_report(report, lane, runbook)
      end

      private

      # Ask the lane. A raise is caught HERE and nowhere wider, so an
      # exception from the runbook registry or from result assembly still
      # escapes rather than being disguised as a lane fault.
      def describe_via_lane(lane, component_status, kind)
        account = component_status.respond_to?(:account) ? component_status.account : nil
        lane.describe(component_status, kind, account: account)
      rescue StandardError => e
        Rails.logger.error(
          "[Platform::RemediationRouter] lane #{lane.class} raised for #{kind}: #{e.class}: #{e.message}"
        )
        :error
      end

      def merge_report(report, lane, runbook)
        normalized = normalize(report)
        state = normalized[:state].to_s

        unless ::Platform::ComponentStatus::REMEDIATION_STATES.include?(state)
          Rails.logger.error(
            "[Platform::RemediationRouter] lane #{lane.class} reported unknown state #{state.inspect}"
          )
          # THE LANE'S OWN reason SURVIVES THE REFUSAL, in `lane_reason`.
          #
          # `reason` stays the constant, because a caller matching on
          # UNKNOWN_STATE must keep matching and because the operator has to
          # learn the lane is misbehaving. But discarding what the lane said
          # loses the only sentence that explains the component's situation —
          # a lane that reports the gate's `pending` instead of a state rung
          # (the mistake Lane's contract now warns about) also reports
          # "consent budget exhausted", and dropping it leaves the screen
          # saying `not_actuatable` for no visible cause.
          #
          # Reported SEPARATELY rather than merged into `reason`: it came from
          # a lane that just produced a garbage state, so it is evidence, not
          # an authority. nil when the lane offered none.
          return not_actuatable(runbook, UNKNOWN_STATE, lane_key: lane_key_of(lane),
                                lane_reason: normalized[:reason].presence)
        end

        # The lane's report, then the two things core is entitled to fill in:
        # the runbook (always core's) and a lane_key the lane did not bother
        # to name (its own identity, not an invention).
        normalized.merge(
          state: state,
          lane_key: normalized[:lane_key].presence || lane_key_of(lane),
          runbook: runbook
        )
      end

      def not_actuatable(runbook, reason, lane_key: nil, lane_reason: nil)
        {
          state: ::Platform::ComponentStatus::REMEDIATION_NOT_ACTUATABLE,
          lane_key: lane_key,
          lane_reason: lane_reason,
          policy: nil,
          consent: { remaining: nil, budget: nil },
          disruption: {},
          environment_ceiling: nil,
          blast_radius: nil,
          runbook: runbook,
          can_proceed: false,
          reason: reason
        }
      end

      def lane_key_of(lane)
        return nil unless lane.respond_to?(:key)

        lane.key.to_s.presence
      rescue StandardError
        nil
      end

      # Symbol-keyed result, whatever the lane used. A lane written in an
      # extension may hand back string keys (it may have come from JSON), and
      # a router that answered `result[:state]` for one lane and
      # `result["state"]` for another would make every downstream reader carry
      # the ambiguity.
      #
      # Keys OUTSIDE LANE_KEYS are kept: a lane may report extra evidence and
      # the drawer may render it. `runbook` is the one exclusion, dropped
      # before the merge so a lane cannot overwrite core's answer with its own.
      def normalize(report)
        return { state: nil } unless report.is_a?(Hash)

        report.each_with_object({}) do |(k, v), out|
          key = k.to_sym
          next if key == :runbook

          out[key] = v
        end
      end
    end
  end
end
