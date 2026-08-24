# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Single definition of the tenancy anchor for the worker-facing internal
      # API (`/api/v1/internal/**`), authenticated by
      # InternalBaseController#authenticate_worker_via_mtls!.
      #
      # WHY THIS EXISTS AS ONE THING. Every controller on this seam that looks a
      # record up by a bare, caller-supplied id must constrain that lookup to the
      # calling worker's account, or a principal that authenticates here reads
      # (or writes) another account's row by enumerable id. e9352723d and
      # 0f4b6e1db each fixed this by hand in `internal/ai/*`, and the class
      # promptly reappeared in six MORE controllers that were never touched — a
      # second, copied definition of the anchor is exactly how it regenerates.
      # So the anchor lives here, once, and every call site derives its scope
      # from `worker_account_id` rather than re-deriving `current_worker.account`.
      #
      # THE ANCHOR IS THE PRINCIPAL, NEVER A PARAMETER. `worker_account_id` reads
      # only `current_worker`, which MtlsClientAuthentication set from the
      # verified/forwarded client-cert CN. No value from `params`, a header, or a
      # request body feeds it, so no caller-supplied input can WIDEN it: the scope
      # holds even when the forwarded-CN identity is FORGED — asserting a worker
      # CN gets you that worker's account and nothing beyond it. This is the same
      # property e9352723d relied on; it is reused here, not re-derived.
      #
      # NO `is_system` EXEMPTION, DELIBERATELY. The principal on this seam in
      # production is an ACCOUNT-BOUND worker: `workers.node_instance_id` is
      # written only by
      # extensions/system/server/lib/tasks/worker_provision.rake, which binds
      # each Worker to an operator-supplied account and leaves `is_system` at its
      # column default of false. `EnsureSystemWorker#bind_dev_sentinel` is the
      # only producer that touches the system worker, and it binds the sentinel
      # ONLY in development; outside development the sentinel is actively REVOKED
      # (by that method and at boot by
      # config/initializers/worker_dev_sentinel_revocation.rb). An `is_system`
      # exemption would therefore be INERT in production while, before that first
      # boot in a dev-bootstrapped database, handing unrestricted cross-account
      # reach to anyone presenting the PUBLISHED constant
      # EnsureSystemWorker::DEV_SENTINEL_NODE_ID. Controllers that legitimately
      # need cross-account reach (account lifecycle / GDPR erasure run by the
      # system worker) must NOT include this concern; they declare that intent
      # explicitly and are exempted by name in the namespace tenancy sweep.
      #
      # SCOPE BY THE COLUMN, NOT THE ASSOCIATION — IT FAILS CLOSED. Callers use
      # `worker_account_id` inside `where(account_id: ...)` (or a join onto the
      # owning table's `account_id`), never `current_worker.account`.
      # `workers.account_id` is NULLABLE at the DB level, so a half-provisioned
      # or nil principal yields `nil`; `where(account_id: nil)` matches NO rows
      # instead of raising, and every credential/host/server table scoped here
      # has a NOT NULL `account_id`, so no real row is ever caught by a NULL
      # scope. A nil principal is therefore denied, not granted.
      #
      # A cross-account lookup must 404 (RecordNotFound -> "not found"), NEVER
      # 403: a 403 would confirm the row EXISTS on another account, which is
      # itself a disclosure. `find_by!`/`find` on the scoped relation gives the
      # 404 for free.
      module WorkerTenancy
        extend ActiveSupport::Concern

        private

        # The tenancy VALUE: the authenticated Worker principal's own
        # `account_id` COLUMN. See the module comment for why this is the column
        # and not `current_worker.account`, and why there is no `is_system`
        # exemption. Callers MUST use this inside a `where`/`joins` scope so a
        # nil value fails closed.
        def worker_account_id
          current_worker&.account_id
        end
      end
    end
  end
end
