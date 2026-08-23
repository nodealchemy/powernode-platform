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
    # The register / unregister / registered? / names / handlers / reset! surface
    # is the shared ::Powernode::HandlerRegistry shape; @handlers memoizes on this
    # module, so this registry's state is its own.
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
      extend ::Powernode::HandlerRegistry

      class << self
        private

        def handler_noun
          "scanner handler"
        end
      end
    end
  end
end
