# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # THE PLATFORM'S OWN CORE SERVICES — database, redis, sidekiq, disk,
      # memory and cpu — as components, read from Platform::Health::CoreChecks.
      #
      # They are reported here in every mode, so /app/status always shows them,
      # and no other contributor reports them. The Observability and
      # Maintenance health tabs that used to were deleted in fc-47.
      #
      # ── SCOPE ───────────────────────────────────────────────────────────────
      # Process-wide: one set per deployment, NULL account, the "shared
      # infrastructure" section. Every service is structural, so nothing is
      # ever "gone" and there is no terminated arm.
      #
      # ── ONE MEASUREMENT PER INTERVAL, NOT PER ACCOUNT ───────────────────────
      # The sweep reads, it does not probe — and these checks open sockets (a
      # SELECT 1, a PING, the worker Redis). The sweep runs once per account
      # every interval, so the readings are cached and every account's sweep
      # in that interval reads the same measurement. The cache lives HALF an
      # interval, so each sweep reads a measurement taken after the previous
      # sweep began, never one a full interval stale. Each reading carries its
      # `measured_at`, so the evidence says how old it is. The other methods
      # are pure functions of a reading.
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

        CACHE_KEY = "platform:status:core_service:readings"

        def kind = KIND

        def account_scoped? = false

        # The account is ignored on purpose: these services have no tenant.
        def each_component(_account)
          readings.each do |service, values|
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
          evidence = values.except("status", "error_class")
          name = display_name_for(reading)
          cause = values["error_class"].presence && " (#{values['error_class']})"

          unless mapped
            return [
              Condition.build(
                type: HEALTHY, status: Condition::UNKNOWN, reason: NOT_OBSERVED,
                message: "#{name} could not be read#{cause}", evidence: evidence
              )
            ]
          end

          [
            Condition.build(
              type: HEALTHY,
              status: mapped[:status],
              severity: mapped[:severity],
              reason: mapped[:reason],
              message: "#{name} is #{status}#{cause}",
              evidence: evidence
            )
          ]
        end

        private

        def readings
          Rails.cache.fetch(CACHE_KEY, expires_in: cache_ttl) do
            measured_at = Time.current.utc.iso8601
            ::Platform::Health::CoreChecks.all.transform_values { |values| values.merge(measured_at: measured_at) }
          end
        end

        def cache_ttl
          [ SweepService.sweep_interval_seconds / 2, 1 ].max.seconds
        end
      end
    end
  end
end
