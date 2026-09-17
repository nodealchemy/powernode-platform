# frozen_string_literal: true

# IMP-dd0305de2799. webhook_events.provider was constrained to the two INBOUND
# billing providers (stripe/paypal) — correct for that origin, but
# WebhookDelivery#webhook_event is a hard NOT NULL belongs_to, and the outbound
# platform-event producer (WebhookEventPublisher) needs a webhook_event row for
# every OUTBOUND platform event (user.created, account.updated, ...) too. Those
# are not billing provider callbacks, so tagging them "stripe"/"paypal" would
# corrupt Admin::SettingsService's real Stripe/PayPal event counts
# (WebhookEvent.for_provider("stripe")/("paypal")). "system" is the new,
# additive third value for platform-originated (non-billing) events; it is
# never counted by the stripe/paypal-scoped admin queries.
#
# LOCK NOTE: add_check_constraint (and the remove_check_constraint that
# precedes it here) takes an ACCESS EXCLUSIVE lock on webhook_events and, for
# the add, runs a validating scan of the existing rows before releasing it —
# a write-blocking window proportional to the table's size, not merely the
# instant of a metadata change. Fine for this table's expected volume; call
# out explicitly for whoever reaches for this same remove+add shape on a
# larger table later.
#
# Kept in sync with WebhookEvent::ALL_PROVIDERS (model validation) by
# spec/models/webhook_event_spec.rb's "provider value set agrees with the DB
# check constraint" spec — that is the THIRD place this value list appears
# (model, constraint, this migration's own record of the constraint's
# history) and there is no way to collapse it to fewer without a differently
# shaped scan-time-vs-DB-metadata check; the spec is what catches drift.
class AllowSystemProviderForWebhookEvents < ActiveRecord::Migration[8.0]
  OLD_PROVIDERS = %w[stripe paypal].freeze
  NEW_PROVIDERS = %w[stripe paypal system].freeze
  CONSTRAINT = "valid_webhook_provider"

  def up
    swap_provider_constraint(NEW_PROVIDERS)
  end

  # Once any provider='system' row exists, re-adding the two-value CHECK
  # cannot succeed as a plain constraint swap (PG raises CheckViolation during
  # the validating scan), and those rows cannot simply be deleted out from
  # under it either: webhook_deliveries.webhook_event_id is NOT NULL, so every
  # WebhookDelivery fanned out to a real endpoint for a real platform event
  # would have to be deleted first — an operator decision (discarding
  # delivery history), not a side effect of `db:rollback`. Refuse loudly with
  # the exact count instead of failing obscurely on the CheckViolation.
  def down
    doomed = select_value(
      "SELECT COUNT(*) FROM webhook_events WHERE provider = 'system'"
    ).to_i

    if doomed.positive?
      raise ActiveRecord::IrreversibleMigration,
            "Rolling back would make #{doomed} webhook_events row(s) with provider='system' " \
            "violate the restored two-value CHECK (and each is very likely referenced by a " \
            "NOT NULL webhook_deliveries.webhook_event_id, so it cannot simply be deleted). " \
            "This rollback does not attempt that data loss; an operator must decide it explicitly " \
            "(delete the affected webhook_deliveries and webhook_events rows first if rolling " \
            "back is truly required)."
    end

    swap_provider_constraint(OLD_PROVIDERS)
  end

  private

  def swap_provider_constraint(providers)
    remove_check_constraint :webhook_events, name: CONSTRAINT
    add_check_constraint :webhook_events, provider_expression(providers), name: CONSTRAINT
  end

  def provider_expression(providers)
    list = providers.map { |p| "'#{p}'::character varying::text" }.join(", ")
    "provider::text = ANY (ARRAY[#{list}])"
  end
end
