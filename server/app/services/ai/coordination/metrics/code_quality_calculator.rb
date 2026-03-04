# frozen_string_literal: true

module Ai
  module Coordination
    module Metrics
      class CodeQualityCalculator
        def initialize(account:)
          @account = account
        end

        def measure(artifact_ref:, artifact_type: nil)
          # Stub: returns normalized pressure value 0-1
          # Higher value = more pressure (worse quality)
          { value: 0.5, dimensions: { lint_errors: 0, complexity: 0, style_violations: 0 } }
        end
      end
    end
  end
end
