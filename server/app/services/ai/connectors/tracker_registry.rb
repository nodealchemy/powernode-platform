# frozen_string_literal: true

module Ai
  module Connectors
    # Generic seam for OUTBOUND issue-tracker / error-tracker connectors (Linear,
    # Jira, Sentry, or any webhook destination). CORE OWNS the registry + the
    # adapter contract and NEVER hard-wires a specific vendor's auth/REST — vendor
    # adapters register themselves here (see config/initializers/ai_tracker_connectors.rb),
    # mirroring the Ai::Land::SecurityScannerRegistry / Ai::Deploy::MethodRegistry
    # inversion-of-control pattern. With nothing registered (and no tracker
    # configured), the internal report_issue / escalate paths are unchanged.
    #
    # An adapter is any object responding to at least one of:
    #   #create_issue(title:, body:, severity:, metadata:)  -> { ok:, external_id:, url: }
    #   #report_error(error:, severity:, context:)           -> { ok:, external_id:, url: }
    #
    # Example (extension / initializer):
    #   Ai::Connectors::TrackerRegistry.register(:linear, Ai::Connectors::LinearAdapter.new)
    module TrackerRegistry
      class << self
        # Register (or replace) an adapter by name. The adapter must respond to
        # #create_issue and/or #report_error.
        def register(name, adapter)
          unless adapter.respond_to?(:create_issue) || adapter.respond_to?(:report_error)
            raise ArgumentError,
                  "tracker adapter for #{name.inspect} must respond to #create_issue or #report_error"
          end

          registry[name.to_sym] = adapter
          name.to_sym
        end

        # The adapter registered under +name+, or nil.
        def adapter(name)
          registry[name.to_sym]
        end

        # The live name => adapter map (returned by reference; iterate read-only).
        def adapters
          registry
        end

        def names
          registry.keys
        end

        def registered?(name)
          registry.key?(name.to_sym)
        end

        def unregister(name)
          registry.delete(name.to_sym)
        end

        # Clears all registered adapters (test isolation / re-boot).
        def reset!
          @registry = {}
        end

        private

        def registry
          @registry ||= {}
        end
      end
    end
  end
end
