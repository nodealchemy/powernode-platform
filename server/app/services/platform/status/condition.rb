# frozen_string_literal: true

module Platform
  module Status
    # A CONDITION is one observed fact about a component (design §4.2).
    #
    #   { type: "Reachable", status: true | false | "unknown",
    #     reason: "HeartbeatStale", message: "no heartbeat for 7m 12s",
    #     severity: "degraded" | "down",
    #     last_transition_at:, observed_at:, observed_generation:,
    #     evidence: { ... } }
    #
    # WHY CamelCase IS ENFORCED, not merely recommended: `type` and `reason`
    # are stable, greppable tokens that a runbook, an alert and a spec all key
    # on. They are also the exact strings that must NEVER reach a
    # status-variant lookup, which lowercases its input and would silently
    # fall through to the default variant — a lowercase reason would render as
    # "unknown" and nobody would see an error. Rejecting them at construction
    # is the only place that failure mode is visible.
    #
    # WHY `last_transition_at` IS COMPUTED HERE: it must mean "when did this
    # condition last CHANGE", not "when did we last look". A sweep runs every
    # 60 seconds; if the timestamp were refreshed each pass, "down for three
    # hours" and "down for three seconds" would be indistinguishable, and the
    # root-cause ranking (which orders by earliest transition) would rank by
    # nothing. So a build that carries the SAME status as the previously
    # stored condition of the same type inherits that condition's
    # `last_transition_at` verbatim.
    module Condition
      UNKNOWN = "unknown"

      # A false condition is `degraded` unless it says otherwise. `down` is
      # reserved for total loss of the thing, and a contributor has to ask for
      # it — the default must not silently escalate.
      SEVERITY_DEGRADED = "degraded"
      SEVERITY_DOWN     = "down"
      SEVERITIES = [ SEVERITY_DEGRADED, SEVERITY_DOWN ].freeze

      # UpperCamelCase, no separators. Matches the Kubernetes condition-token
      # convention the design borrows from.
      TOKEN_FORMAT = /\A[A-Z][A-Za-z0-9]*\z/

      # Statuses, normalized. `true`/`false` stay booleans in the jsonb;
      # anything unmeasurable is the string "unknown" (NOT nil — nil in jsonb
      # is indistinguishable from an absent key).
      def self.normalize_status(status)
        case status
        when true, "true"   then true
        when false, "false" then false
        when UNKNOWN, :unknown, nil then UNKNOWN
        else
          raise ArgumentError, "status must be true, false or #{UNKNOWN.inspect} (got #{status.inspect})"
        end
      end

      # Builds one condition hash with STRING keys (it is going into jsonb and
      # will come back with string keys; building it any other way makes the
      # round trip asymmetric and every comparison subtly wrong).
      #
      # @param previous [Hash, nil] the previously stored condition of the SAME
      #   type, if any. Its `last_transition_at` is inherited when the status
      #   is unchanged.
      def self.build(type:, status:, reason:, message: nil, severity: nil,
                     evidence: nil, observed_generation: nil, observed_at: nil,
                     previous: nil, now: Time.current)
        validate_token!(:type, type)
        validate_token!(:reason, reason)
        normalized = normalize_status(status)
        severity = normalize_severity(severity)

        {
          "type" => type.to_s,
          "status" => normalized,
          "reason" => reason.to_s,
          "message" => message.presence,
          "severity" => severity,
          "evidence" => evidence.presence || {},
          "observed_generation" => observed_generation&.to_s,
          "observed_at" => (observed_at || now),
          "last_transition_at" => transition_at(previous: previous, status: normalized, now: now)
        }
      end

      # Re-keys a list of previously stored conditions by type, so a caller can
      # hand `build` the right `previous:`.
      def self.index_by_type(conditions)
        Array(conditions).each_with_object({}) do |condition, acc|
          next unless condition.is_a?(Hash)

          type = condition["type"] || condition[:type]
          acc[type.to_s] = condition if type.present?
        end
      end

      # The verdict one condition argues for (design §4.1). `Held` and
      # `Progressing` are the ONLY way a component reaches those two verdicts:
      # see Platform::Status::Contributor for why there is no second channel.
      # One source for the tokens: the model owns them, because the rollup's
      # held bucket keys on the same string (see ComponentStatus.intent_held?).
      HELD_TYPE        = ComponentStatus::HELD_CONDITION_TYPE
      PROGRESSING_TYPE = ComponentStatus::PROGRESSING_CONDITION_TYPE

      def self.verdict_for(condition)
        return ComponentStatus::NOT_MEASURED unless condition.is_a?(Hash)

        type   = (condition["type"] || condition[:type]).to_s
        status = condition["status"]
        status = condition[:status] if status.nil? && condition.key?(:status)

        case status
        when true
          case type
          when HELD_TYPE        then ComponentStatus::HELD
          when PROGRESSING_TYPE then ComponentStatus::PROGRESSING
          else ComponentStatus::OK
          end
        when false
          # An absent intent is not a failure: "not held" and "not
          # provisioning" are both the ordinary case.
          return ComponentStatus::OK if [ HELD_TYPE, PROGRESSING_TYPE ].include?(type)

          severity = (condition["severity"] || condition[:severity]).to_s
          severity == SEVERITY_DOWN ? ComponentStatus::DOWN : ComponentStatus::DEGRADED
        else
          ComponentStatus::NOT_MEASURED
        end
      end

      # The component verdict a whole condition set argues for: the worst of
      # them. NO conditions at all is `not_measured`, never `ok` — a
      # contributor that returned nothing told us nothing.
      def self.verdict_for_set(conditions)
        list = Array(conditions)
        return ComponentStatus::NOT_MEASURED if list.empty?

        ComponentStatus.worst(list.map { |c| verdict_for(c) })
      end

      def self.validate_token!(field, value)
        return if value.to_s.match?(TOKEN_FORMAT)

        raise ArgumentError,
              "condition #{field} must be UpperCamelCase with no separators (got #{value.inspect}); " \
              "these tokens are greppable and must never reach a status-variant lookup"
      end

      def self.normalize_severity(severity)
        return nil if severity.blank?

        value = severity.to_s
        return value if SEVERITIES.include?(value)

        raise ArgumentError, "severity must be one of #{SEVERITIES.join(', ')} (got #{severity.inspect})"
      end

      def self.transition_at(previous:, status:, now:)
        return now unless previous.is_a?(Hash)

        previous_status = previous.key?("status") ? previous["status"] : previous[:status]
        return now unless previous_status == status

        previous["last_transition_at"] || previous[:last_transition_at] || now
      end

      private_class_method :validate_token!, :normalize_severity, :transition_at
    end
  end
end
