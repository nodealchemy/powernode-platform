# frozen_string_literal: true

module Audit
  # Resolves the account a PLATFORM-scoped audit row is attributed to.
  #
  # Some records have no owning tenant — a global Ai::Agent (account_id nil,
  # is_system) is the consequential case, since its configuration governs what
  # a shared agent is permitted to do. `audit_logs.account_id` is null: false,
  # so such a row still needs an account to be attributed to, and the platform
  # sentinel is it.
  #
  # FAILS CLOSED. This used to end in `|| ::Account.first`, which meant that on
  # any platform without a sentinel, every global-agent change was written into
  # whichever tenant sorted first by primary key — and that tenant could read
  # it back through `current_user.account.audit_logs`
  # (audit_logs_controller.rb:170). A row naming the wrong party is worse than
  # a missing row, because the record exists precisely to be trusted; here it
  # was worse still, because the misfiled row was readable by a tenant with no
  # relationship to the event. Same call as 444be12f6 made for KB attribution:
  # when no principal resolves inside the correct scope, refusing is the only
  # honest option.
  #
  # Refusing silently would trade a wrong row for an invisible gap, so a miss
  # emits Auditable::SKIPPED_NOTIFICATION — the signal that concern already
  # defines "so the gap is countable in production rather than living only in a
  # log line" (auditable.rb:45).
  #
  # Deliberately NOT auto-provisioning the account: creating an Account as a
  # side effect of an audit callback is a large, surprising action taken at the
  # worst possible moment. Deliberately NOT configurable here either — how a
  # platform sentinel should exist at all is a design decision, and it should
  # not be settled inside a callback. Both remain open (improvement 019fd155).
  #
  # SHARED ON PURPOSE. System::LifecycleAuditable#record_lifecycle_audit! opens
  # `return unless account.present?` and then writes to this same audit_logs
  # table, so it has the identical root cause and needs the identical answer.
  # It is NOT wired up here — that is a separate call — but this is the seam to
  # call when it is, so the decision is made once rather than re-derived.
  module PlatformAccount
    SENTINEL_NAME = "Powernode Admin"

    MISSING_REASON = "no platform sentinel account (#{SENTINEL_NAME}) exists — " \
                     "refusing to attribute a platform audit row to a tenant"

    class << self
      # The sentinel, or nil. Never a fallback.
      def resolve
        ::Account.find_by(name: SENTINEL_NAME)
      end

      # Resolve for an audit write. On a miss, emits the skip signal naming the
      # record that went unaudited and returns nil, so the caller can `return
      # unless`.
      def resolve_for(model:, record_id:, action:)
        account = resolve
        return account if account

        ::ActiveSupport::Notifications.instrument(
          ::Auditable::SKIPPED_NOTIFICATION,
          model: model,
          record_id: record_id,
          action: action,
          reason: MISSING_REASON
        )
        nil
      end
    end
  end
end
