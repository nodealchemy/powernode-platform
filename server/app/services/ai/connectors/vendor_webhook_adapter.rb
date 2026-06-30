# frozen_string_literal: true

module Ai
  module Connectors
    # Thin shared base for the named-vendor scaffolding adapters (Linear / Jira /
    # Sentry). Each subclass only declares its label + registry key. Until a full
    # vendor API client (auth + REST) is wired, the adapter either delegates to the
    # GenericWebhookTrackerAdapter against a configured webhook/proxy URL, or — when
    # nothing is configured — raises NotImplementedError with a clear pointer to the
    # G8 follow-up. Subclasses stay thin; the wiring lives here, DRY.
    class VendorWebhookAdapter
      def initialize(url: nil, headers: nil)
        @url = url
        @headers = headers
      end

      def name
        self.class.vendor_key
      end

      def create_issue(title:, body:, severity: "warning", metadata: {})
        delegate.create_issue(
          title: title, body: body, severity: severity,
          metadata: metadata.merge(vendor: self.class.vendor_label)
        )
      end

      def report_error(error:, severity: "error", context: {})
        delegate.report_error(
          error: error, severity: severity,
          context: context.merge(vendor: self.class.vendor_label)
        )
      end

      class << self
        def vendor_label
          raise NotImplementedError, "#{name} must define .vendor_label"
        end

        def vendor_key
          raise NotImplementedError, "#{name} must define .vendor_key"
        end
      end

      private

      def delegate
        target = @url || Ai::Connectors::TrackerConfig.endpoint
        if target.blank?
          raise NotImplementedError,
                "#{self.class.vendor_label} tracker is registered but not fully wired. " \
                "Configure a full #{self.class.vendor_label} API client (auth + REST), or set a webhook " \
                "proxy URL (ai_tracker_webhook_url) and select adapter '#{name}'. See G8 follow-up."
        end

        Ai::Connectors::GenericWebhookTrackerAdapter.new(url: target, headers: @headers, name: name)
      end
    end
  end
end
