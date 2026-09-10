# frozen_string_literal: true

module Platform
  module Status
    # THE PULL SEAM for "what is currently signalling about this component?"
    # (design §4.3, the `remediation` jsonb).
    #
    # Core has no SignalState, no FleetEvent and no remediation outcome table —
    # those belong to whoever emits signals. So core does not reach for them.
    # A source is REGISTERED here by its owner and core PULLS from it, which is
    # the platform's stated data-flow direction: downstream pulls from
    # upstream, upstream never pushes downstream.
    #
    #   Platform::Status::SignalSources.register(->(component_status) { [...] })
    #
    # A source is anything answering #call with a component status and
    # returning an Array of SIGNAL FACTS. A fact is a plain Hash:
    #
    #   { signal_kind:         "instance.silent",   # required; a fact without one is dropped
    #     fingerprint:         "<stable id>",       # the dedupe key for this occurrence
    #     approval_request_id: "<uuid or nil>",     # set when a person has been asked
    #     last_outcome:        "succeeded" | "failed" | nil,
    #     stuck:               true | false }
    #
    # String or symbol keys; Platform::Status::RemediationState normalizes.
    #
    # WHY FACTS AND NOT ROWS. The source hands over a described observation,
    # not an ActiveRecord object, so core never learns the shape of the table
    # behind it and cannot grow a dependency on an extension's schema by
    # accident. It also means the whole derivation is testable over plain
    # hashes, with no extension loaded.
    #
    # A source that RAISES is logged and skipped. One broken source must not
    # blank the remediation state of every component on the page — that would
    # turn a source bug into a fleet-wide "nothing is being remediated", which
    # reads exactly like good news.
    module SignalSources
      MUTEX = Mutex.new
      private_constant :MUTEX

      class << self
        # @param source [#call] (component_status) => Array<Hash>
        def register(source)
          raise ArgumentError, "source must respond to #call" unless source.respond_to?(:call)

          MUTEX.synchronize do
            registry.delete(source)
            registry << source
          end
          source
        end

        def unregister(source)
          MUTEX.synchronize { registry.delete(source) }
        end

        # A frozen COPY — readers iterate this while a reload may be
        # registering.
        def sources
          MUTEX.synchronize { registry.dup.freeze }
        end

        def any?
          sources.any?
        end

        # Every source's facts for this component, concatenated in
        # registration order. Never nil.
        def signals_for(component_status)
          sources.flat_map { |source| safe_call(source, component_status) }
        end

        # Spec seam. Never call this from application code.
        def reset!
          MUTEX.synchronize { registry.clear }
        end

        private

        def safe_call(source, component_status)
          result = source.call(component_status)
          result.is_a?(Array) ? result.select { |fact| fact.is_a?(Hash) } : []
        rescue StandardError => e
          Rails.logger.error(
            "[Platform::Status::SignalSources] source #{source.class} raised: #{e.class}: #{e.message}"
          )
          []
        end

        def registry
          @registry ||= []
        end
      end
    end
  end
end
