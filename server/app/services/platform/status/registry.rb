# frozen_string_literal: true

module Platform
  module Status
    # WHERE KINDS COME FROM. Core registers a few; extensions register the
    # rest from their engine's `to_prepare`; core never names an extension.
    #
    #   Platform::Status::Registry.register("ai_provider", AiProviderContributor.new)
    #
    # THREAD SAFETY, and why it is not paranoia. Registration happens at boot
    # AND on every `to_prepare` (which fires per code reload in development,
    # on a thread that is not necessarily the one serving requests), while the
    # sweep reads the table from a worker-driven request. A bare Hash mutated
    # during a concurrent read is exactly the shape that produces an
    # intermittent, unreproducible "kind vanished" in development and never in
    # a spec. A Mutex around every mutation and a frozen copy handed to every
    # reader costs nothing at this size and removes the failure mode.
    #
    # REGISTRATION IS IDEMPOTENT AND LAST-WRITE-WINS. `to_prepare` re-runs, so
    # re-registering the same kind must not raise; and a reloaded contributor
    # class must REPLACE its stale predecessor, or development would keep
    # serving the old code. The trade-off is that two extensions claiming one
    # kind silently resolve to whichever registered last — the same hazard the
    # frontend slot registry documents. Kinds are namespaced by convention to
    # keep that from happening by accident.
    module Registry
      MUTEX = Mutex.new
      private_constant :MUTEX

      class << self
        # @param kind [String, Symbol] registry key, snake_case
        # @param contributor [#each_component] anything answering the
        #   Platform::Status::Contributor contract
        def register(kind, contributor)
          key = normalize(kind)
          raise ArgumentError, "kind must be present" if key.blank?
          raise ArgumentError, "contributor must respond to #each_component" unless contributor.respond_to?(:each_component)

          MUTEX.synchronize { store[key] = contributor }
          contributor
        end

        # Removes a kind. Used by specs, and by an extension that unloads.
        # Returns the contributor that was removed, or nil.
        def unregister(kind)
          MUTEX.synchronize { store.delete(normalize(kind)) }
        end

        def fetch(kind)
          MUTEX.synchronize { store[normalize(kind)] }
        end

        def registered?(kind)
          !fetch(kind).nil?
        end

        # {kind => contributor}, a frozen COPY. Callers iterate this while a
        # reload may be registering; handing out the live Hash would let a
        # sweep iterate a Hash being mutated.
        def contributors
          MUTEX.synchronize { store.dup.freeze }
        end

        def kinds
          contributors.keys
        end

        # Spec seam. Never call this from application code: it would silently
        # empty the registry for every other request in the process.
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
