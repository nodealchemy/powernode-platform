# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Analytics::MetricsService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, time_range: 30.days) }

  describe "#all_metrics" do
    it "returns a hash with all metric sections" do
      result = service.all_metrics

      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(
        :workflows, :agents, :providers, :executions, :performance
      )
    end
  end

  describe "#workflow_metrics" do
    context "with no data" do
      it "returns zero counts" do
        result = service.workflow_metrics

        expect(result[:total_workflows]).to eq(0)
        expect(result[:active_workflows]).to eq(0)
        expect(result[:total_executions]).to eq(0)
        expect(result[:successful_executions]).to eq(0)
        expect(result[:failed_executions]).to eq(0)
        expect(result[:success_rate]).to be_nil
      end
    end
  end

  describe "#agent_metrics" do
    context "with no agents" do
      it "returns zero counts" do
        result = service.agent_metrics

        expect(result[:total_agents]).to eq(0)
        expect(result[:active_agents]).to eq(0)
        expect(result[:agents_by_type]).to eq({})
      end
    end

    context "with agents" do
      before do
        create(:ai_agent, account: account, agent_type: "assistant")
        create(:ai_agent, account: account, agent_type: "assistant")
        create(:ai_agent, :code_assistant, account: account)
        create(:ai_agent, :inactive, account: account, agent_type: "monitor")
      end

      it "counts agents correctly" do
        result = service.agent_metrics

        expect(result[:total_agents]).to eq(4)
        expect(result[:active_agents]).to eq(3)
      end

      it "groups agents by type" do
        result = service.agent_metrics
        expect(result[:agents_by_type]).to be_a(Hash)
        expect(result[:agents_by_type]["assistant"]).to eq(2)
        expect(result[:agents_by_type]["code_assistant"]).to eq(1)
      end
    end
  end

  describe "#provider_metrics" do
    context "with no providers" do
      it "returns zero counts" do
        result = service.provider_metrics

        expect(result[:total_providers]).to eq(0)
        expect(result[:active_providers]).to eq(0)
        expect(result[:providers]).to eq([])
      end
    end

    context "with providers" do
      let!(:provider) { create(:ai_provider, :active, account: account) }

      it "returns provider stats" do
        result = service.provider_metrics

        expect(result[:total_providers]).to eq(1)
        expect(result[:active_providers]).to eq(1)
        expect(result[:providers]).to be_an(Array)
        expect(result[:providers].first).to include(
          :id, :name, :provider_type, :is_active,
          :total_requests, :error_rate
        )
      end
    end
  end

  describe "#execution_metrics" do
    context "with no executions" do
      it "returns queue time metrics" do
        result = service.execution_metrics

        expect(result[:queue_time]).to include(
          :average_ms, :p95_ms, :max_ms
        )
      end
    end
  end

  describe "#performance_metrics" do
    context "with no data" do
      it "returns throughput metrics" do
        result = service.performance_metrics

        expect(result[:throughput]).to include(
          :executions_per_hour, :executions_per_day
        )
      end

      it "returns latency metrics" do
        result = service.performance_metrics

        expect(result[:latency]).to include(
          :p50_ms, :p90_ms, :p95_ms, :p99_ms
        )
      end

      it "returns availability" do
        result = service.performance_metrics
        expect(result[:availability]).to be_a(Numeric)
      end

      it "returns error budget" do
        result = service.performance_metrics
        expect(result[:error_budget]).to include(
          :target_slo, :actual_success_rate,
          :remaining_budget, :budget_consumed
        )
      end
    end
  end

  describe "#agent_specific_metrics" do
    let(:agent) { create(:ai_agent, account: account) }

    context "with no executions" do
      it "returns zero counts" do
        result = service.agent_specific_metrics(agent)

        expect(result[:agent_id]).to eq(agent.id)
        expect(result[:agent_name]).to eq(agent.name)
        expect(result[:total_executions]).to eq(0)
        expect(result[:successful_executions]).to eq(0)
        expect(result[:failed_executions]).to eq(0)
        expect(result[:success_rate]).to be_nil
      end
    end
  end
end
