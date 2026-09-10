# frozen_string_literal: true

module Platform
  module Status
    # ONE SWEEP PER ACCOUNT AT A TIME, ENFORCED BY THE DOOR (A2 review M5).
    #
    # The single-producer property used to belong to the CALLER. The worker
    # holds a Redis lock around the cron tick — but that guards the cron path
    # and nothing else, while the internal route also accepts a targeted
    # `account_id` re-check and a second worker calling directly. Two
    # overlapping calls each read the same pre-change verdict off the status
    # row and each record the transition: two `status_changed` rows, two
    # `component_down` rows, two broadcasts, for one change.
    #
    # ── WHY A POSTGRES ADVISORY LOCK AND NOT THE REDIS ONE ──────────────────
    # It is held for the TRANSACTION and released by the database when that
    # transaction ends however it ends — commit, rollback, or a connection that
    # died mid-sweep. So it needs no TTL, which means nobody has to guess how
    # long a sweep takes and nothing is left holding a lock it lost the right
    # to. The Redis lock in the worker needs a TTL precisely because Redis
    # cannot know the holder is gone.
    #
    # `pg_try_advisory_xact_lock` NEVER WAITS. A concurrent caller skips rather
    # than queueing: the sweep already running is about to produce exactly the
    # events the second one would have produced, so waiting for it buys nothing
    # and holds a request open for the duration.
    #
    # ── REENTRANCY, STATED BECAUSE IT LOOKS LIKE A BUG IN SPECS ─────────────
    # Advisory locks are per-SESSION, so the SAME connection can re-acquire a
    # key it already holds. In production that is irrelevant — two overlapping
    # HTTP requests are two connections out of the pool. In a spec with
    # transactional fixtures everything shares one connection, so a second call
    # inside one example appears to acquire the lock. That is why the spec for
    # this class uses a real second connection rather than asserting the
    # controller's behaviour twice.
    class AccountLock
      # Namespace half of the two-int advisory key ("PNST"), so this cannot
      # collide with any other advisory lock in the platform that happens to
      # hash an id to the same 32 bits.
      NAMESPACE = 0x504E5354

      class << self
        # MUST be called inside a transaction — an xact lock outside one is
        # taken and released immediately, which would silently be no lock at
        # all. Returns false rather than raising when the lock is held.
        #
        # @return [Boolean] true when this transaction now owns the account
        def try_acquire!(account)
          ::ActiveRecord::Base.connection.select_value(
            ::ActiveRecord::Base.sanitize_sql_array(
              [ "SELECT pg_try_advisory_xact_lock(?, ?)", NAMESPACE, key_for(account) ]
            )
          )
        end

        # A stable signed-32-bit key from the account's UUID. SHA256 rather
        # than `hash`, because Ruby's `hash` is salted per process and two web
        # processes would derive different keys for the same account — a lock
        # that only ever locks against itself.
        def key_for(account)
          id = account.respond_to?(:id) ? account.id : account
          unsigned = ::Digest::SHA256.hexdigest(id.to_s)[0, 8].to_i(16)
          unsigned >= 2**31 ? unsigned - 2**32 : unsigned
        end
      end
    end
  end
end
