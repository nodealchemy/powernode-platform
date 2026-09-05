# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SelfHealing::PredictiveMonitorService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  subject(:service) { described_class.new(account: account) }

  # The service references `total_cost_usd` and `.ai_provider` which may not
  # exist in the current schema. We stub the internal analysis methods that
  # hit those paths, so we can test the orchestration and decision logic.

  before do
    # Stub cost_metrics to avoid referencing missing column total_cost_usd
    allow(service).to receive(:send).and_call_original
  end

  # ===========================================================================
  # #analyze
  # ===========================================================================

  describe "#analyze" do
    before do
      # Stub the three analysis branches to return controlled data
      allow(service).to receive(:analyze_provider_health).and_return(provider_predictions)
      allow(service).to receive(:analyze_execution_trends).and_return(execution_predictions)
      allow(service).to receive(:analyze_cost_trends).and_return(cost_predictions)
    end

    let(:provider_predictions) { [] }
    let(:execution_predictions) { [] }
    let(:cost_predictions) { [] }

    context "with no data" do
      it "returns empty predictions" do
        predictions = service.analyze

        expect(predictions).to be_an(Array)
        expect(predictions).to be_empty
      end
    end

    context "with predictions below threshold" do
      let(:provider_predictions) do
        [{ event_type: "provider_degradation", probability: 0.3, source: "provider" }]
      end

      it "filters out predictions below FAILURE_PROBABILITY_THRESHOLD" do
        predictions = service.analyze

        expect(predictions).to be_empty
      end
    end

    context "with provider degradation above threshold" do
      let(:provider_predictions) do
        [{
          event_type: "provider_degradation",
          source: "provider",
          source_id: provider.id,
          source_name: provider.name,
          probability: 0.85,
          signals: ["high_error_rate", "consecutive_failures"],
          metrics: { total_requests: 10, error_rate: 0.8 },
          message: "Provider showing degradation signals"
        }]
      end

      it "includes provider degradation predictions" do
        predictions = service.analyze

        expect(predictions.size).to eq(1)
        expect(predictions.first[:event_type]).to eq("provider_degradation")
        expect(predictions.first[:probability]).to eq(0.85)
      end

      it "includes signal information" do
        predictions = service.analyze

        expect(predictions.first[:signals]).to include("high_error_rate")
      end
    end

    context "with execution degradation above threshold" do
      let(:execution_predictions) do
        [{
          event_type: "execution_degradation",
          source: "executions",
          probability: 0.9,
          signals: ["error_rate_80pct", "error_rate_rising"],
          metrics: { window: 300, recent_error_rate: 0.8, baseline_error_rate: 0.1 },
          message: "Execution quality degrading"
        }]
      end

      it "includes execution degradation predictions" do
        predictions = service.analyze

        expect(predictions.size).to eq(1)
        expect(predictions.first[:event_type]).to eq("execution_degradation")
      end
    end

    context "with cost anomaly above threshold" do
      let(:cost_predictions) do
        [{
          event_type: "cost_anomaly",
          source: "cost",
          probability: 0.8,
          signals: ["cost_spike_5.0x"],
          metrics: { recent_cost: 7.5, baseline_hourly_avg: 1.5, cost_ratio: 5.0 },
          message: "Cost spike detected: 5.0x baseline"
        }]
      end

      it "includes cost anomaly predictions" do
        predictions = service.analyze

        expect(predictions.size).to eq(1)
        expect(predictions.first[:event_type]).to eq("cost_anomaly")
        expect(predictions.first[:signals].first).to match(/cost_spike/)
      end
    end

    context "with multiple predictions" do
      let(:provider_predictions) do
        [{ event_type: "provider_degradation", probability: 0.75, source: "provider" }]
      end
      let(:execution_predictions) do
        [{ event_type: "execution_degradation", probability: 0.9, source: "executions" }]
      end

      it "sorts by probability descending" do
        predictions = service.analyze

        probabilities = predictions.map { |p| p[:probability] }
        expect(probabilities).to eq(probabilities.sort.reverse)
      end
    end
  end

  # ===========================================================================
  # #analyze_and_remediate!
  # ===========================================================================

  describe "#analyze_and_remediate!" do
    before do
      allow(service).to receive(:analyze_provider_health).and_return(provider_predictions)
      allow(service).to receive(:analyze_execution_trends).and_return(execution_predictions)
      allow(service).to receive(:analyze_cost_trends).and_return(cost_predictions)
    end

    let(:provider_predictions) { [] }
    let(:execution_predictions) { [] }
    let(:cost_predictions) { [] }

    context "with no predictions above threshold" do
      it "returns zero remediations" do
        result = service.analyze_and_remediate!

        expect(result[:predictions_count]).to eq(0)
        expect(result[:remediations_count]).to eq(0)
        expect(result[:analyzed_at]).to be_present
      end

      it "returns correct structure" do
        result = service.analyze_and_remediate!

        expect(result).to have_key(:predictions_count)
        expect(result).to have_key(:remediations_count)
        expect(result).to have_key(:predictions)
        expect(result).to have_key(:remediations)
        expect(result).to have_key(:analyzed_at)
      end
    end

    context "with high-probability provider degradation" do
      let(:provider_predictions) do
        [{
          event_type: "provider_degradation",
          source: "provider",
          source_id: provider.id,
          source_name: provider.name,
          probability: 0.85,
          signals: ["high_error_rate"],
          metrics: { total_requests: 10, error_rate: 0.8 },
          message: "Provider showing degradation"
        }]
      end

      before do
        allow(Ai::SelfHealing::RemediationDispatcher).to receive(:dispatch).and_return(
          { status: "success", action: "provider_failover" }
        )
      end

      it "dispatches remediation for provider_failover" do
        service.analyze_and_remediate!

        expect(Ai::SelfHealing::RemediationDispatcher).to have_received(:dispatch).with(
          hash_including(
            account: account,
            trigger_source: "predictive_monitor",
            trigger_event: "provider_degradation"
          )
        )
      end

      it "returns remediation details" do
        result = service.analyze_and_remediate!

        expect(result[:predictions_count]).to eq(1)
        expect(result[:remediations_count]).to eq(1)
        expect(result[:remediations].first[:action]).to eq("provider_failover")
      end
    end

    context "with execution degradation (latency spike)" do
      let(:execution_predictions) do
        [{
          event_type: "execution_degradation",
          source: "executions",
          source_id: nil,
          probability: 0.9,
          signals: ["latency_spike"],
          metrics: {},
          message: "Latency spike detected"
        }]
      end

      # This stub proves only that the monitor ASKS for a model_downgrade — the
      # dispatcher body never runs here, and for a long time that body raised
      # NoMethodError on the first agent it touched (IMP-929aadc88e19). What the
      # dispatcher actually does with a real agent is covered, unstubbed, in
      # spec/services/ai/self_healing/remediation_dispatcher_model_downgrade_spec.rb.
      before do
        allow(Ai::SelfHealing::RemediationDispatcher).to receive(:dispatch).and_return(
          { status: "success", action: "model_downgrade" }
        )
      end

      it "triggers model_downgrade action for latency spikes" do
        result = service.analyze_and_remediate!

        expect(result[:remediations].first[:action]).to eq("model_downgrade")
      end
    end

    context "with execution degradation (non-latency)" do
      let(:execution_predictions) do
        [{
          event_type: "execution_degradation",
          source: "executions",
          source_id: nil,
          probability: 0.8,
          signals: ["error_rate_50pct"],
          metrics: {},
          message: "Error rate elevated"
        }]
      end

      before do
        allow(Ai::SelfHealing::RemediationDispatcher).to receive(:dispatch).and_return(
          { status: "success", action: "alert_escalation" }
        )
      end

      it "triggers alert_escalation for non-latency execution issues" do
        result = service.analyze_and_remediate!

        expect(result[:remediations].first[:action]).to eq("alert_escalation")
      end
    end

    context "with cost anomaly" do
      let(:cost_predictions) do
        [{
          event_type: "cost_anomaly",
          source: "cost",
          source_id: nil,
          probability: 0.8,
          signals: ["cost_spike_5.0x"],
          metrics: {},
          message: "Cost spike detected"
        }]
      end

      before do
        allow(Ai::SelfHealing::RemediationDispatcher).to receive(:dispatch).and_return(
          { status: "success", action: "alert_escalation" }
        )
      end

      it "triggers alert_escalation for cost anomalies" do
        result = service.analyze_and_remediate!

        expect(result[:remediations].first[:action]).to eq("alert_escalation")
      end
    end
  end

  # ===========================================================================
  # #record_learning
  # Regression: guarded on `defined?(Ai::CompoundLearningService)` and called
  # .record_extraction — but the class is Ai::Learning::CompoundLearningService
  # (no top-level alias) and has no record_extraction, so the guard was always
  # nil and the self-healing feedback loop never recorded a learning.
  # ===========================================================================
  describe "#record_learning" do
    before do
      # Return nil so store_learning uses its deterministic text-dedup path
      # (a stubbed vector would route through pgvector nearest_neighbors).
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(nil)
    end

    let(:prediction) do
      { event_type: "provider_degradation", source_id: "prov-1", probability: 0.9, signals: ["latency_spike_3.2x"] }
    end

    it "persists a compound learning for a successful remediation (auto_success)" do
      expect {
        service.send(:record_learning, prediction, "model_downgrade", { status: "success" })
      }.to change(Ai::CompoundLearning, :count).by(1)

      learning = Ai::CompoundLearning.order(:created_at).last
      expect(learning.content).to include("model_downgrade")
      expect(learning.extraction_method).to eq("auto_success")
      expect(learning.source_execution_successful).to be true
      expect(Ai::CompoundLearning::CATEGORIES).to include(learning.category)
    end

    it "records a failed remediation as auto_failure" do
      service.send(:record_learning, prediction, "alert_escalation", { status: "failed" })

      learning = Ai::CompoundLearning.order(:created_at).last
      expect(learning).to be_present
      expect(learning.extraction_method).to eq("auto_failure")
      expect(learning.source_execution_successful).to be false
    end
  end

  # ===========================================================================
  # #determine_preemptive_action
  # Regression: signals are emitted as "latency_spike_#{N}x" but the dispatch did
  # include?("latency_spike") (exact match), so model_downgrade was unreachable and
  # every execution_degradation fell through to alert_escalation.
  # ===========================================================================
  describe "#determine_preemptive_action" do
    it "returns model_downgrade for an execution_degradation with a latency_spike_Nx signal" do
      prediction = { event_type: "execution_degradation", signals: ["latency_spike_3.2x"] }
      expect(service.send(:determine_preemptive_action, prediction)).to eq("model_downgrade")
    end

    it "returns alert_escalation for an execution_degradation without a latency spike" do
      prediction = { event_type: "execution_degradation", signals: ["error_rate_rising"] }
      expect(service.send(:determine_preemptive_action, prediction)).to eq("alert_escalation")
    end
  end
end
