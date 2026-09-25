# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # THE PLATFORM'S OWN CORE SERVICES — database, redis, sidekiq, disk,
      # memory and cpu — as components, read from Platform::Health::CoreChecks.
      #
      # Core mode needs these on /app/status: without the system extension no
      # other contributor reports them, and the Observability and Maintenance
      # health tabs that used to were deleted in fc-47.
      #
      # ── SCOPE ───────────────────────────────────────────────────────────────
      # Process-wide: one set per deployment, NULL account, the "shared
      # infrastructure" section. Every service is structural, so nothing is
      # ever "gone" and there is no terminated arm.
      #
      # ── ONE MEASUREMENT PER SWEEP ───────────────────────────────────────────
      # `each_component` reads every service once and yields the readings; the
      # other methods are pure functions of a reading. The checks are cheap (a
      # SELECT 1, a PING, two /proc reads, a statfs, sidekiq's counters).
      class CoreService < Contributor
        KIND = "core_service"

        HEALTHY = "Healthy"

        # CoreChecks status -> condition status, severity and reason. Anything
        # else (`unknown`, or a token this table does not know) is not
        # measured, never healthy.
        STATUS_CONDITIONS = {
          "healthy" => { status: true, reason: "Healthy" },
          "warning" => { status: false, severity: Condition::SEVERITY_DEGRADED, reason: "Warning" },
          "unhealthy" => { status: false, severity: Condition::SEVERITY_DOWN, reason: "Unhealthy" }
        }.freeze
        NOT_OBSERVED = "NotObserved"

        DISPLAY_NAMES = {
          "database" => "Database", "redis" => "Redis", "sidekiq" => "Sidekiq",
          "disk" => "Disk", "memory" => "Memory", "cpu" => "CPU"
        }.freeze

        Reading = Struct.new(:service, :values, keyword_init: true)

        def kind = KIND

        def account_scoped? = false

        # The account is ignored on purpose: these services have no tenant.
        def each_component(_account)
          ::Platform::Health::CoreChecks.all.each do |service, values|
            yield Reading.new(service: service.to_s, values: values)
          end
        end

        def ref_for(reading) = reading.service

        def display_name_for(reading) = DISPLAY_NAMES.fetch(reading.service) { reading.service.humanize }

        def links_for(_reading) = []

        def presentation
          # group_order 5: the platform's own services sort first.
          { "icon" => "Server", "label" => "Core Service", "group_order" => 5 }
        end

        def dependencies_for(_reading) = []

        def actions_for(_reading) = []

        def conditions_for(reading)
          values = reading.values.to_h.transform_keys(&:to_s)
          status = values["status"].to_s
          mapped = STATUS_CONDITIONS[status]
          evidence = values.except("status", "error")

          unless mapped
            return [
              Condition.build(
                type: HEALTHY, status: Condition::UNKNOWN, reason: NOT_OBSERVED,
                message: [ "#{display_name_for(reading)} could not be read", values["error"].presence ].compact.join(": "),
                evidence: evidence
              )
            ]
          end

          [
            Condition.build(
              type: HEALTHY,
              status: mapped[:status],
              severity: mapped[:severity],
              reason: mapped[:reason],
              message: values["error"].presence || "#{display_name_for(reading)} is #{status}",
              evidence: evidence
            )
          ]
        end
      end
    end
  end
end
