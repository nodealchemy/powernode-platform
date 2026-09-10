# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # Shared mapping from a SOURCE ENUM VALUE to one typed condition.
      #
      # Every contributor in this directory normalizes one or more enum-like
      # columns (`Devops::DockerHost::STATUSES`, `Ai::CircuitBreaker::STATES`,
      # …) into conditions. The mechanical part is identical everywhere and the
      # part that matters is not:
      #
      #   - the TABLE (which value means held, which means down) is per kind
      #     and lives in the contributor, where it can be read next to the
      #     model it describes;
      #   - the MISS BEHAVIOUR is the same everywhere and lives here, because
      #     it is the one rule no contributor may get wrong.
      #
      # ── WHY AN UNRECOGNISED VALUE IS NEVER `ok` ─────────────────────────────
      # A source grows a status value; the contributor's table does not. If the
      # miss fell through to "healthy" the screen would report green for a state
      # nobody has ever reasoned about — the exact failure this plane exists to
      # prevent. So a miss is `status: "unknown"` with reason `UnknownStatus`,
      # which the ladder renders as `not_measured`: visibly a gap, never a pass.
      # The raw value travels in `evidence` so the operator (and a spec) can see
      # WHICH value was unrecognised.
      #
      # This module is NOT a contributor and carries no `KIND`;
      # Contributors.register_all! skips it for exactly that reason.
      module EnumConditions
        # The single reason token for "the source said something we do not
        # model". Greppable on purpose: one grep finds every unmapped value
        # across every kind.
        UNKNOWN_REASON = "UnknownStatus"

        # @param value [String, Symbol, nil] the raw enum value off the record
        # @param table [Hash{String=>Hash}] value => {type:, status:, reason:,
        #   severity:, message:}
        # @param unknown_type [String] the condition type to use when the value
        #   is unrecognised — the contributor's own primary type, so the miss
        #   lands on the same row of the drawer as a hit would
        # @param evidence [Hash, nil] the raw fields the reason came from
        def enum_condition(value, table:, unknown_type:, evidence: nil)
          key = value.to_s
          spec = table[key]

          return unknown_condition(key, unknown_type, evidence) if spec.nil?

          Condition.build(
            type: spec.fetch(:type, unknown_type),
            status: spec.fetch(:status),
            reason: spec.fetch(:reason),
            message: spec[:message],
            severity: spec[:severity],
            evidence: evidence
          )
        end

        # The set of values a table claims to cover. Specs assert this equals
        # the source model's own constant, so a value added to the model with
        # no mapping here turns the spec red rather than turning the screen
        # green.
        def mapped_values(table)
          table.keys.map(&:to_s).sort
        end

        private

        def unknown_condition(key, unknown_type, evidence)
          Condition.build(
            type: unknown_type,
            status: Condition::UNKNOWN,
            reason: UNKNOWN_REASON,
            message: "unrecognised source status #{key.inspect}",
            evidence: (evidence || {}).merge("unmapped_value" => key)
          )
        end
      end
    end
  end
end
