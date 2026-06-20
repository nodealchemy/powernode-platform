# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::IntegrationInstance, type: :model do
  describe "#record_execution!" do
    let(:instance) { create(:devops_integration_instance) } # counters at 0, avg 0

    context "on the very first execution" do
      # Regression: the running-average divided by `execution_count` (still 0 on
      # the first call, since the +1 lives only in the unsaved updates hash),
      # producing an infinite value that overflowed the decimal(10,2) column
      # (PG::NumericValueOutOfRange). It must divide by execution_count + 1.
      it "does not overflow and records the duration as the average" do
        expect do
          instance.record_execution!(success: true, duration_ms: 100)
        end.not_to raise_error

        instance.reload
        expect(instance.execution_count).to eq(1)
        expect(instance.success_count).to eq(1)
        expect(instance.average_duration_ms.to_f).to eq(100.0)
      end
    end

    context "across multiple executions" do
      it "maintains a correct running average" do
        instance.record_execution!(success: true, duration_ms: 100) # avg 100 over 1
        instance.record_execution!(success: true, duration_ms: 300) # (100*1 + 300) / 2 = 200

        instance.reload
        expect(instance.execution_count).to eq(2)
        expect(instance.average_duration_ms.to_f).to eq(200.0)
      end
    end

    context "on failure" do
      it "tracks failure counters and the last error without touching the average" do
        instance.record_execution!(success: false, duration_ms: nil, error: "boom")

        instance.reload
        expect(instance.execution_count).to eq(1)
        expect(instance.failure_count).to eq(1)
        expect(instance.consecutive_failures).to eq(1)
        expect(instance.last_error).to eq("boom")
      end
    end
  end
end
