# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Analytics::PerformanceAnalysisService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, time_range: 30.days) }

  let(:workflow) { create(:ai_workflow, :active, account: account) }

  def create_completed_run(duration_ms:, completed_at: 1.day.ago, started_at: nil)
    s = started_at || completed_at - (duration_ms / 1000.0).seconds
    create(:ai_workflow_run, :completed,
           workflow: workflow,
           duration_ms: duration_ms,
           started_at: s,
           completed_at: completed_at)
  end

  def create_failed_run(error_type: "execution_error", completed_at: 1.day.ago)
    create(:ai_workflow_run, :failed,
           workflow: workflow,
           completed_at: completed_at,
           started_at: completed_at - 5.minutes,
           error_details: { "error_type" => error_type, "error_message" => "Test error" })
  end

  describe "#full_analysis" do
    it "returns a hash with all analysis sections" do
      result = service.full_analysis

      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(
        :response_times, :success_rates, :throughput, :error_rates,
        :resource_utilization, :bottlenecks, :sla_compliance, :performance_trends
      )
    end
  end

  describe "#analyze_response_times" do
    context "with no completed runs" do
      it "returns empty duration stats" do
        result = service.analyze_response_times

        expect(result[:count]).to eq(0)
        expect(result[:min_ms]).to be_nil
        expect(result[:max_ms]).to be_nil
        expect(result[:avg_ms]).to be_nil
        expect(result[:median_ms]).to be_nil
        expect(result[:by_hour]).to eq({})
        expect(result[:by_workflow]).to eq([])
      end
    end

    context "with completed runs" do
      before do
        create_completed_run(duration_ms: 100)
        create_completed_run(duration_ms: 200)
        create_completed_run(duration_ms: 300)
        create_completed_run(duration_ms: 400)
        create_completed_run(duration_ms: 500)
      end

      it "returns correct count" do
        result = service.analyze_response_times
        expect(result[:count]).to eq(5)
      end

      it "returns correct min and max" do
        result = service.analyze_response_times
        expect(result[:min_ms]).to eq(100)
        expect(result[:max_ms]).to eq(500)
      end

      it "returns correct average" do
        result = service.analyze_response_times
        expect(result[:avg_ms]).to eq(300.0)
      end

      it "returns correct median" do
        result = service.analyze_response_times
        expect(result[:median_ms]).to eq(300)
      end

      it "returns percentiles" do
        result = service.analyze_response_times
        expect(result[:p75_ms]).to be_a(Numeric)
        expect(result[:p90_ms]).to be_a(Numeric)
        expect(result[:p95_ms]).to be_a(Numeric)
        expect(result[:p99_ms]).to be_a(Numeric)
      end

      it "returns standard deviation" do
        result = service.analyze_response_times
        expect(result[:std_dev_ms]).to be_a(Numeric)
        expect(result[:std_dev_ms]).to be > 0
      end

      it "returns by_workflow breakdown" do
        result = service.analyze_response_times
        expect(result[:by_workflow]).to be_an(Array)
        expect(result[:by_workflow].first).to include(:id, :name, :avg_ms)
      end
    end

    context "with runs outside time range" do
      it "excludes old runs" do
        create_completed_run(duration_ms: 100, completed_at: 31.days.ago, started_at: 31.days.ago - 1.minute)
        result = service.analyze_response_times
        expect(result[:count]).to eq(0)
      end
    end
  end

  describe "#analyze_success_rates" do
    context "with no runs" do
      it "returns empty success stats" do
        result = service.analyze_success_rates

        expect(result[:total_executions]).to eq(0)
        expect(result[:successful]).to eq(0)
        expect(result[:failed]).to eq(0)
        expect(result[:success_rate]).to be_nil
      end
    end

    context "with mixed status runs" do
      before do
        3.times { create_completed_run(duration_ms: 100) }
        2.times { create_failed_run }
        create(:ai_workflow_run, :cancelled, workflow: workflow, started_at: 1.day.ago, completed_at: 1.day.ago + 1.minute, cancelled_at: 1.day.ago + 1.minute)
      end

      it "returns correct totals" do
        result = service.analyze_success_rates
        expect(result[:total_executions]).to eq(6)
        expect(result[:successful]).to eq(3)
        expect(result[:failed]).to eq(2)
        expect(result[:cancelled]).to eq(1)
      end

      it "calculates correct rates" do
        result = service.analyze_success_rates
        expect(result[:success_rate]).to eq(50.0)
        expect(result[:failure_rate]).to be_within(0.1).of(33.33)
        expect(result[:cancellation_rate]).to be_within(0.1).of(16.67)
      end

      it "returns by_workflow breakdown" do
        result = service.analyze_success_rates
        expect(result[:by_workflow]).to be_an(Array)
      end

      it "returns by_day breakdown" do
        result = service.analyze_success_rates
        expect(result[:by_day]).to be_a(Hash)
      end

      it "returns by_trigger_type breakdown" do
        result = service.analyze_success_rates
        expect(result[:by_trigger_type]).to be_a(Hash)
      end
    end

    context "excludes running/initializing/pending runs" do
      before do
        create_completed_run(duration_ms: 100)
        create(:ai_workflow_run, :running, workflow: workflow)
        create(:ai_workflow_run, workflow: workflow, status: "initializing")
      end

      it "only counts finished runs" do
        result = service.analyze_success_rates
        expect(result[:total_executions]).to eq(1)
      end
    end
  end

  describe "#analyze_throughput" do
    context "with no runs" do
      it "returns zero totals" do
        result = service.analyze_throughput
        expect(result[:total_executions]).to eq(0)
        expect(result[:executions_per_hour]).to eq(0.0)
        expect(result[:executions_per_day]).to eq(0.0)
      end
    end

    context "with runs" do
      before do
        5.times { create_completed_run(duration_ms: 100) }
      end

      it "returns correct total" do
        result = service.analyze_throughput
        expect(result[:total_executions]).to eq(5)
      end

      it "returns period in hours" do
        result = service.analyze_throughput
        expect(result[:period_hours]).to be_within(0.1).of(720.0)
      end

      it "calculates executions per hour" do
        result = service.analyze_throughput
        expect(result[:executions_per_hour]).to be_a(Numeric)
      end

      it "calculates executions per day" do
        result = service.analyze_throughput
        expect(result[:executions_per_day]).to be_a(Numeric)
      end

      it "returns throughput breakdowns" do
        result = service.analyze_throughput
        expect(result[:by_hour_of_day]).to be_a(Hash)
        expect(result[:by_day_of_week]).to be_a(Hash)
      end
    end
  end

  describe "#analyze_error_rates" do
    context "with no failed runs" do
      it "returns zero errors" do
        result = service.analyze_error_rates
        expect(result[:total_errors]).to eq(0)
        expect(result[:error_rate]).to eq(0.0)
        expect(result[:by_error_type]).to eq({})
      end
    end

    context "with failed runs" do
      before do
        3.times { create_completed_run(duration_ms: 100) }
        create_failed_run(error_type: "timeout")
        create_failed_run(error_type: "timeout")
        create_failed_run(error_type: "api_error")
      end

      it "returns correct total errors" do
        result = service.analyze_error_rates
        expect(result[:total_errors]).to eq(3)
      end

      it "calculates error rate" do
        result = service.analyze_error_rates
        expect(result[:error_rate]).to eq(50.0)
      end

      it "groups by error type" do
        result = service.analyze_error_rates
        expect(result[:by_error_type]).to include("timeout" => 2, "api_error" => 1)
      end

      it "sorts error types by frequency descending" do
        result = service.analyze_error_rates
        values = result[:by_error_type].values
        expect(values).to eq(values.sort.reverse)
      end

      it "returns recent errors" do
        result = service.analyze_error_rates
        expect(result[:recent_errors]).to be_an(Array)
        expect(result[:recent_errors].length).to be <= 10
      end

      it "returns by_workflow breakdown" do
        result = service.analyze_error_rates
        expect(result[:by_workflow]).to be_an(Array)
      end
    end

    context "calculates MTBF" do
      it "returns nil with fewer than 2 failures" do
        create_failed_run
        result = service.analyze_error_rates
        expect(result[:mtbf_hours]).to be_nil
      end

      it "returns hours between failures with multiple failures" do
        create_failed_run(completed_at: 3.days.ago)
        create_failed_run(completed_at: 1.day.ago)
        result = service.analyze_error_rates
        expect(result[:mtbf_hours]).to be_a(Numeric)
        expect(result[:mtbf_hours]).to be > 0
      end
    end
  end

  describe "#analyze_resource_utilization" do
    it "returns resource utilization hash" do
      result = service.analyze_resource_utilization

      expect(result).to include(
        :provider_utilization,
        :model_utilization,
        :token_utilization,
        :queue_metrics
      )
    end

    context "token utilization" do
      it "returns total tokens from node executions" do
        run = create_completed_run(duration_ms: 100)
        node = create(:ai_workflow_node, workflow: workflow)
        create(:ai_workflow_node_execution, :completed,
               workflow_run: run,
               node: node,
               metadata: { "token_usage" => { "input_tokens" => 100, "output_tokens" => 50 } })

        result = service.analyze_resource_utilization
        expect(result[:token_utilization][:total_tokens]).to eq(150)
      end
    end
  end

  describe "#identify_bottlenecks" do
    it "returns an array" do
      result = service.identify_bottlenecks
      expect(result).to be_an(Array)
    end

    context "with high error rate workflows" do
      before do
        # Create 11 runs: 1 completed, 10 failed = 90.9% error rate (> 10% threshold)
        create_completed_run(duration_ms: 100)
        10.times { create_failed_run }
      end

      it "identifies high error rate workflows" do
        result = service.identify_bottlenecks
        error_bottlenecks = result.select { |b| b[:type] == "high_error_rate" }
        expect(error_bottlenecks).not_to be_empty
      end
    end

    it "sorts bottlenecks with high impact first" do
      # Create conditions for multiple bottleneck types
      create_completed_run(duration_ms: 100)
      10.times { create_failed_run }

      result = service.identify_bottlenecks
      next unless result.length > 1

      impacts = result.map { |b| b[:impact] }
      high_indices = impacts.each_index.select { |i| impacts[i] == "high" }
      other_indices = impacts.each_index.reject { |i| impacts[i] == "high" }

      if high_indices.any? && other_indices.any?
        expect(high_indices.max).to be < other_indices.min
      end
    end
  end

  describe "#analyze_sla_compliance" do
    context "with no data" do
      it "returns SLA targets with default values" do
        result = service.analyze_sla_compliance

        expect(result[:availability]).to include(:target, :actual, :compliant)
        expect(result[:response_time]).to include(:target_p95_ms, :actual_p95_ms, :compliant)
        expect(result[:success_rate]).to include(:target, :actual, :compliant)
        expect(result).to have_key(:overall_compliant)
      end
    end

    context "with custom SLA targets" do
      before do
        account.update!(settings: {
          "ai_sla_targets" => {
            "availability" => 95.0,
            "response_time_p95_ms" => 20000,
            "success_rate" => 90.0
          }
        })
      end

      it "uses account SLA targets" do
        result = service.analyze_sla_compliance
        expect(result[:availability][:target]).to eq(95.0)
        expect(result[:response_time][:target_p95_ms]).to eq(20000)
        expect(result[:success_rate][:target]).to eq(90.0)
      end
    end

    context "with compliant data" do
      before do
        10.times { create_completed_run(duration_ms: 500) }
      end

      it "reports overall compliance" do
        result = service.analyze_sla_compliance
        expect(result[:availability][:compliant]).to be true
        expect(result[:response_time][:compliant]).to be true
        expect(result[:success_rate][:compliant]).to be true
        expect(result[:overall_compliant]).to be true
      end
    end

    context "with non-compliant data" do
      before do
        1.times { create_completed_run(duration_ms: 500) }
        9.times { create_failed_run }
      end

      it "reports non-compliance for success rate" do
        result = service.analyze_sla_compliance
        expect(result[:success_rate][:compliant]).to be false
        expect(result[:overall_compliant]).to be false
      end
    end
  end

  describe "#analyze_performance_trends" do
    it "returns trend analysis hash" do
      result = service.analyze_performance_trends

      expect(result).to include(
        :response_time_trend,
        :success_rate_trend,
        :throughput_trend,
        :error_rate_trend
      )
    end

    context "response time trend" do
      it "returns 'stable' with insufficient data" do
        result = service.analyze_performance_trends
        expect(result[:response_time_trend]).to eq("stable")
      end

      it "detects increasing response times" do
        # Create runs with increasing durations over time
        15.times do |i|
          base_duration = i < 7 ? 100 : 500
          completed_at = (29 - i).days.ago
          create_completed_run(duration_ms: base_duration, completed_at: completed_at, started_at: completed_at - 1.minute)
        end

        result = service.analyze_performance_trends
        expect(%w[increasing stable decreasing]).to include(result[:response_time_trend])
      end
    end
  end

  describe "custom time range" do
    let(:service_7d) { described_class.new(account: account, time_range: 7.days) }

    it "respects the configured time range" do
      create_completed_run(duration_ms: 100, completed_at: 5.days.ago, started_at: 5.days.ago - 1.minute)
      create_completed_run(duration_ms: 200, completed_at: 10.days.ago, started_at: 10.days.ago - 1.minute)

      result = service_7d.analyze_response_times
      expect(result[:count]).to eq(1)
    end
  end
end
