# frozen_string_literal: true

module Platform
  module Remediation
    # WHERE LANES COME FROM. Keyed by SIGNAL KIND, one lane per kind.
    #
    #   Platform::Remediation::Registry.register_lane("instance.silent", MyLane.new)
    #
    # Deliberately the same shape as Platform::Status::Registry — same Mutex,
    # same frozen copy handed to readers, same idempotent last-write-wins
    # registration — because it has the same lifecycle: registered from an
    # engine's `to_prepare` (which re-runs per code reload, on a thread that is
    # not the one serving requests) and read from a worker-driven sweep. Two
    # registries with the same lifecycle and different concurrency rules is how
    # one of them acquires an intermittent bug nobody can reproduce.
    #
    # ── THE DEFAULT IS `not_actuatable` ─────────────────────────────────────
    # An unregistered kind is not an error and not a gap to be filled in later
    # by guessing. It is the answer: nothing has claimed the authority to act
    # on this signal, so the front door reports `not_actuatable` with the
    # reason rendered and offers the runbook instead. Design §5.1 states this
    # for `platform_subsystem` in particular — every recommendation about the
    # control plane's own components is `not_actuatable` unless a registered
    # lane claims the kind, and the only lane that may claim it is one that
    # runs the self-management fence.
    #
    # That property is a consequence of this registry being empty by default
    # rather than a special case written anywhere: core registers no lane at
    # all, so core cannot actuate anything on its own behalf.
    module Registry
      MUTEX = Mutex.new
      private_constant :MUTEX

      class << self
        # @param signal_kind [String, Symbol]
        # @param lane [#describe] anything answering the
        #   Platform::Remediation::Lane contract
        # @return [Object] the lane
        def register_lane(signal_kind, lane)
          key = normalize(signal_kind)
          raise ArgumentError, "signal_kind must be present" if key.blank?
          raise ArgumentError, "lane must respond to #describe" unless lane.respond_to?(:describe)

          MUTEX.synchronize { store[key] = lane }
          lane
        end

        # The lane claiming this kind, or nil.
        def lane_for(signal_kind)
          MUTEX.synchronize { store[normalize(signal_kind)] }
        end

        def registered?(signal_kind)
          !lane_for(signal_kind).nil?
        end

        # {signal_kind => lane}, a frozen COPY — a reader must never iterate a
        # Hash a reload may be mutating.
        def lanes
          MUTEX.synchronize { store.dup.freeze }
        end

        def signal_kinds
          lanes.keys
        end

        # Removes a kind's lane. Returns the lane that was removed, or nil.
        def unregister(signal_kind)
          MUTEX.synchronize { store.delete(normalize(signal_kind)) }
        end

        # Spec seam. Never call this from application code.
        def reset!
          MUTEX.synchronize { store.clear }
        end

        private

        def store
          @store ||= {}
        end

        def normalize(signal_kind)
          signal_kind.to_s.strip
        end
      end
    end
  end
end
