# frozen_string_literal: true

module Platform
  module Status
    # THE PRODUCER (design §4.3, §4.5). Guards, then sweep, then exactly one
    # set of events and one broadcast per transition, then the mirror seam.
    #
    # A1's SweepService computes verdicts and RETURNS transitions; it writes no
    # event and sends no broadcast. This class is the only thing that turns a
    # transition into a record. Splitting it that way is what makes "one
    # producer, always" checkable: the producer is one class, and a spec can
    # assert that a sweep with no transitions writes nothing at all.
    #
    # ── GUARDS RUN BEFORE ANY WRITE, AND THAT ORDERING IS THE POINT ─────────
    # A halted platform must not merely stop broadcasting; it must not sweep.
    # Evaluating the guards after the sweep would leave the status rows
    # updated (they are written by SweepService itself) while the operator
    # believes everything is frozen. So the guards are checked first and the
    # sweep is never called.
    #
    #   1. Kill switch — `account.ai_suspended?`, the same flag
    #      Ai::Autonomy::KillSwitchService sets and every worker job's
    #      suspension check reads. Not a second mechanism: the account flag IS
    #      the source of truth, and inventing a status-plane-specific halt
    #      would give an operator two switches that can disagree.
    #   2. Dual-plane standby fence — a standby control plane does nothing.
    #
    # ── THE STANDBY FENCE AND WHY IT GOES THROUGH A SEAM ────────────────────
    # The role decision needs a quorum reading from the host, which is fleet
    # logic and lives in an extension. Core must not name that extension, so
    # the role is resolved through the generic provider seam
    # (`Powernode::ExtensionRegistry.provider(:control_plane_role)`).
    #
    # STATED PLAINLY BECAUSE IT MATTERS: with no provider registered, this
    # resolves to nil and the fence is INERT — a single-plane or core-mode
    # deployment sweeps normally, which is correct for it and is the
    # documented nil-default of the provider seam. It also means that on a
    # dual-plane deployment the fence does nothing until the provider is
    # registered. This class cannot fix that from core; what it CAN do, and
    # does, is fail toward "do nothing" whenever a provider IS registered and
    # cannot give a clean answer: a provider that raises is treated as
    # standby, never as active. A safety device that reports "active" when it
    # is confused is worse than no safety device, because it is trusted.
    class SweepRunner
      REASON_KILL_SWITCH = "kill_switch"
      REASON_STANDBY     = "standby"

      # The provider key an extension registers to arm the dual-plane fence.
      # Its object answers `active?`.
      CONTROL_PLANE_ROLE_PROVIDER = :control_plane_role

      class << self
        def run!(account, now: Time.current)
          new(account: account, now: now).run!
        end

        # True when this plane may act. Nil provider ⇒ core mode ⇒ active.
        # A provider that raises ⇒ NOT active (fail toward doing nothing).
        def control_plane_active?
          provider = ::Powernode::ExtensionRegistry.provider(CONTROL_PLANE_ROLE_PROVIDER)
          return true if provider.nil?

          provider.active?
        rescue StandardError => e
          Rails.logger.error(
            "[Platform::Status] control-plane role unreadable, treating as standby: #{e.class}: #{e.message}"
          )
          false
        end
      end

      def initialize(account:, now: Time.current)
        @account = account
        @now = now
      end

      def run!
        halted = halt_reason
        return { account_id: @account&.id, skipped: true, reason: halted } if halted

        summary = SweepService.run_once!(@account, now: @now)
        events = Array(summary[:transitions]).flat_map { |transition| publish(transition) }

        summary.merge(skipped: false, events_written: events.size)
      end

      private

      # Returns the reason string of the FIRST guard that halts, or nil.
      def halt_reason
        return REASON_KILL_SWITCH if @account.respond_to?(:ai_suspended?) && @account.ai_suspended?
        return REASON_STANDBY unless self.class.control_plane_active?

        nil
      end

      # One transition in, the event rows out. Order matters: the durable
      # record is written FIRST, then the broadcast, then the mirrors. A
      # dropped WebSocket frame costs a client a refresh; a lost event row
      # costs the platform its history of an outage.
      def publish(transition)
        events = write_events(transition)
        broadcast(transition, events)
        Emitters.notify(transition: transition, events: events)
        events
      end

      def write_events(transition)
        kinds = [ StatusEvent::KIND_STATUS_CHANGED ]
        kinds << StatusEvent::KIND_COMPONENT_DOWN if transition[:to].to_s == ComponentStatus::DOWN

        kinds.map { |kind| StatusEvent.create!(**event_attributes(transition, kind)) }
      end

      def event_attributes(transition, kind)
        {
          account_id: transition[:account_id],
          component_status_id: transition[:component_status_id],
          component_kind: transition[:component_kind],
          component_ref: transition[:component_ref],
          kind: kind,
          from_verdict: transition[:from],
          to_verdict: transition[:to],
          occurred_at: transition[:at] || @now,
          payload: {
            "swept_account_id" => @account&.id,
            "shared" => transition[:account_id].nil?
          }
        }
      end

      # EXACTLY ONE broadcast per transition, routed by tenancy: an
      # account-scoped component to its account's stream, a shared one to the
      # shared stream. See PlatformStatusChannel for why it is not fanned out
      # to every account.
      #
      # Rescued because a Redis hiccup in the cable adapter must not roll back
      # events that are already committed, nor stop the remaining transitions
      # from being recorded.
      def broadcast(transition, events)
        PlatformStatusChannel.broadcast_transition(transition[:account_id], {
          type: "component_status_changed",
          component_kind: transition[:component_kind],
          component_ref: transition[:component_ref],
          from_verdict: transition[:from],
          to_verdict: transition[:to],
          shared: transition[:account_id].nil?,
          event_ids: events.map(&:id),
          occurred_at: (transition[:at] || @now).iso8601
        })
      rescue StandardError => e
        Rails.logger.error("[Platform::Status] broadcast failed: #{e.class}: #{e.message}")
      end
    end
  end
end
