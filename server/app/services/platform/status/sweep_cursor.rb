# frozen_string_literal: true

module Platform
  module Status
    # WHERE THE NEXT SWEEP STARTS (A2 review M2).
    #
    # The door sweeps accounts in `id` order under a wall-clock ceiling. That
    # is fine for a one-off overrun — the leftovers go on the next tick — and
    # WRONG for the systematic case that truncation actually signals: if every
    # tick exceeds the ceiling, every tick truncates at the same place, and the
    # SAME tail is never swept on any tick, ever.
    #
    # The starved accounts do not even look starved. `reap!` scopes to the
    # account being swept, so an unswept account's rows are never reap
    # candidates: they keep their last verdicts indefinitely, with no staleness
    # marker anywhere on the plane whose entire purpose is not lying about
    # state. A screen confidently showing an hour-old `ok` is precisely the
    # failure this plane exists to end.
    #
    # So the starting point ROTATES. Each pass records the last account it
    # swept; the next pass starts after it and wraps at the end. Over enough
    # ticks every account is swept even if no single tick can finish.
    #
    # ── WHY REDIS AND NOT A COLUMN ──────────────────────────────────────────
    # This is scheduler bookkeeping, not platform state: it is per-deployment,
    # it is worthless after a restart, and losing it costs one tick starting
    # from the top. A column would put a write on the accounts table (or a new
    # table) once a minute forever to store something nobody audits.
    #
    # EVERY OPERATION IS BEST-EFFORT. A Redis outage must not stop a sweep —
    # the fallback is "start from the beginning", which is exactly the
    # behaviour that existed before this class. A cursor that cannot be read is
    # a slower sweep, never a failed one.
    class SweepCursor
      REDIS_KEY = "platform:status:sweep:cursor"

      # Long enough to survive a deploy, short enough that a cursor pointing at
      # a deleted account expires on its own rather than needing a cleanup.
      TTL_SECONDS = 3600

      class << self
        # @return [String, nil] the last account id swept, or nil to start from
        #   the top
        def read
          redis { |conn| conn.get(REDIS_KEY).presence }
        end

        # @param account_id [String, nil] nil CLEARS the cursor, which is what a
        #   pass that finished the whole set should do: the next tick starts
        #   from the top rather than from wherever the last one happened to end.
        def write(account_id)
          redis do |conn|
            account_id.blank? ? conn.del(REDIS_KEY) : conn.set(REDIS_KEY, account_id.to_s, ex: TTL_SECONDS)
          end
        end

        def clear
          write(nil)
        end

        private

        def redis
          yield ::Powernode::Redis.client
        rescue StandardError => e
          Rails.logger.warn("[Platform::Status] sweep cursor unavailable: #{e.class}: #{e.message}")
          nil
        end
      end
    end
  end
end
