# frozen_string_literal: true

module Platform
  module Status
    # THE MIRROR SEAM (design §4.3). Anything that wants to know about a
    # verdict transition — without being the thing that records it — registers
    # here.
    #
    #   Platform::Status::Emitters.register(:fleet_feed) do |transition:, events:|
    #     ...
    #   end
    #
    # PULL, NEVER PUSH. Core does not know that a fleet feed exists, does not
    # call it, and does not name it. The extension reaches into core from its
    # own engine's `to_prepare` and takes what it wants. Reverse that — core
    # pushing into a named downstream — and core acquires a dependency on
    # every consumer that will ever exist, which is precisely the direction
    # the architecture forbids.
    #
    # THIS IS NOT A SECOND PRODUCER. Emitters run AFTER the status events are
    # written and the broadcast has gone out, and their return value is
    # discarded. An emitter mirrors; it does not decide. If an emitter could
    # veto or amend the event, "one producer, always" would be a comment
    # rather than a property.
    #
    # AN EMITTER THAT RAISES IS THE EMITTER'S PROBLEM. It is logged and the
    # next one still runs, because the alternative is that a mirror into some
    # secondary feed can suppress the primary record of an outage. The event
    # rows are already committed by the time any emitter is called, so there
    # is nothing an emitter can do to lose them.
    #
    # Built on the shared Powernode::HandlerRegistry shape (register /
    # unregister / registered? / names / handlers / reset!), so this seam
    # cannot drift from the other inversion-of-control registries in core.
    # Registration is by NAME rather than by bare callable: `to_prepare` runs
    # again on every reload, and a name is what lets the second registration
    # REPLACE the first instead of stacking a duplicate emitter that mirrors
    # every transition twice.
    module Emitters
      extend ::Powernode::HandlerRegistry

      class << self
        # Fan out one transition to every registered emitter. Each is called
        # with keywords so a later increment can add context without breaking
        # emitters written against today's contract.
        #
        # @param transition [Hash] one entry from SweepService's :transitions
        # @param events [Array<Platform::StatusEvent>] the rows already written
        # @return [Integer] how many emitters were called (raising ones included)
        def notify(transition:, events:)
          each do |name, handler|
            handler.call(transition: transition, events: events)
          rescue StandardError => e
            Rails.logger.error(
              "[Platform::Status::Emitters] emitter #{name} failed: #{e.class}: #{e.message}"
            )
          end
          handlers.size
        end

        # Iterate name => handler over a COPY, so an emitter that registers or
        # unregisters another emitter cannot mutate the collection being
        # iterated.
        def each(&block)
          return handlers.dup.each unless block

          handlers.dup.each(&block)
        end

        private

        def handler_noun
          "status emitter"
        end
      end
    end
  end
end
