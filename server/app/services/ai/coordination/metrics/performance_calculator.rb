# frozen_string_literal: true

module Ai
  module Coordination
    module Metrics
      class PerformanceCalculator
        def initialize(account:)
          @account = account
        end

        def measure(artifact_ref:, artifact_type: nil)
          # Stub: returns performance degradation from benchmarks as pressure 0-1
          # Higher value = worse performance = more pressure
          { value: 0.5, dimensions: { p95_ms: 0, p99_ms: 0, error_rate: 0.0, throughput_rps: 0 } }
        end
      end
    end
  end
end
