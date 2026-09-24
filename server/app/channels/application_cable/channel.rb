# frozen_string_literal: true

module ApplicationCable
  class Channel < ActionCable::Channel::Base
    # N2: a socket opened BEFORE maintenance mode was enabled is otherwise
    # never re-checked — Connection#authenticate_user only gates the initial
    # handshake. Two chokepoints close that gap for every channel that
    # inherits from this base, with no per-channel code:
    #   - before_subscribe: a NEW subscription attempt over an
    #     already-open (grandfathered) connection is rejected.
    #   - #perform_action: every subsequent action call on an EXISTING
    #     subscription is rejected/closed once maintenance turns on mid-session.
    before_subscribe :reject_if_maintenance_blocked!

    # Overrides ActionCable::Channel::Base#perform_action, which is PUBLIC
    # (the dispatcher calls it from outside the channel instance) — must stay
    # public here too, or the override merely shadows it with a protected
    # method the real dispatcher (and `perform` in a channel spec) can no
    # longer call at all.
    def perform_action(data)
      return close_for_maintenance! if maintenance_blocked?

      super
    end

    protected

    # Helper method to get current user's account
    def current_account
      @current_account ||= current_user&.account
    end

    # Helper method to check if user can access account data
    def authorized_for_account?(account_id)
      return false unless current_user&.account

      # User can access their own account data
      current_user.account.id == account_id
    end

    # Helper method to broadcast to account-specific stream
    def broadcast_to_account(account, data)
      ActionCable.server.broadcast("account_#{account.id}", data)
    end

    # Helper method to stream from account-specific channel
    def stream_for_account(account)
      stream_from("account_#{account.id}")
    end

    private

    def reject_if_maintenance_blocked!
      return unless maintenance_blocked?

      reject
      throw :abort
    end

    # `current_user` is delegated from the connection (identified_by); a
    # worker-authenticated channel (current_user nil) is never gated here —
    # consistent with Admin::MaintenanceMode.blocked? only ever being called
    # against a resolved user principal on the REST/MCP/cable-connect paths.
    #
    # `connection.request`/`connection.impersonator` are read defensively
    # (`respond_to?`) rather than bare, because ActionCable::Channel::TestCase's
    # ConnectionStub (`stub_connection` in a channel spec) implements neither —
    # only whatever identifiers a given spec explicitly stubs. Every existing
    # channel spec calls `stub_connection current_user: ...` without an
    # `impersonator:` or `request:`, so referencing either one un-guarded here
    # would raise NoMethodError in EVERY channel spec, not just one exercising
    # maintenance mode.
    def maintenance_blocked?
      return false unless current_user

      remote_ip = connection.respond_to?(:request) ? connection.request.remote_ip : nil
      impersonator = connection.respond_to?(:impersonator) ? connection.impersonator : nil

      Admin::MaintenanceMode.blocked?(remote_ip) { |perm| current_user.has_permission?(perm) || (impersonator && impersonator.has_permission?(perm)) }
    end

    # Real Connection#close is public and works from a Channel (Channel has a
    # public `connection` reader) — but ActionCable::Channel::TestCase's
    # ConnectionStub doesn't define #close (only #transmit), so guard for it
    # the same way Connection#close_for_maintenance! guards for @coder/
    # @websocket: reject is the test-harness-safe fallback that still proves
    # the action didn't dispatch.
    def close_for_maintenance!
      if connection.respond_to?(:close)
        connection.close(reason: "maintenance_mode", reconnect: false)
      else
        reject
      end
    end
  end
end
