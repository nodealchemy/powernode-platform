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
      # Logic lives in Platform::Status::SweepRunner. This controller decides
      # only WHICH accounts to sweep and how long it may take.
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
        # truncates the same tail rather than a random subset — and the next
        # tick starts from the top again. Fairness across a large installed
        # base is a problem for the day this platform has one; today the
        # honest ceiling beats a half-built rotation.
        BATCH_SIZE = 100

        # POST /api/v1/internal/platform/status_sweep
        #
        # Sweeps every account. Optional `account_id` narrows it to one, which
        # is what a targeted re-check or a spec uses.
        def status_sweep
          started = Time.current
          summaries = []
          truncated = false

          accounts_scope.find_each(batch_size: BATCH_SIZE) do |account|
            if Time.current - started > MAX_SWEEP_SECONDS
              truncated = true
              break
            end

            summaries << summarize(account, Platform::Status::SweepRunner.run!(account))
          rescue StandardError => e
            # One account's failure must not cost every other account its
            # sweep — the same discipline SweepService applies to a raising
            # contributor, applied one level up.
            Rails.logger.error("[PlatformStatusSweep] account #{account.id} failed: #{e.class}: #{e.message}")
            summaries << { account_id: account.id, error: "#{e.class}: #{e.message}" }
          end

          render_success(
            accounts_swept: summaries.size,
            truncated: truncated,
            duration_seconds: (Time.current - started).round(3),
            summaries: summaries
          )
        end

        private

        def accounts_scope
          return ::Account.where(id: params[:account_id]) if params[:account_id].present?

          ::Account.order(:id)
        end

        # The transitions array carries model ids and timestamps that no worker
        # needs; the worker only logs totals. Sending the whole thing would put
        # every transition on the platform through a JSON round trip once a
        # minute for no reader.
        def summarize(account, result)
          {
            account_id: account.id,
            skipped: result[:skipped],
            reason: result[:reason],
            transitions: Array(result[:transitions]).size,
            events_written: result[:events_written].to_i,
            reaped: result[:reaped].to_i,
            kinds: Array(result[:kinds]&.keys).size
          }.compact
        end
      end
    end
  end
end
