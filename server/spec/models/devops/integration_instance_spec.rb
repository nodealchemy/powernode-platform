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

  # A8: the three health columns had exactly one writer (`#update_health!`) and
  # zero call sites. `#record_health_probe!` is that call site — it derives the
  # verdict from the probe outcome plus the failure streak and writes THROUGH
  # `#update_health!`, which stays the single writer of the columns.
  describe "#record_health_probe!" do
    let(:instance) { create(:devops_integration_instance, status: "active", health_status: nil, last_health_check_at: nil) }

    it "records a passing probe as healthy and clears the streak" do
      instance.update!(consecutive_failures: 2, last_error: "stale")

      expect(instance.record_health_probe!(success: true)).to be false

      instance.reload
      expect(instance.health_status).to eq("healthy")
      expect(instance.consecutive_failures).to eq(0)
      expect(instance.last_error).to be_nil
      expect(instance.last_health_check_at).to be_present
      expect(instance.status).to eq("active")
    end

    it "records a failing probe below the threshold as degraded" do
      expect(instance.record_health_probe!(success: false, error: "refused")).to be false

      instance.reload
      expect(instance.health_status).to eq("degraded")
      expect(instance.consecutive_failures).to eq(1)
      expect(instance.last_error).to eq("refused")
      expect(instance.status).to eq("active")
    end

    it "reaches unhealthy and pauses at the threshold" do
      threshold = described_class.health_failure_threshold
      paused = (1..threshold).map { instance.record_health_probe!(success: false, error: "refused") }

      expect(paused).to eq([ *Array.new(threshold - 1, false), true ])
      instance.reload
      expect(instance.health_status).to eq("unhealthy")
      expect(instance.status).to eq("paused")
    end

    it "merges probe metrics into health_metrics without dropping prior keys" do
      instance.update!(health_metrics: { "keep" => "me" })

      instance.record_health_probe!(success: true, metrics: { "response_time_ms" => 12 })

      expect(instance.reload.health_metrics).to include("keep" => "me", "response_time_ms" => 12)
    end

    # GUARD THE DECISION, not the mechanism. `#pause!` is a bare `update!`, so the
    # guard has to sit where the auto-pause is DECIDED, or a sweep would drag a
    # disabled integration back to `paused` and undo an operator's retirement.
    it "does not auto-pause an integration that is not active" do
      instance.update!(status: "disabled")

      described_class.health_failure_threshold.times do
        expect(instance.record_health_probe!(success: false, error: "refused")).to be false
      end

      expect(instance.reload.status).to eq("disabled")
    end
  end

  describe ".health_failure_threshold" do
    it "falls back to the built-in default when no SiteSetting row exists" do
      expect(described_class.health_failure_threshold)
        .to eq(described_class::DEFAULT_HEALTH_FAILURE_THRESHOLD)
    end

    it "reads the SiteSetting when one is present" do
      SiteSetting.set(described_class::HEALTH_FAILURE_THRESHOLD_SETTING, 7, setting_type: "integer")

      expect(described_class.health_failure_threshold).to eq(7)
    end

    it "ignores a non-positive setting rather than pausing on every probe" do
      SiteSetting.set(described_class::HEALTH_FAILURE_THRESHOLD_SETTING, 0, setting_type: "integer")

      expect(described_class.health_failure_threshold)
        .to eq(described_class::DEFAULT_HEALTH_FAILURE_THRESHOLD)
    end
  end
end
