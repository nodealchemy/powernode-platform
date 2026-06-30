# frozen_string_literal: true

module Ai
  module Land
    # Generic seam for external security scanners used by the land gate (SAST,
    # dependency-CVE, deep secret-scan over the full diff). CORE OWNS the registry
    # + the handler contract and NEVER names a specific scanner — extensions and
    # the worker inject the heavy implementations here, mirroring the
    # Ai::Deploy::MethodRegistry / Devops::StepHandlerRegistry inversion-of-control
    # pattern. With nothing registered (core mode), the land gate still runs the
    # in-process core secret-scan; registered handlers ADD findings on top.
    #
    # A handler is any callable responding to #call(context) and returning an Array
    # of finding hashes: { scanner:, severity:, detail: }. `severity` is one of
    # Ai::Land::SecurityGateService::SEVERITY_ORDER. Example (in an extension's
    # boot initializer — core never references the extension's class name):
    #
    #   Ai::Land::SecurityScannerRegistry.register(:brakeman) do |context|
    #     MyExt::Sast.scan(context[:changed_files]) # => [{ scanner: "brakeman", ... }]
    #   end
    module SecurityScannerRegistry
      class << self
        # Register (or replace) a scanner handler by name. Accepts a callable
        # argument or a block.
        def register(name, callable = nil, &block)
          handler = callable || block
          unless handler.respond_to?(:call)
            raise ArgumentError, "scanner handler for #{name.inspect} must respond to #call"
          end

          handlers[name.to_sym] = handler
          name.to_sym
        end

        def unregister(name)
          handlers.delete(name.to_sym)
        end

        def registered?(name)
          handlers.key?(name.to_sym)
        end

        def names
          handlers.keys
        end

        # The live name => callable map. Returned by reference; callers iterate it
        # read-only.
        def handlers
          @handlers ||= {}
        end

        # Clears all registered handlers (test isolation / re-boot).
        def reset!
          @handlers = {}
        end
      end
    end
  end
end
