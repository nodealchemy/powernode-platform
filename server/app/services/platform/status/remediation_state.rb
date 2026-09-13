# frozen_string_literal: true

module Platform
  module Status
    # THE ONE WRITER of Platform::ComponentStatus#remediation (design §4.3:
    # "derived from SignalState, RemediationOutcome, ApprovalRequest and the
    # lane binding — never hand-written").
    #
    # "Never hand-written" is enforced, not merely asserted: a lint spec scans
    # the tree for any other assignment to the column and fails on one. That
    # matters because the column is what the operator screen reads to decide
    # whether anybody is doing anything about a failing component, and a
    # second writer would produce two contradictory answers with no way to
    # tell which is current.
    #
    # ── INPUT ───────────────────────────────────────────────────────────────
    # SIGNAL FACTS, pulled through Platform::Status::SignalSources — plain
    # hashes, never rows. See that file for the shape.
    #
    # ── DERIVATION ──────────────────────────────────────────────────────────
    # Per fact:
    #
    #   stuck                 → stuck
    #   approval_request_id   → awaiting_operator
    #   router says not_actuatable → not_actuatable
    #   last_outcome succeeded → remediated
    #   otherwise             → whatever state the lane reported
    #
    # `stuck` outranks `awaiting_operator` on purpose. A stuck remediation
    # that also has an approval parked is still stuck, and calling it
    # "awaiting operator" would tell the operator the ball is in their court
    # when the real news is that the last attempt did not finish.
    #
    # Across facts, the WORST wins, on an explicit ladder ordered by how much
    # a person has to do:
    #
    #   none < remediated < auto_in_progress < not_actuatable
    #        < awaiting_operator < stuck
    #
    # `not_actuatable` sits above `auto_in_progress` because "a machine is
    # handling it" needs nobody, while "nothing can handle this" eventually
    # needs someone. `remediated` sits just above `none` because it is a
    # closed story, not an open one — but it is not collapsed INTO `none`: a
    # component that was just repaired is a different screen from one nothing
    # ever touched.
    #
    # NO FACTS AT ALL is `none`, not `not_actuatable`. Nothing is signalling,
    # so there is nothing to actuate and nothing to route; reporting
    # `not_actuatable` would put a refusal on every healthy component in the
    # fleet.
    module RemediationState
      CS = ::Platform::ComponentStatus

      # Outcome tokens that mean the last attempt finished the job. Compared
      # after #to_s.downcase, so a source may spell them as symbols.
      SUCCEEDED_OUTCOMES = %w[succeeded success resolved remediated completed].freeze

      RANK = {
        CS::REMEDIATION_NONE => 0,
        CS::REMEDIATION_REMEDIATED => 1,
        CS::REMEDIATION_AUTO_IN_PROGRESS => 2,
        CS::REMEDIATION_NOT_ACTUATABLE => 3,
        CS::REMEDIATION_AWAITING_OPERATOR => 4,
        CS::REMEDIATION_STUCK => 5
      }.freeze

      # The shape written to the column. Listed as a constant so the lint
      # spec, the serializer and the drawer read the same list.
      PAYLOAD_KEYS = %w[state signal_kind fingerprint approval_request_id last_outcome stuck runbook].freeze

      class << self
        # Derive and PERSIST. Returns the payload hash that was written.
        #
        # @param component_status [Platform::ComponentStatus]
        # @param signals [Array<Hash>] signal facts (see SignalSources)
        def derive(component_status, signals:)
          payload = build(component_status, signals: signals)
          write!(component_status, payload)
          payload
        end

        # The derivation with no write. Exposed because a caller that wants to
        # SHOW the state without touching the row (a preview, a spec) must not
        # have to reach for the writer to get it.
        def build(component_status, signals:)
          facts = Array(signals).select { |fact| fact.is_a?(Hash) }.map { |fact| normalize(fact) }
                                .reject { |fact| fact["signal_kind"].blank? }

          return empty_payload if facts.empty?

          # Route ONCE per fact. The route carries both the state input and
          # the runbook, and a lane is a live gate check — asking it twice for
          # one fact is not free and, for a lane that counts its own
          # consultations, is not even idempotent.
          fact, state, route = facts.map { |f| resolve(component_status, f) }
                                    .max_by { |(_f, state, _route)| rank_of(state) }

          payload_for(fact, state, route)
        end

        def rank_of(state)
          RANK.fetch(state.to_s, RANK[CS::REMEDIATION_NOT_ACTUATABLE])
        end

        private

        # THE ONLY ASSIGNMENT to the column anywhere in the tree. Kept as its
        # own one-line method so the lint spec has a single, greppable site to
        # allow, and so a future caller that wants to write must come here and
        # read why it should not.
        def write!(component_status, payload)
          component_status.update!(remediation: payload)
        end

        # => [fact, state, route]. The route is carried out so the runbook it
        # already resolved is reused rather than re-asked for.
        def resolve(component_status, fact)
          route = ::Platform::RemediationRouter.route(component_status, signal_kind: fact["signal_kind"])
          [ fact, state_for(fact, route), route ]
        end

        def state_for(fact, route)
          return CS::REMEDIATION_STUCK if truthy?(fact["stuck"])
          return CS::REMEDIATION_AWAITING_OPERATOR if fact["approval_request_id"].present?
          return CS::REMEDIATION_NOT_ACTUATABLE if route[:state] == CS::REMEDIATION_NOT_ACTUATABLE
          return CS::REMEDIATION_REMEDIATED if succeeded?(fact["last_outcome"])

          # The lane's own word for what is happening. Already validated
          # against REMEDIATION_STATES by the router, which is why this can be
          # trusted straight into a validated column.
          route[:state]
        end

        def payload_for(fact, state, route)
          {
            "state" => state,
            "signal_kind" => fact["signal_kind"],
            "fingerprint" => fact["fingerprint"],
            "approval_request_id" => fact["approval_request_id"],
            "last_outcome" => fact["last_outcome"],
            "stuck" => truthy?(fact["stuck"]),
            "runbook" => route[:runbook]
          }
        end

        def empty_payload
          {
            "state" => CS::REMEDIATION_NONE,
            "signal_kind" => nil,
            "fingerprint" => nil,
            "approval_request_id" => nil,
            "last_outcome" => nil,
            "stuck" => false,
            "runbook" => nil
          }
        end

        def normalize(fact)
          fact.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
        end

        def succeeded?(outcome)
          SUCCEEDED_OUTCOMES.include?(outcome.to_s.downcase)
        end

        # Compared against a token list rather than used for truthiness: a
        # fact that came back through JSON carries "false", which is truthy in
        # Ruby and would mark every such component stuck.
        def truthy?(value)
          return true if value == true
          return false if value == false || value.nil?

          %w[true t yes 1].include?(value.to_s.strip.downcase)
        end
      end
    end
  end
end
