# frozen_string_literal: true

module Ai
  module Coordination
    class PressureFieldService
      def initialize(account:)
        @account = account
      end

      def measure!(artifact_ref:, artifact_type: nil, field_type:, team_id: nil)
        calculator = metric_calculator_for(field_type)
        return nil unless calculator

        measurement = calculator.measure(artifact_ref: artifact_ref, artifact_type: artifact_type)
        return nil unless measurement

        field = Ai::PressureField.find_or_initialize_by(
          account: @account,
          field_type: field_type,
          artifact_ref: artifact_ref
        )
        field.artifact_type = artifact_type if artifact_type
        field.save! if field.new_record?

        field.record_measurement!(
          value: measurement[:value],
          dimensions: measurement[:dimensions] || {}
        )

        field
      end

      def perceive(agent:, team_id: nil, limit: 10)
        scope = Ai::PressureField.for_account(@account.id).actionable.highest_pressure
        fields = scope.limit(limit)

        fields.map do |field|
          {
            id: field.id,
            field_type: field.field_type,
            artifact_ref: field.artifact_ref,
            artifact_type: field.artifact_type,
            pressure_value: field.pressure_value,
            threshold: field.threshold,
            dimensions: field.dimensions,
            last_measured_at: field.last_measured_at&.iso8601,
            last_addressed_at: field.last_addressed_at&.iso8601,
            address_count: field.address_count
          }
        end
      end

      def claim_and_address!(field_id:, agent:)
        field = Ai::PressureField.find_by(id: field_id, account: @account)
        return { claimed: false, reason: "not_found" } unless field

        # Atomic claim check (avoid double-addressing)
        if field.last_addressed_at && field.last_addressed_at > 5.minutes.ago
          return { claimed: false, reason: "recently_addressed" }
        end

        field.record_address!(agent.id)
        { claimed: true, field: field.as_json(only: [:id, :field_type, :artifact_ref, :pressure_value]) }
      end

      def decay_all!
        decayed = 0
        Ai::PressureField.for_account(@account.id).where("pressure_value > 0").find_each do |field|
          field.apply_decay!
          decayed += 1
        end
        decayed
      end

      private

      def metric_calculator_for(field_type)
        calculators = {
          "code_quality" => Ai::Coordination::Metrics::CodeQualityCalculator,
          "test_coverage" => Ai::Coordination::Metrics::TestCoverageCalculator,
          "doc_readability" => Ai::Coordination::Metrics::DocReadabilityCalculator,
          "security_posture" => Ai::Coordination::Metrics::SecurityPostureCalculator,
          "performance" => Ai::Coordination::Metrics::PerformanceCalculator,
          "dependency_health" => Ai::Coordination::Metrics::DependencyHealthCalculator
        }

        klass = calculators[field_type]
        klass&.new(account: @account)
      end
    end
  end
end
