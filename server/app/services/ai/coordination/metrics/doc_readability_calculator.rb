# frozen_string_literal: true

module Ai
  module Coordination
    module Metrics
      class DocReadabilityCalculator
        def initialize(account:)
          @account = account
        end

        def measure(artifact_ref:, artifact_type: nil)
          # Stub: returns documentation freshness/completeness gap as pressure 0-1
          # Higher value = staler/less complete docs = more pressure
          { value: 0.5, dimensions: { days_since_update: 0, completeness_ratio: 0.5, missing_sections: 0 } }
        end
      end
    end
  end
end
