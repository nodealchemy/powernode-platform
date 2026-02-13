# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevopsBridge::DeploymentGuardian, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }
  let(:pipeline_run) do
    double("PipelineRun",
           id: SecureRandom.uuid,
           started_at: 10.minutes.ago)
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe "constants" do
    it "sets HEALTH_CHECK_INTERVAL to 30 seconds" do
      expect(described_class::HEALTH_CHECK_INTERVAL).to eq(30.seconds)
    end

    it "sets MAX_MONITORING_DURATION to 30 minutes" do
      expect(described_class::MAX_MONITORING_DURATION).to eq(30.minutes)
    end
  end

  describe "#monitor_deployment" do
    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:cross_system_triggers).and_return(false)
      end

      it "returns skip recommendation" do
        result = service.monitor_deployment(pipeline_run: pipeline_run)

        expect(result[:recommendation]).to eq("skip")
        expect(result[:reason]).to include("not enabled")
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:cross_system_triggers).and_return(true)
      end

      it "returns analysis with recommendation" do
        # Mock execution events
        events_scope = double("events_scope")
        allow(Ai::ExecutionEvent).to receive(:by_account).and_return(events_scope)
        allow(events_scope).to receive(:in_time_range).and_return(events_scope)
        allow(events_scope).to receive(:count).and_return(100)
        allow(events_scope).to receive(:with_errors).and_return(events_scope)
        allow(events_scope).to receive(:where).and_return(events_scope)
        allow(events_scope).to receive(:not).and_return(events_scope)
        allow(events_scope).to receive(:pluck).and_return([50, 60, 70, 80, 90])

        # Mock baseline events
        baseline_scope = double("baseline_scope")
        allow(Ai::ExecutionEvent).to receive(:by_account).with(account.id).and_return(events_scope)
        allow(events_scope).to receive(:in_time_range).with(any_args).and_return(events_scope)

        # Mock remediation log creation
        allow(Ai::RemediationLog).to receive(:create!)

        result = service.monitor_deployment(pipeline_run: pipeline_run, strategy: :canary)

        expect(result).to include(:recommendation, :mode, :strategy, :health, :analyzed_at)
        expect(result[:mode]).to eq("recommendation_only")
        expect(result[:strategy]).to eq(:canary)
      end

      it "recommends rollback for high error rates" do
        allow(service).to receive(:collect_health_data).and_return({
          error_rate: 15.0,
          total_events: 100,
          error_count: 15,
          latency_p95: 200,
          baseline_latency: 100,
          deployment_age_minutes: 10.0
        })
        allow(service).to receive(:log_guardian_decision)

        result = service.monitor_deployment(pipeline_run: pipeline_run)
        expect(result[:recommendation]).to eq("rollback")
      end

      it "recommends hold for moderate error rates" do
        allow(service).to receive(:collect_health_data).and_return({
          error_rate: 7.0,
          total_events: 100,
          error_count: 7,
          latency_p95: 100,
          baseline_latency: 100,
          deployment_age_minutes: 10.0
        })
        allow(service).to receive(:log_guardian_decision)

        result = service.monitor_deployment(pipeline_run: pipeline_run)
        expect(result[:recommendation]).to eq("hold")
      end

      it "recommends hold for young deployments" do
        allow(service).to receive(:collect_health_data).and_return({
          error_rate: 1.0,
          total_events: 100,
          error_count: 1,
          latency_p95: 100,
          baseline_latency: 100,
          deployment_age_minutes: 3.0
        })
        allow(service).to receive(:log_guardian_decision)

        result = service.monitor_deployment(pipeline_run: pipeline_run)
        expect(result[:recommendation]).to eq("hold")
      end

      it "recommends promote for healthy mature deployments" do
        allow(service).to receive(:collect_health_data).and_return({
          error_rate: 0.5,
          total_events: 100,
          error_count: 0,
          latency_p95: 100,
          baseline_latency: 100,
          deployment_age_minutes: 10.0
        })
        allow(service).to receive(:log_guardian_decision)

        result = service.monitor_deployment(pipeline_run: pipeline_run)
        expect(result[:recommendation]).to eq("promote")
      end
    end
  end

  describe "#recommend_action" do
    before do
      allow(service).to receive(:collect_health_data).and_return(health_data)
    end

    context "when error rate exceeds 10%" do
      let(:health_data) { { error_rate: 15.0, latency_p95: 100, baseline_latency: 80 } }

      it "recommends rollback with high confidence" do
        result = service.recommend_action(pipeline_run: pipeline_run)
        expect(result[:recommendation]).to eq("rollback")
        expect(result[:confidence]).to eq(0.9)
      end
    end

    context "when latency is 2x baseline" do
      let(:health_data) { { error_rate: 2.0, latency_p95: 200, baseline_latency: 80 } }

      it "recommends hold" do
        result = service.recommend_action(pipeline_run: pipeline_run)
        expect(result[:recommendation]).to eq("hold")
        expect(result[:confidence]).to eq(0.7)
      end
    end

    context "when metrics are within acceptable range" do
      let(:health_data) { { error_rate: 0.5, latency_p95: 90, baseline_latency: 80 } }

      it "recommends promote" do
        result = service.recommend_action(pipeline_run: pipeline_run)
        expect(result[:recommendation]).to eq("promote")
        expect(result[:confidence]).to eq(0.8)
      end
    end

    context "when metrics are inconclusive" do
      let(:health_data) { { error_rate: 5.0, latency_p95: 100, baseline_latency: 80 } }

      it "recommends hold with low confidence" do
        result = service.recommend_action(pipeline_run: pipeline_run)
        expect(result[:recommendation]).to eq("hold")
        expect(result[:confidence]).to eq(0.5)
      end
    end
  end

  describe "calculate_p95 (private)" do
    it "returns 0 for empty array" do
      expect(service.send(:calculate_p95, [])).to eq(0)
    end

    it "calculates p95 for sorted durations" do
      durations = (1..100).to_a
      expect(service.send(:calculate_p95, durations)).to eq(95)
    end

    it "handles single value" do
      expect(service.send(:calculate_p95, [42])).to eq(42)
    end
  end
end
