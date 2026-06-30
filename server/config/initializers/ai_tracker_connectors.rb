# frozen_string_literal: true

# Register the CORE outbound issue/error-tracker adapters into
# Ai::Connectors::TrackerRegistry at boot. The generic webhook adapter is the
# reference implementation; the named-vendor adapters (Linear/Jira/Sentry) are
# THIN scaffolding that delegate to a configured webhook proxy until a full
# vendor API client (auth + REST) is wired — the documented G8 follow-up.
#
# These are opt-in: nothing is forwarded unless a tracker is configured via
# SiteSetting (see Ai::Connectors::TrackerConfig). Extensions MAY register
# additional adapters the same way; core stays vendor-agnostic.
Rails.application.config.after_initialize do
  {
    generic_webhook: "Ai::Connectors::GenericWebhookTrackerAdapter",
    linear: "Ai::Connectors::LinearAdapter",
    jira: "Ai::Connectors::JiraAdapter",
    sentry: "Ai::Connectors::SentryAdapter"
  }.each do |name, const_name|
    klass = const_name.safe_constantize
    Ai::Connectors::TrackerRegistry.register(name, klass.new) if klass
  end
end
