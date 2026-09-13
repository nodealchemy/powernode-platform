# frozen_string_literal: true

module Platform
  # Reopened, not declared: `Platform::Investigation` is the ActiveRecord
  # class in app/models. Zeitwerk resolves the namespace from that file
  # before loading this child, so `class` here is a reopen and `module`
  # would be a TypeError.
  class Investigation
    # WHICH EVENT KINDS OPEN AN INVESTIGATION AUTOMATICALLY (design §5.3).
    #
    # Core knows exactly one of them: a `platform_subsystem` component
    # transitioning to `down`. The other — `fleet.remediation_stuck` — is an
    # EXTENSION's event kind, and core naming it in a constant would be core
    # depending on an extension by name, which the architecture forbids
    # outright.
    #
    # So the kinds are a registry the extension fills from its own engine:
    #
    #   Platform::Investigation::Triggers.register("fleet.remediation_stuck")
    #
    # ── WHY A SET OF STRINGS AND NOT A CALLABLE ─────────────────────────────
    # Every other seam in this plane registers behaviour. This one registers a
    # NAME, because the behaviour is core's: core decides whether to open an
    # investigation, subject to the open-fingerprint rule and the daily cap.
    # If an extension registered a callable it could open investigations that
    # skip both bounds, and the cap would be advisory.
    module Triggers
      # The one kind core knows without being told. It is a COMPONENT KIND
      # rather than an event kind because core owns the status plane's own
      # vocabulary; `platform_subsystem` is registered by the system extension
      # but the string is core's to react to, exactly as `docker_host` names a
      # kind without naming a model.
      SUBSYSTEM_KIND = "platform_subsystem"

      MUTEX = Mutex.new
      private_constant :MUTEX

      class << self
        # @param kind [String] an event kind an extension wants to trigger on
        def register(kind)
          key = normalize(kind)
          raise ArgumentError, "trigger kind must be present" if key.blank?

          MUTEX.synchronize { store[key] = true }
          key
        end

        def unregister(kind)
          MUTEX.synchronize { store.delete(normalize(kind)) }
        end

        def registered?(kind)
          MUTEX.synchronize { store.key?(normalize(kind)) }
        end

        def kinds
          MUTEX.synchronize { store.keys.dup.freeze }
        end

        # Spec seam. Never call from application code.
        def reset!
          MUTEX.synchronize { store.clear }
        end

        private

        def store
          @store ||= {}
        end

        def normalize(kind)
          kind.to_s.strip
        end
      end
    end
  end
end
