# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Analytics::DashboardService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:service) { described_class.new(account: account, time_range: 30.days) }

  # =========================================================================
  # #generate
  # =========================================================================
  describe "#generate" do
    it "returns a hash with expected top-level keys" do
      result = service.generate

      expect(result).to include(
        :summary, :trends, :highlights,
        :quick_stats, :resource_usage, :recent_activity
      )
    end

    it "caches the result for 15 minutes" do
      cache_key = "ai:dashboard:#{account.id}:#{30.days.to_i}"

      expect(Rails.cache).to receive(:fetch)
        .with(cache_key, expires_in: 15.minutes, force: false)
        .and_call_original

      service.generate
    end

    it "force-refreshes when requested" do
      cache_key = "ai:dashboard:#{account.id}:#{30.days.to_i}"

      expect(Rails.cache).to receive(:fetch)
        .with(cache_key, expires_in: 15.minutes, force: true)
        .and_call_original

      service.generate(force_refresh: true)
    end
  end

  # =========================================================================
  # .invalidate_cache
  # =========================================================================
  describe ".invalidate_cache" do
    it "deletes matched cache keys for the account" do
      expect(Rails.cache).to receive(:delete_matched)
        .with("ai:dashboard:#{account.id}:*")

      described_class.invalidate_cache(account.id)
    end
  end

  # =========================================================================
  # #generate_summary_metrics
  # =========================================================================
  describe "#generate_summary_metrics" do
    let(:workflow) { create(:ai_workflow, :active, account: account) }
    let(:agent) { create(:ai_agent, account: account, provider: provider) }

    context "with no data" do
      it "returns zero counts" do
        result = service.generate_summary_metrics

        expect(result[:workflows][:total]).to eq(0)
        expect(result[:agents][:total]).to eq(0)
        expect(result[:conversations][:total]).to eq(0)
        expect(result[:cost][:total]).to eq(0)
      end
    end

    context "with workflow and agent data" do
      before do
        create(:ai_workflow_run, :completed, workflow: workflow)
        create(:ai_workflow_run, :failed, workflow: workflow)
        create(:ai_agent_execution, :completed, agent: agent, account: account, provider: provider)
      end

      it "returns correct workflow metrics" do
        result = service.generate_summary_metrics

        expect(result[:workflows][:total]).to eq(1)
        expect(result[:workflows][:active]).to eq(1)
        expect(result[:workflows][:executions]).to eq(2)
      end

      it "returns correct agent metrics" do
        result = service.generate_summary_metrics

        expect(result[:agents][:total]).to eq(1)
        expect(result[:agents][:executions]).to eq(1)
      end

      it "calculates success rates" do
        result = service.generate_summary_metrics

        expect(result[:workflows][:success_rate]).to be_a(Float)
        expect(result[:agents][:success_rate]).to be_a(Float)
      end
    end

    context "with conversation data" do
      let!(:conversation) { create(:ai_conversation, account: account, status: "active") }
      let!(:message) { create(:ai_message, conversation: conversation) }

      it "counts conversations and messages" do
        result = service.generate_summary_metrics

        expect(result[:conversations][:total]).to eq(1)
        expect(result[:conversations][:active]).to eq(1)
        expect(result[:conversations][:messages]).to be >= 1
      end
    end
  end

  # =========================================================================
  # #generate_trend_data
  # =========================================================================
  describe "#generate_trend_data" do
    it "returns trend keys" do
      result = service.generate_trend_data

      expect(result).to include(
        :executions_by_day, :cost_by_day,
        :success_rate_by_day, :messages_by_day
      )
    end

    context "with workflow runs across multiple days" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        create(:ai_workflow_run, :completed, workflow: workflow, created_at: 2.days.ago)
        create(:ai_workflow_run, :completed, workflow: workflow, created_at: 1.day.ago)
      end

      it "groups executions by day" do
        result = service.generate_trend_data

        expect(result[:executions_by_day]).to be_a(Hash)
        expect(result[:executions_by_day].values.sum).to eq(2)
      end

      it "groups costs by day" do
        result = service.generate_trend_data

        expect(result[:cost_by_day]).to be_a(Hash)
        result[:cost_by_day].each_value do |cost|
          expect(cost).to be_a(Float)
        end
      end
    end
  end

  # =========================================================================
  # #generate_highlights
  # =========================================================================
  describe "#generate_highlights" do
    it "returns highlight keys" do
      result = service.generate_highlights

      expect(result).to include(
        :top_workflows, :top_agents,
        :recent_failures, :cost_leaders
      )
    end

    context "with workflow data" do
      let(:workflow1) { create(:ai_workflow, :active, account: account, name: "High Runner") }
      let(:workflow2) { create(:ai_workflow, :active, account: account, name: "Low Runner") }

      before do
        3.times { create(:ai_workflow_run, :completed, workflow: workflow1) }
        1.times { create(:ai_workflow_run, :completed, workflow: workflow2) }
      end

      it "returns top workflows sorted by execution count" do
        result = service.generate_highlights

        expect(result[:top_workflows].length).to be <= 5
        expect(result[:top_workflows].first[:name]).to eq("High Runner")
      end
    end

    context "with failures" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        create(:ai_workflow_run, :failed, workflow: workflow)
      end

      it "includes recent failures" do
        result = service.generate_highlights

        expect(result[:recent_failures]).not_to be_empty
        expect(result[:recent_failures].first).to include(:run_id, :workflow_name, :error)
      end
    end
  end

  # =========================================================================
  # #generate_quick_stats
  # =========================================================================
  describe "#generate_quick_stats" do
    it "returns today, yesterday, and this_week stats" do
      result = service.generate_quick_stats

      expect(result).to include(:today, :yesterday, :this_week)
      %i[today yesterday this_week].each do |period|
        expect(result[period]).to include(:executions, :cost, :messages)
      end
    end

    context "with today's data" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        create(:ai_workflow_run, :completed, workflow: workflow)
      end

      it "counts today's executions" do
        result = service.generate_quick_stats

        expect(result[:today][:executions]).to eq(1)
        expect(result[:this_week][:executions]).to eq(1)
      end
    end
  end

  # =========================================================================
  # #generate_resource_usage
  # =========================================================================
  describe "#generate_resource_usage" do
    it "returns resource usage keys" do
      result = service.generate_resource_usage

      expect(result).to include(:providers, :models, :tokens)
    end

    it "returns token usage with zero totals when no data" do
      result = service.generate_resource_usage

      expect(result[:tokens][:total_tokens]).to eq(0)
      expect(result[:tokens][:total_input_tokens]).to eq(0)
      expect(result[:tokens][:total_output_tokens]).to eq(0)
    end
  end

  # =========================================================================
  # #generate_recent_activity
  # =========================================================================
  describe "#generate_recent_activity" do
    let(:workflow) { create(:ai_workflow, :active, account: account) }

    it "returns an array sorted by created_at desc" do
      create(:ai_workflow_run, :completed, workflow: workflow)
      create(:ai_conversation, account: account)

      result = service.generate_recent_activity

      expect(result).to be_an(Array)
      expect(result.length).to be <= 20
    end

    it "respects the limit parameter" do
      3.times { create(:ai_workflow_run, :completed, workflow: workflow) }

      result = service.generate_recent_activity(limit: 2)

      expect(result.length).to be <= 2
    end

    it "includes both workflow runs and conversations" do
      create(:ai_workflow_run, :completed, workflow: workflow)
      create(:ai_conversation, account: account)

      result = service.generate_recent_activity
      types = result.map { |a| a[:type] }

      expect(types).to include("workflow_run")
      expect(types).to include("conversation")
    end

    it "returns activities with expected fields" do
      create(:ai_workflow_run, :completed, workflow: workflow)

      result = service.generate_recent_activity
      activity = result.first

      expect(activity).to include(:type, :status, :resource_name, :created_at)
    end
  end

  # =========================================================================
  # #real_time_metrics
  # =========================================================================
  describe "#real_time_metrics" do
    it "returns real-time metric keys" do
      result = service.real_time_metrics

      expect(result).to include(
        :active_executions, :active_conversations,
        :queue_depth, :error_rate_last_hour,
        :avg_response_time_last_hour, :timestamp
      )
    end

    it "caches for 1 minute" do
      cache_key = "ai:dashboard:realtime:#{account.id}"

      expect(Rails.cache).to receive(:fetch)
        .with(cache_key, expires_in: 1.minute, force: false)
        .and_call_original

      service.real_time_metrics
    end

    it "supports force refresh" do
      cache_key = "ai:dashboard:realtime:#{account.id}"

      expect(Rails.cache).to receive(:fetch)
        .with(cache_key, expires_in: 1.minute, force: true)
        .and_call_original

      service.real_time_metrics(force_refresh: true)
    end

    context "with running workflows" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        create(:ai_workflow_run, :running, workflow: workflow)
      end

      it "counts active executions" do
        result = service.real_time_metrics

        expect(result[:active_executions]).to eq(1)
      end
    end
  end

  # =========================================================================
  # #aiops_dashboard
  # =========================================================================
  describe "#aiops_dashboard" do
    it "returns comprehensive AIOps data" do
      result = service.aiops_dashboard

      expect(result).to include(
        :health, :overview, :providers, :workflows,
        :agents, :cost_analysis, :alerts, :circuit_breakers,
        :real_time, :generated_at
      )
    end

    it "accepts a custom time range" do
      result = service.aiops_dashboard(ops_time_range: 24.hours)

      expect(result[:overview][:time_range_seconds]).to eq(24.hours.to_i)
    end
  end

  # =========================================================================
  # #system_health
  # =========================================================================
  describe "#system_health" do
    it "returns overall health with component breakdown" do
      result = service.system_health

      expect(result).to include(
        :overall_score, :status, :components,
        :last_incident, :uptime_percentage
      )
    end

    it "includes all component health scores" do
      result = service.system_health

      expect(result[:components]).to include(
        :providers, :workflows, :agents, :infrastructure
      )
    end

    context "with no data" do
      it "reports healthy status" do
        result = service.system_health

        expect(result[:overall_score]).to eq(100)
        expect(result[:status]).to eq("healthy")
      end
    end

    context "with unhealthy provider metrics" do
      let!(:active_provider) { create(:ai_provider, account: account, is_active: true) }

      before do
        create(:ai_provider_metric, :unhealthy,
               provider: active_provider,
               account: account,
               recorded_at: 2.minutes.ago)
      end

      it "reflects degraded health score" do
        result = service.system_health

        expect(result[:components][:providers][:score]).to be < 100
      end
    end

    context "with many failed workflows" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        10.times { create(:ai_workflow_run, :failed, workflow: workflow, created_at: 30.minutes.ago) }
      end

      it "reduces workflow health score" do
        result = service.system_health

        expect(result[:components][:workflows][:score]).to be < 100
        expect(result[:components][:workflows][:issues]).not_to be_empty
      end
    end
  end

  # =========================================================================
  # #system_overview
  # =========================================================================
  describe "#system_overview" do
    let(:workflow) { create(:ai_workflow, :active, account: account) }

    it "returns system overview with default 1-hour range" do
      result = service.system_overview

      expect(result[:time_range_seconds]).to eq(1.hour.to_i)
      expect(result).to include(:workflows, :executions, :performance, :costs)
    end

    context "with completed and failed runs" do
      before do
        create(:ai_workflow_run, :completed, workflow: workflow, created_at: 30.minutes.ago)
        create(:ai_workflow_run, :failed, workflow: workflow, created_at: 20.minutes.ago)
      end

      it "computes correct counts and success rate" do
        result = service.system_overview

        expect(result[:workflows][:total]).to eq(2)
        expect(result[:workflows][:successful]).to eq(1)
        expect(result[:workflows][:failed]).to eq(1)
        expect(result[:workflows][:success_rate]).to eq(50.0)
      end
    end

    context "with no data" do
      it "returns 100% success rate when no runs exist" do
        result = service.system_overview

        expect(result[:workflows][:success_rate]).to eq(100)
        expect(result[:executions][:success_rate]).to eq(100)
      end
    end
  end

  # =========================================================================
  # #ops_provider_metrics
  # =========================================================================
  describe "#ops_provider_metrics" do
    let!(:active_provider) { create(:ai_provider, account: account, is_active: true) }

    context "with provider metrics" do
      before do
        create(:ai_provider_metric,
               provider: active_provider,
               account: account,
               recorded_at: 30.minutes.ago)
      end

      it "returns metrics for each provider" do
        result = service.ops_provider_metrics

        expect(result).to be_an(Array)
        expect(result.first[:provider_id]).to eq(active_provider.id)
        expect(result.first).to include(:metrics, :circuit_breaker, :health_status)
      end
    end

    context "without metrics" do
      it "returns unknown health status with empty metrics" do
        result = service.ops_provider_metrics

        entry = result.find { |p| p[:provider_id] == active_provider.id }
        expect(entry[:health_status]).to eq("unknown")
        expect(entry[:metrics][:request_count]).to eq(0)
      end
    end
  end

  # =========================================================================
  # #ops_provider_comparison
  # =========================================================================
  describe "#ops_provider_comparison" do
    it "delegates to ProviderMetric.provider_comparison" do
      expect(Ai::ProviderMetric).to receive(:provider_comparison)
        .with(account, time_range: 1.hour)
        .and_return({})

      service.ops_provider_comparison(ops_time_range: 1.hour)
    end
  end

  # =========================================================================
  # #ops_workflow_metrics
  # =========================================================================
  describe "#ops_workflow_metrics" do
    let!(:workflow) { create(:ai_workflow, :active, account: account) }

    context "with recent runs" do
      before do
        create(:ai_workflow_run, :completed, workflow: workflow, created_at: 30.minutes.ago)
        create(:ai_workflow_run, :failed, workflow: workflow, created_at: 20.minutes.ago)
      end

      it "returns workflow-level metrics" do
        result = service.ops_workflow_metrics

        expect(result).to be_an(Array)
        wf_metric = result.find { |w| w[:workflow_id] == workflow.id }
        expect(wf_metric[:metrics][:total_runs]).to eq(2)
        expect(wf_metric[:metrics][:successful]).to eq(1)
        expect(wf_metric[:metrics][:failed]).to eq(1)
      end
    end

    context "with no runs" do
      it "returns idle status" do
        result = service.ops_workflow_metrics

        wf_metric = result.find { |w| w[:workflow_id] == workflow.id }
        expect(wf_metric[:recent_status]).to eq("idle")
      end
    end
  end

  # =========================================================================
  # #ops_agent_metrics
  # =========================================================================
  describe "#ops_agent_metrics" do
    let!(:agent) { create(:ai_agent, account: account, provider: provider, status: "active") }

    context "with executions" do
      before do
        create(:ai_agent_execution, :completed,
               agent: agent, account: account, provider: provider,
               created_at: 30.minutes.ago,
               tokens_used: 500, cost_usd: 0.01)
      end

      it "returns agent-level metrics" do
        result = service.ops_agent_metrics

        agent_metric = result.find { |a| a[:agent_id] == agent.id }
        expect(agent_metric[:metrics][:total_executions]).to eq(1)
        expect(agent_metric[:metrics][:successful]).to eq(1)
        expect(agent_metric[:metrics][:total_tokens]).to be >= 0
      end
    end

    context "with no executions" do
      it "returns zero metrics with 100% success rate" do
        result = service.ops_agent_metrics

        agent_metric = result.find { |a| a[:agent_id] == agent.id }
        expect(agent_metric[:metrics][:total_executions]).to eq(0)
        expect(agent_metric[:metrics][:success_rate]).to eq(100)
      end
    end
  end

  # =========================================================================
  # #ops_cost_analysis
  # =========================================================================
  describe "#ops_cost_analysis" do
    it "returns cost analysis structure" do
      result = service.ops_cost_analysis

      expect(result).to include(
        :time_range_seconds, :totals, :by_category,
        :by_provider, :hourly_trend, :optimization_opportunities
      )
    end

    context "with workflow and agent costs" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }
      let(:agent) { create(:ai_agent, account: account, provider: provider) }

      before do
        create(:ai_workflow_run, :completed, workflow: workflow,
               created_at: 30.minutes.ago, total_cost: 0.05)
        create(:ai_agent_execution, :completed, agent: agent,
               account: account, provider: provider,
               created_at: 30.minutes.ago, cost_usd: 0.03)
      end

      it "sums workflow and agent costs" do
        result = service.ops_cost_analysis

        expect(result[:totals][:total_cost]).to be > 0
        expect(result[:totals][:workflow_cost]).to eq(0.05)
        expect(result[:totals][:agent_cost]).to eq(0.03)
      end
    end
  end

  # =========================================================================
  # #active_alerts
  # =========================================================================
  describe "#active_alerts" do
    context "with no issues" do
      it "returns empty alerts" do
        result = service.active_alerts

        expect(result).to be_an(Array)
        expect(result).to be_empty
      end
    end

    context "with unhealthy provider" do
      let!(:active_provider) { create(:ai_provider, account: account, is_active: true) }

      before do
        create(:ai_provider_metric, :unhealthy,
               provider: active_provider,
               account: account,
               recorded_at: 2.minutes.ago,
               success_count: 2,
               failure_count: 8,
               request_count: 10)
      end

      it "generates provider_unhealthy alert" do
        result = service.active_alerts

        unhealthy_alerts = result.select { |a| a[:type] == "provider_unhealthy" }
        expect(unhealthy_alerts).not_to be_empty
        expect(unhealthy_alerts.first[:severity]).to eq("critical")
      end
    end

    context "with open circuit breaker" do
      let!(:active_provider) { create(:ai_provider, account: account, is_active: true) }

      before do
        create(:ai_provider_metric,
               provider: active_provider,
               account: account,
               recorded_at: 2.minutes.ago,
               circuit_state: "open",
               consecutive_failures: 5)
      end

      it "generates circuit_breaker_open alert" do
        result = service.active_alerts

        cb_alerts = result.select { |a| a[:type] == "circuit_breaker_open" }
        expect(cb_alerts).not_to be_empty
        expect(cb_alerts.first[:severity]).to eq("warning")
      end
    end

    context "with high workflow failure rate" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        8.times { create(:ai_workflow_run, :failed, workflow: workflow, created_at: 5.minutes.ago) }
        3.times { create(:ai_workflow_run, :completed, workflow: workflow, created_at: 5.minutes.ago) }
      end

      it "generates high_failure_rate alert" do
        result = service.active_alerts

        failure_alerts = result.select { |a| a[:type] == "high_failure_rate" }
        expect(failure_alerts).not_to be_empty
        expect(failure_alerts.first[:severity]).to eq("critical")
      end
    end
  end

  # =========================================================================
  # #circuit_breaker_status
  # =========================================================================
  describe "#circuit_breaker_status" do
    let!(:active_provider) { create(:ai_provider, account: account, is_active: true) }

    it "returns status for each provider" do
      result = service.circuit_breaker_status

      expect(result).to be_an(Array)
      entry = result.find { |p| p[:provider_id] == active_provider.id }
      expect(entry).to include(:state, :consecutive_failures)
    end

    context "with no recent metrics" do
      it "defaults to closed state" do
        result = service.circuit_breaker_status

        entry = result.find { |p| p[:provider_id] == active_provider.id }
        expect(entry[:state]).to eq("closed")
        expect(entry[:consecutive_failures]).to eq(0)
      end
    end

    context "with open circuit breaker metric" do
      before do
        create(:ai_provider_metric,
               provider: active_provider,
               account: account,
               recorded_at: 2.minutes.ago,
               circuit_state: "open",
               consecutive_failures: 5)
      end

      it "reports open state" do
        result = service.circuit_breaker_status

        entry = result.find { |p| p[:provider_id] == active_provider.id }
        expect(entry[:state]).to eq("open")
        expect(entry[:consecutive_failures]).to eq(5)
      end
    end
  end

  # =========================================================================
  # #aiops_real_time_metrics
  # =========================================================================
  describe "#aiops_real_time_metrics" do
    it "returns real-time AIOps metric keys" do
      result = service.aiops_real_time_metrics

      expect(result).to include(
        :timestamp, :active_workflows, :requests_per_minute,
        :success_rate, :avg_latency_ms, :errors_last_minute,
        :cost_last_minute
      )
    end

    context "with no recent activity" do
      it "returns zero values and 100% success rate" do
        result = service.aiops_real_time_metrics

        expect(result[:requests_per_minute]).to eq(0)
        expect(result[:success_rate]).to eq(100.0)
        expect(result[:errors_last_minute]).to eq(0)
      end
    end
  end

  # =========================================================================
  # #record_execution_metrics
  # =========================================================================
  describe "#record_execution_metrics" do
    let!(:prov) { create(:ai_provider, account: account) }

    it "delegates to ProviderMetric.record_metrics" do
      execution_data = {
        success: true,
        timeout: false,
        rate_limited: false,
        input_tokens: 100,
        output_tokens: 50,
        cost_usd: 0.005,
        latency_ms: 350,
        error_type: nil,
        model_name: "gpt-4",
        circuit_state: "closed",
        consecutive_failures: 0
      }

      expect(Ai::ProviderMetric).to receive(:record_metrics).with(
        provider: prov,
        account: account,
        metrics_data: hash_including(
          requests: 1,
          successes: 1,
          failures: 0,
          input_tokens: 100,
          output_tokens: 50
        )
      )

      service.record_execution_metrics(provider: prov, execution_data: execution_data)
    end

    it "records failure when execution is not successful" do
      execution_data = {
        success: false,
        timeout: true,
        rate_limited: false,
        latency_ms: 30000,
        error_type: "timeout"
      }

      expect(Ai::ProviderMetric).to receive(:record_metrics).with(
        provider: prov,
        account: account,
        metrics_data: hash_including(
          successes: 0,
          failures: 1,
          timeouts: 1
        )
      )

      service.record_execution_metrics(provider: prov, execution_data: execution_data)
    end
  end

  # =========================================================================
  # Constants
  # =========================================================================
  describe "constants" do
    it "defines expected cache TTLs" do
      expect(described_class::DASHBOARD_CACHE_TTL).to eq(15.minutes)
      expect(described_class::REAL_TIME_CACHE_TTL).to eq(1.minute)
    end

    it "defines health thresholds" do
      expect(described_class::HEALTH_THRESHOLDS).to include(:healthy, :degraded, :unhealthy)
    end
  end

  # =========================================================================
  # Initialization
  # =========================================================================
  describe "#initialize" do
    it "sets account and time_range" do
      expect(service.account).to eq(account)
      expect(service.time_range).to eq(30.days)
    end

    it "defaults time_range to 30 days" do
      svc = described_class.new(account: account)

      expect(svc.time_range).to eq(30.days)
    end
  end
end
