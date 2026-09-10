# frozen_string_literal: true

# Live component-status transitions for ONE account, plus the shared
# infrastructure stream (design §4.3).
#
# STREAM NAMES ARE GLOBAL IN ACTIONCABLE. A bare "platform_status" or an
# unnamespaced account id would deliver anything any other channel publishes
# under that name — the cross-delivery NotificationChannel documents and
# MissionChannel/CodeFactoryChannel avoid by namespacing. So both streams here
# carry the "platform_status:" prefix and nothing subscribes to a bare id.
#
# TWO STREAMS, BECAUSE THERE ARE TWO KINDS OF COMPONENT.
#
# An account-scoped component belongs to one tenant, and its transitions go to
# that tenant's stream only. A SHARED component (a contributor whose
# `account_scoped?` is false — a process-wide thing with no tenant, whose row
# carries a NULL account) has no tenant stream to go to.
#
# The rule, stated once so nobody has to infer it: a shared transition is
# broadcast on ONE stream, `platform_status:shared`, which any authenticated
# user may subscribe to. Not on every account's stream.
#
# The alternative — fanning a shared transition out to every account stream
# the sweep happened to touch — was rejected for two reasons. It makes the set
# of recipients depend on which accounts a particular batch swept, so the same
# event reaches different people depending on batch composition; and it breaks
# "exactly one broadcast per transition", which is the property that keeps a
# duplicate-delivery bug detectable. Shared components already render in their
# own "shared infrastructure" section (design §4.4) and are excluded from every
# per-account rollup, so a shared stream matches what the page does with them.
class PlatformStatusChannel < ApplicationCable::Channel
  SHARED_STREAM = "platform_status:shared"

  def subscribed
    account_id = params[:account_id]

    # A subscription with no account_id asks for shared infrastructure only.
    if account_id.blank?
      return reject unless current_user

      stream_from(SHARED_STREAM)
      transmit_established(scope: "shared")
      return
    end

    unless authorized_for_account?(account_id)
      Rails.logger.warn(
        "[PlatformStatusChannel] rejected subscription to account #{account_id} " \
        "by user #{current_user&.id}"
      )
      return reject
    end

    stream_from(self.class.account_stream(account_id))
    # Shared infrastructure is part of the same picture, so an account
    # subscriber gets both streams from one subscription rather than having to
    # know a second one exists.
    stream_from(SHARED_STREAM)
    transmit_established(scope: "account")
  end

  def unsubscribed
    Rails.logger.info "[PlatformStatusChannel] user #{current_user&.id} unsubscribed"
  end

  class << self
    def account_stream(account_id)
      "platform_status:#{account_id}"
    end

    # THE publishing primitives. Platform::Status::SweepRunner is their only
    # caller — see Platform::StatusEvent on why there is exactly one producer.
    def broadcast_to_account(account_id, data)
      ActionCable.server.broadcast(account_stream(account_id), data)
    end

    def broadcast_shared(data)
      ActionCable.server.broadcast(SHARED_STREAM, data)
    end

    # Routes by tenancy: a NULL account is a shared component, by definition.
    def broadcast_transition(account_id, data)
      account_id.present? ? broadcast_to_account(account_id, data) : broadcast_shared(data)
    end
  end

  private

  def transmit_established(scope:)
    transmit({
      type: "connection_established",
      scope: scope,
      timestamp: Time.current.iso8601
    })
  end
end
