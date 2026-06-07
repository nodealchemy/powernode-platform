# frozen_string_literal: true

module Ai
  module DataSources
    module Adapters
      # Resolves a request/response adapter for a data source's protocol.
      #
      # CONTRACT:
      #   Registry.for(data_source) => adapter
      #     adapter.build_request(endpoint:, params:) => { method:, url:, headers:, query:, body: }
      #     adapter.parse(raw_body, endpoint:)        => Array<Hash> (canonical records)
      #
      # Selection is by the data source's +protocol+ column. The generic
      # +RestAdapter+ is the fallback, so the +rest+ and +custom+ protocols — and
      # any unrecognised/blank protocol — resolve to it with ZERO per-source code.
      # Bespoke protocols (e.g. GraphQL, SOAP, gRPC-gateway) can be added later by
      # registering a class name here; until then they degrade safely to REST.
      #
      # This mirrors the generic-fallback registry shape used by sibling
      # registries (Ai::DataSources::Auth::SignerRegistry,
      # Ai::DataSources::Decoders::Registry, Ai::Providers::Sync::Generic):
      # a static map of normalized token => adapter class *name* (resolved via
      # +constantize+ to sidestep autoload-order issues), normalize-with-fallback
      # lookup, and a generic default that never raises.
      module Registry
        module_function

        # Canonical protocol token => adapter class name. Matched
        # case-insensitively after normalization. Both +rest+ and +custom+ map to
        # the generic RestAdapter intentionally — "custom" means "a REST source
        # with a hand-rolled template", not "needs its own adapter class".
        ADAPTERS = {
          "rest"   => "Ai::DataSources::Adapters::RestAdapter",
          "custom" => "Ai::DataSources::Adapters::RestAdapter"
        }.freeze

        # The adapter used when the protocol is unknown / unmapped / blank.
        GENERIC_FALLBACK = "Ai::DataSources::Adapters::RestAdapter"

        # @param data_source [Ai::DataSource, #protocol, String, Symbol, nil]
        #   A data source, anything responding to +#protocol+, or a raw protocol
        #   token. Nil resolves to the generic fallback.
        # @return [#build_request, #parse] an adapter conforming to the CONTRACT
        def for(data_source)
          class_name = ADAPTERS.fetch(normalize(protocol_for(data_source)), GENERIC_FALLBACK)
          class_name.constantize.new
        end

        # Returns true when a non-fallback adapter is registered for the protocol —
        # lets callers distinguish "purpose-built adapter" from "generic REST".
        def known_protocol?(protocol)
          ADAPTERS.key?(normalize(protocol))
        end

        # @return [Array<String>] the registered protocol tokens
        def protocols
          ADAPTERS.keys
        end

        # Extracts a protocol token from a DataSource (or accepts a raw token).
        def protocol_for(data_source)
          if data_source.respond_to?(:protocol)
            data_source.protocol
          else
            data_source
          end
        end
        private_class_method :protocol_for

        def normalize(protocol)
          key = protocol.to_s.strip.downcase
          key.empty? ? "rest" : key
        end
        private_class_method :normalize
      end
    end
  end
end
