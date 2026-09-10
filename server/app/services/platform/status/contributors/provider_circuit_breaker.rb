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
      # ── THE ROW IS SANITIZED, AND THAT IS WHAT MAKES IT SHAREABLE ───────────
      # A shared row is broadcast on a shared stream and read by anyone holding
      # `platform.status.read`, in EVERY account. So it carries nothing that
      # identifies a tenant:
      #
      #   - `display_name` is the provider TYPE (`anthropic`, `openai`, …) and a
      #     short id suffix, NEVER the operator-chosen provider name;
      #   - `links_for` is empty. The provider settings page is account-scoped,
      #     so a link would render for a cross-tenant reader and then 403 —
      #     and the contributor contract's own rule about `actions_for` ("a
      #     button that renders and then 403s is worse than no button") applies
      #     word for word to a link;
      #   - `evidence` is the breaker state and its counters, nothing else;
      #   - `dependencies_for` is empty. The `ai_provider` component it would
      #     point at is ACCOUNT-SCOPED, so the edge is unresolvable for the very
      #     readers this row is shared with — an edge to a component the reader
      #     cannot see is a dangling arrow, not information.
      #
      # `component_ref` remains the bare provider UUID: it is the stable key the
      # sweep needs, and an opaque id discloses nothing on its own.
      #
      # AN EARLIER VERSION OF THIS COMMENT CLAIMED the disclosure was "the same
      # exposure Ai::ProviderCircuitBreakerService already has by construction".
      # That was FALSE and the review caught it: the only other caller
      # (`Api::V1::Ai::SelfHealingController`) discloses a cross-account integer
      # COUNT, not names, ids, per-provider state or links. The sanitization
      # above is what closes the gap the false claim papered over.
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
        #
        # The provider TYPE is resolved here, in ONE batched query for the whole
        # set rather than one per row, and merged into the stats hash so every
        # other method stays a pure function of that hash. A type is a vendor
        # name (`anthropic`, `openai`); it identifies no tenant, which is why it
        # is the half of the provider we may carry.
        def each_component(_account)
          stats = ::Ai::ProviderCircuitBreakerService.all_provider_stats
          types = provider_types_for(stats)

          stats.each { |row| yield row.merge(provider_type: types[row[:provider_id].to_s]) }
        end

        def ref_for(stats) = stats[:provider_id].to_s

        # Type plus a short id suffix — enough for an operator to tell two
        # breakers apart, and never the operator-chosen name. See the class
        # comment.
        def display_name_for(stats)
          type = stats[:provider_type].presence || "provider"
          suffix = ref_for(stats).delete("-").last(6)

          suffix.present? ? "#{type} circuit ##{suffix}" : "#{type} circuit"
        end

        # Deliberately empty. See "THE ROW IS SANITIZED" above.
        def links_for(_stats) = []

        def presentation
          { "icon" => "CircuitBoard", "label" => "Provider Circuit Breaker", "group_order" => 41 }
        end

        def conditions_for(stats)
          [
            enum_condition(
              stats[:state],
              table: STATE_CONDITIONS,
              unknown_type: CLOSED_TYPE,
              # State and counters ONLY. No provider id, no provider name.
              evidence: {
                "state" => stats[:state].to_s,
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

        # Deliberately empty, though a real edge exists.
        #
        # The breaker's state IS a function of its `ai_provider` failing, so on
        # the graph alone the edge belongs. But `ai_provider` rows are
        # ACCOUNT-SCOPED and this row is shared: for every reader outside the
        # provider's own account the edge points at a component they cannot
        # see, and `Rollup` silently skips it. An edge that resolves for one
        # reader in a thousand is a dangling arrow that also happens to name
        # another tenant's provider id — the disclosure the sanitization rule
        # exists to prevent. Dropped until there is a shared component the
        # breaker can honestly depend on.
        def dependencies_for(_stats) = []

        def actions_for(_stats) = []

        # The breaker's own last state change, when it has one. Not the sweep's
        # clock: "open since 40 minutes ago" and "open since now" are the whole
        # difference between a stuck breaker and a fresh trip.
        def observed_at_for(stats)
          parse_time(stats[:state_changed_at])
        end

        private

        # One query for the whole sweep. Only `provider_type` is read — never
        # the name, and never the account.
        def provider_types_for(stats)
          ids = stats.filter_map { |row| row[:provider_id].presence }.map(&:to_s).uniq
          return {} if ids.empty?

          ::Ai::Provider.where(id: ids).pluck(:id, :provider_type)
                        .to_h { |id, type| [ id.to_s, type.to_s ] }
        rescue StandardError => e
          Rails.logger.error("[Platform::Status] provider type lookup failed: #{e.class}: #{e.message}")
          {}
        end

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
