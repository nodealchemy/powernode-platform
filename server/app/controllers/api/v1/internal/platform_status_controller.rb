# frozen_string_literal: true

module Api
  module V1
    module Internal
      # The worker→server door for the component status sweep (design §4.5).
      #
      # The server runs no Sidekiq, so the CADENCE lives in the worker
      # (PlatformStatusSweepJob, every 60s) and the WORK lives here. This is
      # the same split the OODA closure driver and the report pipeline already
      # use: the worker owns the clock and calls in; the server owns every
      # gate, so the cron can tick unconditionally and a halted platform
      # simply reports that it skipped.
      #
      # Logic lives in ::Platform::Status::SweepRunner. This controller decides
      # only WHICH accounts to sweep and how long it may take.
      #
      # THE LEADING :: IS LOAD-BEARING. This class is lexically inside
      # Api::V1::Internal, and Api::V1::Platform exists (the component-status
      # REST surface), so a bare `Platform::Status::...` resolves to
      # `Api::V1::Platform::Status` and raises NameError. Worse, the
      # per-account rescue below would have caught it and reported a 200 with
      # an error string per account — a sweep that silently did nothing while
      # every response looked successful.
      class PlatformStatusController < InternalBaseController
        # Wall-clock ceiling for one request, borrowed from
        # ReportsController::MAX_SWEEP_SECONDS and for the same reason: the
        # caller is a 60-second cron with its own read timeout. A request that
        # outlives it reports failure for work that actually succeeded, and a
        # retry would sweep the same accounts again. Stopping early is safe —
        # the unswept accounts are picked up by the next tick, and their rows
        # simply keep the verdicts they had (the reap arm's three-sweep grace
        # exists precisely so a missed pass is survivable).
        MAX_SWEEP_SECONDS = 45

        # Accounts are swept in id order, which is stable, so a ceiling always
        # truncates a contiguous run rather than a random subset. WHERE that
        # run starts rotates between ticks — see ::Platform::Status::SweepCursor
        # for why a fixed starting point starves the same tail forever under a
        # systematic overrun (A2 review M2).
        BATCH_SIZE = 100

        # Reported for an account another caller is already sweeping. Not an
        # error: the sweep in flight produces exactly the events this one would.
        LOCKED_REASON = "locked"

        # POST /api/v1/internal/platform/status_sweep
        #
        # Sweeps every account. Optional `account_id` narrows it to one, which
        # is what a targeted re-check or a spec uses.
        def status_sweep
          started = Time.current
          summaries = []
          truncated = false
          last_swept_id = nil

          # `throw`, not `break`: the ceiling has to escape BOTH the batch
          # iteration and the outer list of scopes, and a break would only end
          # the inner one and silently continue with the next scope.
          catch(:ceiling_reached) do
            account_scopes.each do |scope|
              scope.find_each(batch_size: BATCH_SIZE) do |account|
                if Time.current - started > MAX_SWEEP_SECONDS
                  truncated = true
                  throw :ceiling_reached
                end

                last_swept_id = account.id
                summaries << sweep_one(account)
              end
            end
          end

          # Computed BEFORE the cursor moves: `ordered_accounts` is defined
          # relative to the cursor, so advancing first would report the tail of
          # a different ordering than the one this pass actually walked.
          unswept = unswept_report(truncated: truncated, swept_count: summaries.size)
          advance_cursor(truncated: truncated, last_swept_id: last_swept_id)

          render_success(
            accounts_swept: summaries.size,
            truncated: truncated,
            unswept: unswept,
            duration_seconds: (Time.current - started).round(3),
            events_pruned: prune_events,
            summaries: summaries
          )
        end

        private

        # ONE ACCOUNT, UNDER A LOCK THE DOOR OWNS (A2 review M5).
        #
        # The single-producer guarantee used to belong to the CALLER: the
        # worker's Redis lock guards the cron path and nothing else, while this
        # route also accepts a targeted `account_id` re-check and a second
        # worker calling directly. Two overlapping calls each read the same
        # pre-change verdict off the row and each record the transition — two
        # status_changed rows, two component_down rows and two broadcasts for
        # one change.
        #
        # See ::Platform::Status::AccountLock for why the lock is a Postgres
        # advisory one rather than the worker's Redis key.
        #
        # THE TRANSACTION IS THE LOCK'S SCOPE, and it has a cost worth naming:
        # an account's status rows and its events now commit together, which is
        # better for consistency, but a rollback after a broadcast has gone out
        # would leave a client told about an event that no longer exists. That
        # needs an exception to escape run!, which rescues per transition and
        # around the dwell pass — so it is narrow, and the per-account rescue
        # below reports it rather than hiding it.
        def sweep_one(account)
          ::ActiveRecord::Base.transaction do
            unless ::Platform::Status::AccountLock.try_acquire!(account)
              Rails.logger.info("[PlatformStatusSweep] account #{account.id} already being swept, skipping")
              next { account_id: account.id, skipped: true, reason: LOCKED_REASON }
            end

            summarize(account, ::Platform::Status::SweepRunner.run!(account))
          end
        rescue StandardError => e
          # One account's failure must not cost every other account its
          # sweep — the same discipline SweepService applies to a raising
          # contributor, applied one level up.
          Rails.logger.error("[PlatformStatusSweep] account #{account.id} failed: #{e.class}: #{e.message}")
          { account_id: account.id, error: "#{e.class}: #{e.message}" }
        end

        # Where the NEXT tick starts. A pass that finished the whole set clears
        # the cursor so the next one starts from the top; a truncated pass
        # leaves the last id it managed, so the next tick picks up the tail
        # that would otherwise never be swept.
        def advance_cursor(truncated:, last_swept_id:)
          return if params[:account_id].present?

          ::Platform::Status::SweepCursor.write(truncated ? last_swept_id : nil)
        end

        # Naming the starved accounts, because an unswept account keeps its
        # last verdicts with no staleness marker anywhere — `reap!` scopes to
        # the account being swept, so its rows are never even reap candidates.
        # A count and the first id is enough for an operator to see the shape.
        #
        # Counted by POSITION in the pass's own ordering rather than by an
        # `id > last_swept` comparison. Two reasons, both of which produced
        # real failures: the rotation wraps, so "greater than the last id" is
        # not the unswept set; and a pass that truncates before its FIRST
        # account has no last id at all, which turned into `id > ''` and a
        # cast error from Postgres.
        def unswept_report(truncated:, swept_count:)
          return { count: 0, first_id: nil } unless truncated

          remaining = account_scopes.sum(&:count) - swept_count
          { count: [ remaining, 0 ].max, first_id: account_id_at(swept_count) }
        end

        # The id at position `offset` in the pass's own order, walking the
        # scopes in sequence. Counted by POSITION rather than by an
        # `id > last_swept` comparison, because the rotation WRAPS and because
        # a pass that truncates before its first account has no last id at all.
        def account_id_at(offset)
          account_scopes.each do |scope|
            size = scope.count
            return scope.offset(offset).limit(1).pick(:id) if offset < size

            offset -= size
          end
          nil
        end

        # ONCE PER REQUEST, not once per account: retention is global and
        # account-independent (see ::Platform::Status::EventRetention).
        #
        # Gated on the STANDBY fence only. The fence's promise is that a
        # standby plane does nothing at all, and two planes sharing a database
        # should not both be deleting from it. The per-account kill switch is
        # deliberately NOT consulted: it suspends one tenant's AI activity, and
        # letting one suspended account freeze retention for every other
        # account would be an unrelated side effect of an unrelated switch.
        #
        # Never raises. Housekeeping that fails must not turn a successful
        # sweep into a failed request, and the next tick tries again.
        def prune_events
          return 0 unless ::Platform::Status::SweepRunner.control_plane_active?

          ::Platform::Status::EventRetention.prune!
        rescue StandardError => e
          Rails.logger.error("[PlatformStatusSweep] event retention failed: #{e.class}: #{e.message}")
          0
        end

        # Ordered ALWAYS, including the single-account branch: the
        # stable-order argument is stated for both, and a scope that is ordered
        # only sometimes invites a caller to assume it never is.
        # The accounts to sweep, IN ORDER, as a list of id-ordered scopes.
        #
        # TWO SCOPES RATHER THAN ONE CUSTOM ORDER, and this is a bug fix, not a
        # style choice: `find_each` IGNORES any ordering you give it — it forces
        # `ORDER BY id ASC` so it can page by id. A single relation with a
        # rotated `ORDER BY` therefore came back in plain id order and the
        # cursor did nothing at all, while every unit of the cursor itself
        # passed. Splitting the rotation into "after the cursor" then "up to
        # the cursor" gives two scopes that are each genuinely id-ordered, so
        # batching and rotation stop fighting.
        def account_scopes
          @account_scopes ||= build_account_scopes
        end

        def build_account_scopes
          return [ ::Account.where(id: params[:account_id]).order(:id) ] if params[:account_id].present?

          cursor = valid_cursor
          return [ ::Account.order(:id) ] if cursor.blank?

          [ ::Account.where("id > ?", cursor).order(:id),
            ::Account.where("id <= ?", cursor).order(:id) ]
        end

        # A cursor that is not a UUID would make Postgres raise on the cast.
        # It is scheduler bookkeeping from an external store, so it is
        # validated rather than trusted; a malformed one simply means "start
        # from the top".
        def valid_cursor
          cursor = ::Platform::Status::SweepCursor.read
          return nil if cursor.blank?
          return nil unless cursor.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

          cursor
        end

        # The transitions array carries model ids and timestamps that no worker
        # needs; the worker only logs totals. Sending the whole thing would put
        # every transition on the platform through a JSON round trip once a
        # minute for no reader.
        #
        # `event_failures` IS CARRIED EVEN WHEN ZERO, and deliberately so. The
        # runner rescues per transition so one bad emission cannot discard the
        # rest of the account's tick; that rescue is only defensible if the
        # count it produces reaches a reader. Dropped here, a sweep that failed
        # to emit every single event would report the same shape as a clean one
        # — the silent-PASS this campaign exists to remove.
        #
        # It is NOT run through `.compact`'s reach by being left nil: `.to_i`
        # makes it a real 0, so "no failures" and "the door forgot to report
        # failures" are different values rather than the same absent key.
        def summarize(account, result)
          {
            account_id: account.id,
            skipped: result[:skipped],
            reason: result[:reason],
            transitions: Array(result[:transitions]).size,
            events_written: result[:events_written].to_i,
            event_failures: result[:event_failures].to_i,
            reaped: result[:reaped].to_i,
            kinds: Array(result[:kinds]&.keys).size
          }.compact
        end
      end
    end
  end
end
