# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # PROVIDER CIRCUIT BREAKERS, over
      # `Ai::ProviderCircuitBreakerService.all_provider_stats`.
      #
      # ── THIS KIND IS SHARED, AND THAT IS NOT A SHORTCUT ─────────────────────
      # `account_scoped?` is false, so these rows carry a NULL `account_id` and
      # never enter a per-account rollup. That is what the SOURCE is, read
      # honestly:
      #
      #   - the state lives in Redis under `circuit_breaker:<provider_id>`, in
      #     one keyspace shared by every process talking to that Redis;
      #   - `.all_provider_stats` enumerates `Ai::Provider.active` across ALL
      #     accounts and takes no account argument;
      #   - the stats hash carries `provider_id`, `provider_name`, `state` and
      #     counters — and no account of any kind.
      #
      # We could have joined each `provider_id` back to `ai_providers` to
      # recover an account. We deliberately did not: the reading is
      # process-wide, so attaching it to one tenant's rollup would assert a
      # tenancy the measurement does not have. Fabricating an `account_id` is
      # the one thing the increment's brief forbids outright, and this is the
      # kind where the temptation lives.
      #
      # The consequence, stated plainly: a `provider_id` in `component_ref`
      # belongs to some account, but the ROW is shared, so any operator who can
      # read the shared section sees that provider's breaker state and name.
      # That is the same exposure `Ai::ProviderCircuitBreakerService` already
      # has by construction, not a new one this contributor creates.
      #
      # ── SCOPE ───────────────────────────────────────────────────────────────
      # Whatever `.all_provider_stats` returns, which is `Ai::Provider.active` —
      # so a deactivated provider is already excluded upstream and its row ages
      # out through the reap arm. No further exclusion is applied here: filtering
      # a source we do not own would put a second, drifting definition of
      # "which providers count" in the tree.
      #
      # ── WHEN REDIS IS DOWN ──────────────────────────────────────────────────
      # `.all_provider_stats` raises, the sweep catches it, and this kind's
      # wildcard row becomes `not_measured / ContributorError`. That is the
      # correct answer and needs no code here: a breaker plane we cannot read is
      # blindness, not health.
      class ProviderCircuitBreaker < Contributor
        include EnumConditions

        KIND = "provider_circuit_breaker"

        CLOSED_TYPE = "Closed"

        # `CircuitBreakerCore::STATES`, in full. Same three states and the same
        # reasoning as the per-agent breaker: `open` is a bounded, self-clearing
        # refusal, so `degraded` rather than `down`.
        STATE_CONDITIONS = {
          "closed" => {
            type: CLOSED_TYPE, status: true, reason: "BreakerClosed",
            message: "provider circuit breaker is closed and calls are flowing"
          },
          "open" => {
            type: CLOSED_TYPE, status: false, severity: Condition::SEVERITY_DEGRADED,
            reason: "BreakerOpen",
            message: "provider circuit breaker is open and is refusing calls"
          },
          "half_open" => {
            type: Condition::PROGRESSING_TYPE, status: true, reason: "BreakerHalfOpen",
            message: "provider circuit breaker is half-open and probing for recovery"
          }
        }.freeze

        def kind = KIND

        # Shared: NULL account, no per-account rollup. See the note above.
        def account_scoped? = false

        # The account is ignored on purpose — the source has none. Named `_`
        # so nobody reads a scoping that is not there.
        def each_component(_account)
          ::Ai::ProviderCircuitBreakerService.all_provider_stats.each { |stats| yield stats }
        end

        def ref_for(stats) = stats[:provider_id].to_s

        def display_name_for(stats)
          name = stats[:provider_name].presence || stats[:service_name].presence
          "#{name || stats[:provider_id]} circuit"
        end

        def links_for(stats)
          return [] if stats[:provider_id].blank?

          [ { "label" => "Provider settings",
              "path" => "/app/ai/infrastructure/providers/#{stats[:provider_id]}" } ]
        end

        def presentation
          { "icon" => "CircuitBoard", "label" => "Provider Circuit Breaker", "group_order" => 41 }
        end

        def conditions_for(stats)
          [
            enum_condition(
              stats[:state],
              table: STATE_CONDITIONS,
              unknown_type: CLOSED_TYPE,
              evidence: {
                "state" => stats[:state].to_s,
                "provider_id" => stats[:provider_id].to_s.presence,
                "failure_count" => stats[:failure_count],
                "success_count" => stats[:success_count],
                "consecutive_failures" => stats[:consecutive_failures],
                "consecutive_successes" => stats[:consecutive_successes],
                "can_attempt" => stats[:can_attempt],
                "state_changed_at" => timestamp(stats[:state_changed_at]),
                "last_failure_time" => timestamp(stats[:last_failure_time]),
                "next_retry_at" => timestamp(stats[:next_retry_at])
              }.compact
            )
          ]
        end

        # The provider this breaker guards is an `ai_provider` component, and
        # the breaker's state is entirely a function of that provider failing —
        # a real edge, and the one that makes root-cause ranking put the
        # provider above the breaker rather than beside it.
        def dependencies_for(stats)
          return [] if stats[:provider_id].blank?

          [ { "kind" => "ai_provider", "ref" => stats[:provider_id].to_s, "relation" => "requires" } ]
        end

        def actions_for(_stats) = []

        # The breaker's own last state change, when it has one. Not the sweep's
        # clock: "open since 40 minutes ago" and "open since now" are the whole
        # difference between a stuck breaker and a fresh trip.
        def observed_at_for(stats)
          parse_time(stats[:state_changed_at])
        end

        private

        def timestamp(value) = parse_time(value)&.iso8601

        def parse_time(value)
          case value
          when nil then nil
          when Time, DateTime then value.to_time
          when ActiveSupport::TimeWithZone then value
          when Numeric then Time.zone.at(value)
          else Time.zone.parse(value.to_s)
          end
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
