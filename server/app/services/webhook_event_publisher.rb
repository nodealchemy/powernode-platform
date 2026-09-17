# frozen_string_literal: true

# IMP-dd0305de2799. Fans a subscribable PLATFORM event out to every matching
# WebhookEndpoint on the event's account: one WebhookEvent row (the
# WebhookDelivery#webhook_event FK target — belongs_to is NOT NULL) plus one
# WebhookDelivery per matching endpoint. No new bus: this is the one producer
# the pipeline was missing.
#
# This service does NOT enqueue the worker job itself (D1 fix). It runs from
# Auditable#write_audit_log, which runs from an after_create/after_update/
# before_destroy callback — i.e. INSIDE the same DB transaction as the change
# that triggered it. Enqueuing Webhooks::WebhookDeliveryJob synchronously here
# would let the worker pick the job up (and 404 against the internal
# delivery-fetch endpoint) before this transaction commits, or after it rolls
# back entirely — the delivery job treats a 404 as neither a failure to record
# nor a reason to retry, so the row would be stuck "pending" forever and the
# event silently lost. WebhookDelivery#enqueue_worker_job (an after_commit
# callback) owns the enqueue instead, so it only ever runs once the row is
# durably visible.
#
# Called from Auditable#write_audit_log (see there for the two independent
# guards against double-firing, and why hooking that method rather than
# AuditLog.log_action matters).
#
# The provider on the created WebhookEvent is "system" (WebhookEvent::OUTBOUND_PROVIDER,
# IMP-dd0305de2799 migration AllowSystemProviderForWebhookEvents), distinguishing
# an outbound platform event from an inbound stripe/paypal billing callback so
# it is never counted by the provider-scoped billing admin queries.
#
# The actual HTTP body + HMAC signature are produced later, per delivery
# attempt, by Api::V1::Internal::WebhookDeliveriesController#show
# (IMP-3e7c104f2b36) from webhook_event.payload — this service only decides
# WHO gets a delivery and creates the row; it never touches secret_key and
# never talks to the destination URL itself.
#
# PAYLOAD CONTRACT (documentable to an outside consumer without reading
# source): {"event_type", "action", "timestamp", "id", "account_id", "data"}.
# The first five are flat top-level keys because WebhookEndpoint#trim_payload's
# "minimal" detail level reads exactly those names; "data" carries the
# resource's own attributes for "full" detail (see Auditable#webhook_payload_data
# for what actually populates it and why it defaults to empty), and
# "ids_only" detail walks the whole hash for any *_id/id key regardless of
# nesting. Built by Auditable#publish_webhook_event, the one place that
# assembles it.
class WebhookEventPublisher
  class << self
    # event_type: e.g. "user.created" — see WebhookEndpoint.available_event_types
    #   (only 5 of its ~28 entries can fire today; see the LIVE_EVENT_TYPES
    #   note there).
    # account: the Account whose webhook_endpoints may subscribe. nil is a
    #   no-op: a platform event with no resolved tenant has no endpoint to fan
    #   out to (there is no "broadcast to every account" concept here).
    # payload: Hash, the exact outbound representation of the event. Required
    #   (no default): WebhookEvent validates its presence, so a caller with
    #   nothing to send must decide what that means rather than silently
    #   hitting a RecordInvalid three calls deep.
    def publish(event_type:, account:, payload:)
      return if account.nil? || event_type.blank?

      endpoints = account.webhook_endpoints.active.to_a.select do |endpoint|
        endpoint.can_receive_event?(event_type)
      end
      return if endpoints.empty?

      webhook_event = create_webhook_event(account, event_type, payload)
      endpoints.each { |endpoint| deliver_to(endpoint, webhook_event) }
      nil
    end

    # Derives the platform event_type a generic Auditable create/update/delete
    # maps to, or nil when this resource/action has no subscribable event.
    # Deliberately narrow: only the three generic Auditable-emitted actions are
    # considered, and only when "<demodulized underscored class>.<action>" is
    # itself one of the names WebhookEndpoint.available_event_types declares —
    # every other Auditable model, and every OTHER action string (a controller
    # logging under its own explicit name, e.g. "account_created" or
    # "suspend_account"), is a no-op here by construction. See
    # Auditable#publish_webhook_event for what this guard does and does not
    # protect against.
    def event_type_for(resource, action)
      return nil unless %w[created updated deleted].include?(action.to_s)

      candidate = "#{resource.class.name.demodulize.underscore}.#{action}"
      WebhookEndpoint.available_event_types.include?(candidate) ? candidate : nil
    end

    private

    def create_webhook_event(account, event_type, payload)
      ::WebhookEvent.create!(
        account: account,
        provider: ::WebhookEvent::OUTBOUND_PROVIDER,
        event_id: SecureRandom.uuid,
        event_type: event_type,
        external_id: "system_#{SecureRandom.uuid}",
        payload: payload,
        occurred_at: Time.current,
        status: "pending"
      )
    end

    # Rate-limit decision (operator-direction §4, "over a limit"): the
    # endpoint's own tier daily quota is the only delivery-time limit that
    # exists today (Entitlements::UsageLimitService gates ENDPOINT creation,
    # not delivery volume). An endpoint over quota still gets a WebhookDelivery
    # row — the fan-out and the attempt are real, and the operator can see it
    # in delivery_history/failed_deliveries — but it is recorded straight to
    # "failed" WITHOUT ever being attempted: no worker enqueue (guarded by
    # WebhookDelivery#enqueue_worker_job checking status == "pending" at
    # commit time, since this update happens before that callback runs), no
    # attempted_at, and — D2 — `skip_endpoint_stats` so
    # WebhookDelivery#update_webhook_endpoint_stats does not count a delivery
    # that never reached the network as an endpoint FAILURE (which would
    # otherwise collapse success_rate/health_status and light up the
    # `failing` scope purely from being over quota, for a receiver that was
    # never contacted).
    def deliver_to(endpoint, webhook_event)
      delivery = ::WebhookDelivery.create!(
        webhook_endpoint: endpoint,
        webhook_event: webhook_event,
        status: "pending"
      )

      endpoint.reset_daily_count_if_needed!
      if endpoint.rate_limited?
        delivery.skip_endpoint_stats = true
        delivery.update!(
          status: "failed",
          error_message: "Endpoint daily delivery limit reached for tier '#{endpoint.tier}'"
        )
        return delivery
      end

      endpoint.increment_daily_count!
      delivery
    end
  end
end
