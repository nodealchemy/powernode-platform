# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # DEVOPS INTEGRATION INSTANCES (`Devops::IntegrationInstance`) as
      # components. READ-ONLY, deliberately (design §8, row A3).
      #
      # ── SCOPE ───────────────────────────────────────────────────────────────
      # `Devops::IntegrationInstance.where(account:).where.not(status: "disabled")`.
      #
      # `disabled` is this model's retirement state — `#disable!` is what an
      # operator calls to take an integration out of service for good, and the
      # UI offers no "disabled" filter to bring it back into an operational
      # view. It is therefore excluded, and the reap arm removes the row three
      # sweeps after somebody disables one. `paused` is NOT excluded: pausing is
      # reversible operator intent, which the ladder spells `held`.
      #
      # ── THE HEALTH FIELDS ARE NOT WRITTEN TODAY, AND WE SAY SO ──────────────
      # `health_status`, `consecutive_failures` and `last_health_check_at` exist
      # on the table and `#update_health!` writes them, but nothing calls it:
      # the integration_health probe never persists its derivation (the audit's
      # finding; A8 fixes it). This contributor does not paper over that. When
      # `last_health_check_at` is nil the health condition is
      # `unknown / NeverChecked` — which the ladder renders `not_measured` —
      # regardless of whatever default sits in the `health_status` column. A
      # green row derived from a column nobody writes would be the exact lie
      # this plane exists to prevent, and once A8 lands the same code starts
      # telling the truth with no edit here.
      #
      # This contributor does not touch `Devops::RegistryService`.
      class IntegrationInstance < Contributor
        include EnumConditions

        KIND = "integration_instance"

        ENABLED_TYPE = "Enabled"
        HEALTH_TYPE  = "Healthy"

        # Retired by an operator: enumerated by nobody, so its row ages out.
        EXCLUDED_STATUSES = %w[disabled].freeze

        # `Devops::IntegrationInstance::STATUSES`, in full. `disabled` is mapped
        # even though it is never enumerated — a total table means changing the
        # exclusion rule later cannot silently produce `UnknownStatus`.
        STATUS_CONDITIONS = {
          "active" => {
            type: ENABLED_TYPE, status: true, reason: "Active",
            message: "integration is active"
          },
          "pending" => {
            type: Condition::PROGRESSING_TYPE, status: true, reason: "AwaitingActivation",
            message: "integration has been created but not activated"
          },
          "paused" => {
            type: Condition::HELD_TYPE, status: true, reason: "Paused",
            message: "integration was paused by an operator"
          },
          "disabled" => {
            type: Condition::HELD_TYPE, status: true, reason: "Disabled",
            message: "integration was disabled by an operator"
          },
          "error" => {
            type: ENABLED_TYPE, status: false, severity: Condition::SEVERITY_DEGRADED,
            reason: "InstanceError",
            message: "integration is in the error state"
          }
        }.freeze

        # `Devops::IntegrationInstance::HEALTH_STATUSES`, in full. Only consulted
        # once a health check has actually run — see the note above.
        #
        # `unhealthy` is `down`, not `degraded`, because `#can_execute?` returns
        # false on it: the integration is not partially working, it is not
        # working.
        HEALTH_CONDITIONS = {
          "healthy" => {
            type: HEALTH_TYPE, status: true, reason: "HealthCheckPassed",
            message: "last integration health check succeeded"
          },
          "degraded" => {
            type: HEALTH_TYPE, status: false, severity: Condition::SEVERITY_DEGRADED,
            reason: "HealthCheckDegraded",
            message: "integration health check reports degraded"
          },
          "unhealthy" => {
            type: HEALTH_TYPE, status: false, severity: Condition::SEVERITY_DOWN,
            reason: "HealthCheckFailed",
            message: "integration is unhealthy and cannot execute"
          },
          "unknown" => {
            type: HEALTH_TYPE, status: Condition::UNKNOWN, reason: "HealthUnknown",
            message: "integration health check returned no verdict"
          }
        }.freeze

        def kind = KIND

        def each_component(account)
          return if account.blank?

          ::Devops::IntegrationInstance
            .where(account_id: account.id)
            .where.not(status: EXCLUDED_STATUSES)
            .find_each { |instance| yield instance }
        end

        def ref_for(instance) = instance.id.to_s

        def display_name_for(instance) = instance.name.presence || instance.slug

        def links_for(instance)
          [ { "label" => "Integration", "path" => "/app/devops/connections/integrations/#{instance.id}" } ]
        end

        def presentation
          { "icon" => "Cable", "label" => "Integration", "group_order" => 20 }
        end

        def conditions_for(instance)
          [ status_condition(instance), health_condition(instance) ]
        end

        # An integration instance's `template` and `credential` are
        # configuration rows, not components: neither is a registered kind, and
        # neither has a status anybody can act on. Inventing an edge to them
        # would put boxes on the graph that no verdict ever reaches.
        def dependencies_for(_instance) = []

        def actions_for(_instance) = []

        # The health check's own time, when one has run. Nil (so the sweep's
        # clock is used) when none has — a row that has never been measured must
        # not claim a measurement time.
        def observed_at_for(instance) = instance.last_health_check_at

        private

        def status_condition(instance)
          enum_condition(
            instance.status,
            table: STATUS_CONDITIONS,
            unknown_type: ENABLED_TYPE,
            evidence: {
              "status" => instance.status.to_s,
              "consecutive_failures" => instance.consecutive_failures,
              "execution_count" => instance.execution_count,
              "failure_count" => instance.failure_count,
              "last_executed_at" => instance.last_executed_at&.iso8601,
              "last_error" => instance.last_error&.to_s&.truncate(300)
            }.compact
          )
        end

        def health_condition(instance)
          evidence = {
            "health_status" => instance.health_status,
            "consecutive_failures" => instance.consecutive_failures,
            "last_health_check_at" => instance.last_health_check_at&.iso8601
          }.compact

          if instance.last_health_check_at.blank?
            return Condition.build(
              type: HEALTH_TYPE, status: Condition::UNKNOWN, reason: "NeverChecked",
              message: "no integration health check has been recorded",
              evidence: evidence
            )
          end

          enum_condition(instance.health_status, table: HEALTH_CONDITIONS,
                                                 unknown_type: HEALTH_TYPE, evidence: evidence)
        end
      end
    end
  end
end
