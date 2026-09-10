# frozen_string_literal: true

module Platform
  module Status
    # HOW LONG AN OUTAGE IS WORTH REMEMBERING.
    #
    # A1 reaps status ROWS — current state for a component whose record is
    # gone. Nothing reaped HISTORY, so `platform_status_events` grew without
    # bound: on a flapping fleet that is a table nobody ever reads the far end
    # of, slowing every query that does read it.
    #
    # Thirty days by default because that is the window in which someone asks
    # "what happened last month" and beyond which they ask a data warehouse
    # instead. It is a SiteSetting rather than a constant for the same reason
    # the sweep interval is: retention is a policy an operator owns, and a
    # deployment that must keep a quarter of history should not need a deploy
    # to say so.
    #
    # ── THIS IS GLOBAL, NOT PER-ACCOUNT ─────────────────────────────────────
    # It runs ONCE per sweep request, not once per account. Retention is
    # janitorial and account-independent, and the alternative — a delete per
    # account per minute — would be dozens of statements a tick to avoid one
    # index. (That index exists: see the migration, which also explains why it
    # is not the same mistake A1 review L1 removed.)
    #
    # ── BOUNDED ON PURPOSE ──────────────────────────────────────────────────
    # A first run against a table that has never been pruned could otherwise
    # be a single enormous DELETE holding locks while a 60-second cron waits.
    # Each pass deletes at most MAX_ROWS_PER_RUN; the leftovers go on the next
    # tick, and there is no deadline by which they must be gone.
    class EventRetention
      RETENTION_SETTING = "platform.status.event_retention_days"
      DEFAULT_RETENTION_DAYS = 30

      # Ceiling per pass. Chosen to be far above a normal tick's backlog (a
      # steady fleet produces transitions, not thousands of them) and far
      # below "one statement that locks the table for a visible pause".
      MAX_ROWS_PER_RUN = 5_000

      class << self
        # Days of history kept. A blank or non-positive setting is the
        # default, NOT zero — a zero-day retention read literally would delete
        # every event the moment it was written, and a typo in a settings form
        # should not be able to do that.
        def retention_days
          configured = ::SiteSetting.get(RETENTION_SETTING)
          configured.present? && configured.to_i.positive? ? configured.to_i : DEFAULT_RETENTION_DAYS
        end

        def cutoff(now: Time.current)
          now - retention_days.days
        end

        # @return [Integer] how many rows were deleted
        def prune!(now: Time.current)
          ids = StatusEvent.where(occurred_at: ...cutoff(now: now))
                           .limit(MAX_ROWS_PER_RUN)
                           .pluck(:id)
          return 0 if ids.empty?

          StatusEvent.where(id: ids).delete_all
        end
      end
    end
  end
end
