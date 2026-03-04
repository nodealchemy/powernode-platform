# frozen_string_literal: true

module Ai
  module Coordination
    module Metrics
      class TestCoverageCalculator
        def initialize(account:)
          @account = account
        end

        def measure(artifact_ref:, artifact_type: nil)
          # Stub: returns coverage gap (1 - coverage_ratio) as pressure 0-1
          # Higher value = less coverage = more pressure
          { value: 0.5, dimensions: { coverage_ratio: 0.5, uncovered_lines: 0, total_lines: 0 } }
        end
      end
    end
  end
end
