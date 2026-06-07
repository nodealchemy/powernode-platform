# frozen_string_literal: true

module Ai
  module DataSources
    module Auth
      # Generic no-auth signer and the registry's safe fallback.
      #
      # Performs no mutation: used for fully public endpoints (auth_scheme
      # "none") and for any unrecognized scheme so an unknown source degrades to
      # unauthenticated requests rather than raising mid-flight.
      class NoneSigner < BaseSigner
        def sign!(_conn_or_env, credential: nil, config: {})
          # Intentionally a no-op. No credential material is read or injected.
          nil
        end
      end
    end
  end
end
