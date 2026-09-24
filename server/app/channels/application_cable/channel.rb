# frozen_string_literal: true

module ApplicationCable
  class Channel < ActionCable::Channel::Base
    # N2: a socket opened BEFORE maintenance mode was enabled is otherwise
    # never re-checked — Connection#authenticate_user only gates the initial
    # handshake. Three chokepoints close that gap for every channel that
    # inherits from this base, with no per-channel code:
    #   - before_subscribe: a NEW subscription attempt over an
    #     already-open (grandfathered) connection is rejected.
    #   - #perform_action: every subsequent action call on an EXISTING
    #     subscription is rejected/closed once maintenance turns on mid-session.
    #   - periodically :enforce_maintenance!: catches a PASSIVE subscriber —
    #     one that only streams broadcasts and never calls an action at all
    #     (e.g. NotificationChannel with nothing pending) — which the two
    #     hooks above would otherwise never reach.
    before_subscribe :reject_if_maintenance_blocked!
    periodically :enforce_maintenance!, every: 30.seconds

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

    # The periodic re-check (see periodically above). Same close path as
    # #perform_action's — a passive subscriber gets the SAME
    # reason: "maintenance_mode" disconnect frame a mid-action user would.
    def enforce_maintenance!
      close_for_maintenance! if maintenance_blocked?
    end

    # `current_user` is delegated from the connection (identified_by); a
    # worker-authenticated channel (current_user nil) is never gated here —
    # consistent with Admin::MaintenanceMode.blocked? only ever being called
    # against a resolved user principal on the REST/MCP/cable-connect paths.
    #
    # Reads the remote IP via `connection.maintenance_remote_ip` — NOT
    # `connection.request.remote_ip`. `request` is declared PRIVATE on
    # ActionCable::Connection::Base, so it is unreachable from a DIFFERENT
    # object (this Channel) in PRODUCTION too, not just in a test harness —
    # `connection.respond_to?(:request)` is false either way. Guarded with
    # `respond_to?` regardless, because ActionCable::Channel::TestCase's
    # ConnectionStub (`stub_connection` in a channel spec) doesn't define
    # `maintenance_remote_ip` unless a spec explicitly stubs it, and every
    # PRE-EXISTING channel spec calls `stub_connection current_user: ...`
    # without it.
    def maintenance_blocked?
      return false unless current_user

      remote_ip = connection.respond_to?(:maintenance_remote_ip) ? connection.maintenance_remote_ip : nil

      Admin::MaintenanceMode.blocked?(remote_ip) { |perm| current_user.has_permission?(perm) }
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
