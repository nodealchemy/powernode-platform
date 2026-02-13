# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Analytics::MetricsService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, time_range: 30.days) }

  let(:workflow) { create(:ai_workflow, :active, account: account) }

  def create_completed_run(duration_ms: 480_000, total_cost: 0.025, trigger_type: "manual")
    create(:ai_workflow_run, :completed,
           workflow: workflow,
           duration_ms: duration_ms,
           total_cost: total_cost,
           trigger_type: trigger_type)
  end

  def create_failed_run
    create(:ai_workflow_run, :failed, workflow: workflow)
  end

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

    context "with workflows and runs" do
      let!(:active_workflow) { create(:ai_workflow, :active, account: account) }
      let!(:draft_workflow) { create(:ai_workflow, account: account, status: "draft") }
      let!(:template_workflow) { create(:ai_workflow, :active, :template, account: account) }

      before do
        3.times { create_completed_run(duration_ms: 100, total_cost: 0.01) }
        2.times { create_failed_run }
        create(:ai_workflow_run, :cancelled, workflow: workflow,
               started_at: 1.day.ago, completed_at: 1.day.ago + 1.minute,
               cancelled_at: 1.day.ago + 1.minute)
      end

      it "counts workflows correctly" do
        result = service.workflow_metrics

        # workflow + active_workflow + draft_workflow + template_workflow
        expect(result[:total_workflows]).to eq(4)
        expect(result[:active_workflows]).to eq(3) # workflow(:active) + active_workflow + template_workflow
        expect(result[:template_workflows]).to eq(1)
      end

      it "counts executions correctly" do
        result = service.workflow_metrics

        expect(result[:total_executions]).to eq(6)
        expect(result[:successful_executions]).to eq(3)
        expect(result[:failed_executions]).to eq(2)
        expect(result[:cancelled_executions]).to eq(1)
      end

      it "calculates success rate as fraction" do
        result = service.workflow_metrics
        # 3 completed / 6 total finished = 0.5
        expect(result[:success_rate]).to eq(0.5)
      end

      it "calculates average duration" do
        result = service.workflow_metrics
        expect(result[:average_duration_ms]).to be_a(Numeric)
      end

      it "calculates total cost" do
        result = service.workflow_metrics
        expect(result[:total_cost]).to be >= 0
      end

      it "returns executions by status" do
        result = service.workflow_metrics
        expect(result[:executions_by_status]).to be_a(Hash)
        expect(result[:executions_by_status]["completed"]).to eq(3)
        expect(result[:executions_by_status]["failed"]).to eq(2)
      end

      it "returns executions by trigger" do
        result = service.workflow_metrics
        expect(result[:executions_by_trigger]).to be_a(Hash)
        expect(result[:executions_by_trigger]["manual"]).to be_present
      end
    end

    context "with different durations" do
      before do
        create_completed_run(duration_ms: 100)
        create_completed_run(duration_ms: 300)
        create_completed_run(duration_ms: 500)
      end

      it "calculates median duration" do
        result = service.workflow_metrics
        expect(result[:median_duration_ms]).to eq(300)
      end

      it "calculates p95 duration" do
        result = service.workflow_metrics
        expect(result[:p95_duration_ms]).to be_a(Numeric)
      end

      it "calculates p99 duration" do
        result = service.workflow_metrics
        expect(result[:p99_duration_ms]).to be_a(Numeric)
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
        create(:ai_agent, :inactive, account: account)
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
      it "returns zero counts" do
        result = service.execution_metrics

        expect(result[:total_node_executions]).to eq(0)
        expect(result[:retry_count]).to eq(0)
        expect(result[:timeout_count]).to eq(0)
      end

      it "returns queue time metrics" do
        result = service.execution_metrics

        expect(result[:queue_time]).to include(
          :average_ms, :p95_ms, :max_ms
        )
      end
    end

    context "with node executions" do
      before do
        run = create_completed_run
        node = create(:ai_workflow_node, workflow: workflow)
        create(:ai_workflow_node_execution, :completed,
               workflow_run: run, node: node)
      end

      it "counts node executions" do
        result = service.execution_metrics
        expect(result[:total_node_executions]).to be >= 1
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

    context "with runs" do
      before do
        5.times { create_completed_run(duration_ms: 200) }
        1.times { create_failed_run }
      end

      it "calculates throughput" do
        result = service.performance_metrics
        expect(result[:throughput][:executions_per_hour]).to be > 0
        expect(result[:throughput][:executions_per_day]).to be > 0
      end

      it "calculates latency percentiles" do
        result = service.performance_metrics
        expect(result[:latency][:p50_ms]).to be_a(Numeric)
        expect(result[:latency][:p95_ms]).to be_a(Numeric)
      end

      it "calculates error budget with actual data" do
        result = service.performance_metrics
        budget = result[:error_budget]

        expect(budget[:target_slo]).to eq(99.9)
        expect(budget[:actual_success_rate]).to be_a(Numeric)
        expect(budget[:actual_success_rate]).to be > 0
      end
    end
  end

  describe "#workflow_specific_metrics" do
    context "with no runs for workflow" do
      it "returns zero counts" do
        result = service.workflow_specific_metrics(workflow)

        expect(result[:workflow_id]).to eq(workflow.id)
        expect(result[:workflow_name]).to eq(workflow.name)
        expect(result[:total_executions]).to eq(0)
        expect(result[:successful_executions]).to eq(0)
        expect(result[:failed_executions]).to eq(0)
        expect(result[:success_rate]).to be_nil
      end
    end

    context "with runs" do
      before do
        3.times { create_completed_run(duration_ms: 200, total_cost: 0.01) }
        1.times { create_failed_run }
      end

      it "returns correct execution counts" do
        result = service.workflow_specific_metrics(workflow)

        expect(result[:total_executions]).to eq(4)
        expect(result[:successful_executions]).to eq(3)
        expect(result[:failed_executions]).to eq(1)
      end

      it "calculates success rate" do
        result = service.workflow_specific_metrics(workflow)
        # 3 completed out of 4 non-pending = 0.75
        expect(result[:success_rate]).to eq(0.75)
      end

      it "calculates average duration" do
        result = service.workflow_specific_metrics(workflow)
        expect(result[:average_duration_ms]).to be_a(Numeric)
      end

      it "calculates total cost" do
        result = service.workflow_specific_metrics(workflow)
        expect(result[:total_cost]).to be >= 0
      end

      it "returns execution timeline" do
        result = service.workflow_specific_metrics(workflow)
        expect(result[:execution_timeline]).to be_a(Hash)
      end

      it "returns trigger distribution" do
        result = service.workflow_specific_metrics(workflow)
        expect(result[:trigger_distribution]).to be_a(Hash)
      end

      it "includes node performance" do
        result = service.workflow_specific_metrics(workflow)
        expect(result[:node_performance]).to be_an(Array)
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

  describe "custom time range" do
    let(:service_7d) { described_class.new(account: account, time_range: 7.days) }

    it "respects the configured time range" do
      # Run within 7 days
      create_completed_run
      # Run outside 7 days - create workflow run with old timestamp
      old_run = create(:ai_workflow_run, :completed, workflow: workflow,
                       started_at: 10.days.ago,
                       completed_at: 10.days.ago + 1.minute,
                       created_at: 10.days.ago)

      result_30d = service.workflow_metrics
      result_7d = service_7d.workflow_metrics

      expect(result_30d[:total_executions]).to be >= result_7d[:total_executions]
    end
  end
end
