# frozen_string_literal: true

module Ai
  module Coordination
    module Metrics
      class DependencyHealthCalculator
        def initialize(account:)
          @account = account
        end

        def measure(artifact_ref:, artifact_type: nil)
          # Stub: returns outdated/vulnerable dependency ratio as pressure 0-1
          # Higher value = more outdated/vulnerable deps = more pressure
          { value: 0.5, dimensions: { outdated_count: 0, vulnerable_count: 0, total_count: 0, outdated_ratio: 0.0 } }
        end
      end
    end
  end
end
