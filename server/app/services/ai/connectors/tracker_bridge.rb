# frozen_string_literal: true

module Ai
  module Connectors
    # Opt-in bridge from the loop's INTERNAL issue/escalation analogs
    # (report_issue / escalate) to any configured OUTBOUND tracker. Best-effort and
    # non-blocking: when no tracker is configured (#enabled? false), it is a no-op
    # so default behavior is unchanged; when a tracker IS configured, it forwards
    # via the registry. Adapter/transport failures are swallowed and logged — the
    # internal path is never broken.
    module TrackerBridge
      class << self
        # @return [Hash, nil] the adapter's result ({ ok:, external_id:, url: }) or
        #   nil when no tracker is configured / nothing forwarded.
        def forward(kind:, title:, body:, severity: "warning", metadata: {})
          return nil unless TrackerConfig.enabled?

          name = TrackerConfig.adapter_name
          adapter = TrackerRegistry.adapter(name)
          unless adapter.respond_to?(:create_issue)
            Rails.logger.warn(
              "[Ai::Connectors::TrackerBridge] no create_issue adapter registered for #{name.inspect}; " \
              "skipping #{kind} forward"
            )
            return nil
          end

          result = adapter.create_issue(
            title: title.to_s,
            body: body.to_s,
            severity: severity.to_s,
            metadata: (metadata || {}).merge(kind: kind.to_s, source: "powernode")
          )
          log_result(kind, name, result)
          result
        rescue StandardError => e
          Rails.logger.warn(
            "[Ai::Connectors::TrackerBridge] failed to forward #{kind} to external tracker: " \
            "#{e.class}: #{e.message}"
          )
          nil
        end

        private

        def log_result(kind, name, result)
          if result.is_a?(Hash) && result[:ok]
            Rails.logger.info(
              "[Ai::Connectors::TrackerBridge] forwarded #{kind} to #{name} (external_id=#{result[:external_id]})"
            )
          else
            Rails.logger.warn(
              "[Ai::Connectors::TrackerBridge] #{name} returned non-ok for #{kind}: #{result.inspect}"
            )
          end
        end
      end
    end
  end
end
