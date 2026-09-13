# frozen_string_literal: true

module Platform
  # Reopened, not declared: `Platform::Investigation` is the ActiveRecord
  # class in app/models. Zeitwerk resolves the namespace from that file
  # before loading this child, so `class` here is a reopen and `module`
  # would be a TypeError.
  class Investigation
    # THE AUTOMATIC TRIGGER (design §5.3), registered as a status emitter.
    #
    # Core reacts to exactly one thing it knows by itself: a `platform_subsystem`
    # component transitioning to `down`. Everything else arrives through
    # `Platform::Investigation::Triggers`, which an extension fills with its own
    # event kinds (`fleet.remediation_stuck`) — core names none of them.
    #
    # ── AN EMITTER, SO IT CANNOT BECOME A SECOND PRODUCER ───────────────────
    # It runs AFTER the status events are written and the broadcast has gone
    # out, and its return value is discarded. It cannot amend a verdict, and a
    # failure here cannot suppress the record of an outage.
    #
    # ── EVERY BOUND IS THE SERVICE'S ────────────────────────────────────────
    # This decides only WHETHER a transition is interesting. Whether an
    # investigation may actually be opened — the open-fingerprint rule and the
    # per-account daily cap — is `Platform::InvestigationService`'s, so the
    # operator verb and this trigger are bounded by one rule rather than two
    # that can disagree.
    module TriggerEmitter
      class << self
        # @return [Hash, nil] the service's result, or nil when the transition
        #   is not one core investigates
        def handle(transition:, events: [])
          return nil unless transition.is_a?(Hash)

          to = (transition[:to] || transition["to"]).to_s
          kind = (transition[:component_kind] || transition["component_kind"]).to_s

          trigger = trigger_for(kind, to, events)
          return nil if trigger.nil?

          component = component_for(transition)
          return nil if component.nil?

          ::Platform::InvestigationService.new(account: component.account)
                                          .open!(component, trigger: trigger)
        rescue StandardError => e
          Rails.logger.error("[Platform::Investigation] trigger failed: #{e.class}: #{e.message}")
          nil
        end

        private

        # `down` on the one kind core knows, or any event kind an extension has
        # registered. A transition to nil (a reap) is never investigated: the
        # component is gone, so there is nothing left to investigate.
        def trigger_for(component_kind, to_verdict, events)
          if component_kind == Triggers::SUBSYSTEM_KIND &&
             to_verdict == ::Platform::ComponentStatus::DOWN
            return ::Platform::Investigation::TRIGGER_DOWN
          end

          return ::Platform::Investigation::TRIGGER_STUCK if registered_kind?(events)

          nil
        end

        def registered_kind?(events)
          Array(events).any? do |event|
            kind = event.respond_to?(:kind) ? event.kind : (event.is_a?(Hash) ? event[:kind] || event["kind"] : nil)
            kind.present? && Triggers.registered?(kind)
          end
        end

        def component_for(transition)
          id = transition[:component_status_id] || transition["component_status_id"]
          return nil if id.blank?

          ::Platform::ComponentStatus.find_by(id: id)
        end
      end
    end
  end
end
