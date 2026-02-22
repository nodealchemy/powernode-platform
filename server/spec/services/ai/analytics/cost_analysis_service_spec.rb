# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Analytics::CostAnalysisService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:service) { described_class.new(account: account, time_range: 30.days) }

  # =========================================================================
  # Initialization
  # =========================================================================
  describe "#initialize" do
    it "sets account, time_range, and hourly_rate" do
      expect(service.account).to eq(account)
      expect(service.time_range).to eq(30.days)
      expect(service.hourly_rate).to eq(75.0)
    end

    it "accepts a custom hourly rate" do
      svc = described_class.new(account: account, hourly_rate: 100.0)

      expect(svc.hourly_rate).to eq(100.0)
    end

    it "defines expected constants" do
      expect(described_class::DEFAULT_HOURLY_RATE).to eq(75.0)
      expect(described_class::DEFAULT_TIME_SAVED_PER_TASK).to eq(0.25)
    end
  end

  # =========================================================================
  # #full_analysis
  # =========================================================================
  describe "#full_analysis" do
    it "returns a hash with all analysis keys" do
      result = service.full_analysis

      expect(result).to include(
        :total_cost, :cost_trend, :cost_by_provider,
        :cost_by_agent, :cost_by_workflow, :cost_by_model,
        :daily_costs, :budget_status, :optimization_potential,
        :budget_forecast, :anomalies
      )
    end
  end

  # =========================================================================
  # #calculate_total_cost
  # =========================================================================
  describe "#calculate_total_cost" do
    context "with no data" do
      it "returns zero totals" do
        result = service.calculate_total_cost

        expect(result[:total]).to eq(0)
        expect(result[:workflow_cost]).to eq(0)
        expect(result[:currency]).to eq("USD")
        expect(result[:period_start]).to be_present
        expect(result[:period_end]).to be_present
      end
    end

    context "with workflow costs" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 0.50)
        create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 0.30)
      end

      it "sums workflow costs" do
        result = service.calculate_total_cost

        expect(result[:workflow_cost]).to eq(0.80)
        expect(result[:total]).to eq(0.80)
      end
    end
  end

  # =========================================================================
  # #calculate_cost_trend
  # =========================================================================
  describe "#calculate_cost_trend" do
    context "with no data" do
      it "returns nil change percentage" do
        result = service.calculate_cost_trend

        expect(result[:change_percentage]).to be_nil
        expect(result[:trend_direction]).to eq("unknown")
      end
    end

    context "with data in both periods" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        # Current period
        create(:ai_workflow_run, :completed, workflow: workflow,
               total_cost: 1.0, created_at: 10.days.ago)
        # Previous period
        create(:ai_workflow_run, :completed, workflow: workflow,
               total_cost: 0.5, created_at: 40.days.ago)
      end

      it "calculates percentage change" do
        result = service.calculate_cost_trend

        expect(result[:current_period_cost]).to be > 0
        expect(result[:previous_period_cost]).to be > 0
        expect(result[:change_percentage]).to be_a(Float)
        expect(result[:trend_direction]).to eq("increasing")
      end
    end

    context "when cost decreased" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        create(:ai_workflow_run, :completed, workflow: workflow,
               total_cost: 0.3, created_at: 10.days.ago)
        create(:ai_workflow_run, :completed, workflow: workflow,
               total_cost: 1.0, created_at: 40.days.ago)
      end

      it "reports decreasing trend" do
        result = service.calculate_cost_trend

        expect(result[:change_percentage]).to be < 0
        expect(result[:trend_direction]).to eq("decreasing")
      end
    end
  end

  # =========================================================================
  # #cost_breakdown_by_provider
  # =========================================================================
  describe "#cost_breakdown_by_provider" do
    it "returns an array of provider cost breakdowns" do
      create(:ai_provider, account: account)

      result = service.cost_breakdown_by_provider

      expect(result).to be_an(Array)
      result.each do |entry|
        expect(entry).to include(
          :provider_id, :provider_name, :provider_type,
          :total_cost, :execution_count, :cost_per_execution
        )
      end
    end

    it "returns empty array when no providers exist" do
      result = service.cost_breakdown_by_provider

      # Provider from let block exists but may have no cost data
      expect(result).to be_an(Array)
    end

    it "is sorted by total_cost descending" do
      result = service.cost_breakdown_by_provider

      costs = result.map { |p| p[:total_cost] }
      expect(costs).to eq(costs.sort.reverse)
    end
  end

  # =========================================================================
  # #cost_breakdown_by_agent
  # =========================================================================
  describe "#cost_breakdown_by_agent" do
    it "returns an array of agent cost breakdowns" do
      result = service.cost_breakdown_by_agent

      expect(result).to be_an(Array)
    end

    context "with agents" do
      let!(:agent) { create(:ai_agent, account: account, provider: provider) }

      it "includes each agent with cost data" do
        result = service.cost_breakdown_by_agent

        expect(result.length).to be >= 1
        entry = result.find { |a| a[:agent_id] == agent.id }
        expect(entry).to include(:agent_name, :agent_type, :total_cost, :execution_count)
      end
    end
  end

  # =========================================================================
  # #cost_breakdown_by_workflow
  # =========================================================================
  describe "#cost_breakdown_by_workflow" do
    context "with workflows and runs" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 0.10)
        create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 0.20)
      end

      it "returns per-workflow cost data" do
        result = service.cost_breakdown_by_workflow

        wf_entry = result.find { |w| w[:workflow_id] == workflow.id }
        expect(wf_entry[:total_cost]).to eq(0.30)
        expect(wf_entry[:execution_count]).to eq(2)
        expect(wf_entry[:cost_per_execution]).to eq(0.15)
      end

      it "includes avg_duration_ms" do
        result = service.cost_breakdown_by_workflow

        wf_entry = result.find { |w| w[:workflow_id] == workflow.id }
        expect(wf_entry).to have_key(:avg_duration_ms)
      end
    end

    context "with no workflows" do
      it "returns empty array" do
        result = service.cost_breakdown_by_workflow

        expect(result).to eq([])
      end
    end
  end

  # =========================================================================
  # #cost_breakdown_by_model
  # =========================================================================
  describe "#cost_breakdown_by_model" do
    it "returns an array sorted by cost descending" do
      result = service.cost_breakdown_by_model

      expect(result).to be_an(Array)
      costs = result.map { |m| m[:total_cost] }
      expect(costs).to eq(costs.sort.reverse)
    end

    context "with node executions containing model metadata" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }
      let(:run) { create(:ai_workflow_run, :completed, workflow: workflow) }

      before do
        create(:ai_workflow_node_execution, :completed,
               workflow_run: run,
               cost: 0.05,
               metadata: { "model" => "gpt-4", "token_usage" => { "input_tokens" => 100, "output_tokens" => 50 } })
        create(:ai_workflow_node_execution, :completed,
               workflow_run: run,
               cost: 0.01,
               metadata: { "model" => "gpt-3.5-turbo", "token_usage" => { "input_tokens" => 200, "output_tokens" => 100 } })
      end

      it "groups costs by model" do
        result = service.cost_breakdown_by_model

        expect(result.length).to eq(2)
        gpt4 = result.find { |m| m[:model] == "gpt-4" }
        expect(gpt4[:total_cost]).to eq(0.05)
        expect(gpt4[:input_tokens]).to eq(100)
        expect(gpt4[:output_tokens]).to eq(50)
      end
    end
  end

  # =========================================================================
  # #daily_cost_breakdown
  # =========================================================================
  describe "#daily_cost_breakdown" do
    context "with no data" do
      it "returns an empty hash" do
        result = service.daily_cost_breakdown

        expect(result).to eq({})
      end
    end

    context "with runs across multiple days" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        create(:ai_workflow_run, :completed, workflow: workflow,
               total_cost: 0.10, created_at: 2.days.ago)
        create(:ai_workflow_run, :completed, workflow: workflow,
               total_cost: 0.20, created_at: 1.day.ago)
      end

      it "returns daily costs as string-keyed hash" do
        result = service.daily_cost_breakdown

        expect(result.keys.length).to eq(2)
        result.each do |date, cost|
          expect(date).to be_a(String)
          expect(cost).to be_a(Float)
        end
      end
    end
  end

  # =========================================================================
  # #budget_analysis
  # =========================================================================
  describe "#budget_analysis" do
    it "returns budget keys" do
      result = service.budget_analysis

      expect(result).to include(
        :period_budget, :monthly_budget,
        :current_period_spend, :current_month_spend,
        :budget_utilization, :monthly_utilization,
        :projected_month_end, :days_remaining,
        :budget_alert
      )
    end

    context "with no budget configured" do
      it "returns nil for utilization percentages" do
        result = service.budget_analysis

        expect(result[:budget_utilization]).to be_nil
        expect(result[:monthly_utilization]).to be_nil
      end
    end

    context "with budget configured" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        account.update!(settings: { "ai_budget_limit" => 100.0, "ai_monthly_budget" => 200.0 })
        create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 50.0)
      end

      it "calculates budget utilization" do
        result = service.budget_analysis

        expect(result[:period_budget]).to eq(100.0)
        expect(result[:monthly_budget]).to eq(200.0)
        expect(result[:budget_utilization]).to be > 0
        expect(result[:monthly_utilization]).to be > 0
      end
    end

    context "budget alerts" do
      before do
        account.update!(settings: { "ai_budget_limit" => 10.0 })
      end

      let(:workflow) { create(:ai_workflow, :active, account: account) }

      it "generates warning when budget exceeds 80%" do
        create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 9.0)

        result = service.budget_analysis

        warning_alerts = result[:budget_alert].select { |a| a[:level] == "warning" }
        expect(warning_alerts).not_to be_empty
      end

      it "generates critical alert when budget exceeded" do
        create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 15.0)

        result = service.budget_analysis

        critical_alerts = result[:budget_alert].select { |a| a[:level] == "critical" }
        expect(critical_alerts).not_to be_empty
      end
    end
  end

  # =========================================================================
  # #estimate_cost_savings
  # =========================================================================
  describe "#estimate_cost_savings" do
    it "returns a hash with total_potential_savings and opportunities" do
      result = service.estimate_cost_savings

      expect(result).to include(:total_potential_savings, :opportunities)
      expect(result[:opportunities]).to be_an(Array)
    end

    context "with expensive workflows" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        3.times do
          create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 1.0)
        end
      end

      it "identifies expensive workflow opportunities" do
        result = service.estimate_cost_savings

        expensive = result[:opportunities].select { |o| o[:type] == "expensive_workflow" }
        expect(expensive).not_to be_empty
      end
    end

    context "with gpt-4 model usage over $10" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }
      let(:run) { create(:ai_workflow_run, :completed, workflow: workflow) }

      before do
        20.times do
          create(:ai_workflow_node_execution, :completed,
                 workflow_run: run,
                 cost: 0.60,
                 metadata: { "model" => "gpt-4" })
        end
      end

      it "suggests model downgrade" do
        result = service.estimate_cost_savings

        downgrades = result[:opportunities].select { |o| o[:type] == "model_downgrade" }
        expect(downgrades).not_to be_empty
      end
    end
  end

  # =========================================================================
  # #generate_budget_forecast
  # =========================================================================
  describe "#generate_budget_forecast" do
    context "with no daily costs" do
      it "returns nil" do
        result = service.generate_budget_forecast

        expect(result).to be_nil
      end
    end

    context "with enough daily cost data" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        10.times do |i|
          create(:ai_workflow_run, :completed, workflow: workflow,
                 total_cost: 0.10 + (i * 0.01),
                 created_at: (10 - i).days.ago)
        end
      end

      it "returns forecast data" do
        result = service.generate_budget_forecast

        expect(result).to include(
          :average_daily_cost, :daily_trend,
          :forecast_next_7_days, :forecast_next_30_days,
          :forecast_month_end, :confidence_level
        )
      end

      it "reports high confidence with > 7 days of data" do
        result = service.generate_budget_forecast

        expect(result[:confidence_level]).to eq("high")
      end

      it "returns numeric forecasts" do
        result = service.generate_budget_forecast

        expect(result[:average_daily_cost]).to be_a(Float)
        expect(result[:forecast_next_7_days]).to be_a(Float)
        expect(result[:forecast_next_30_days]).to be_a(Float)
      end
    end

    context "with very few data points" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        3.times do |i|
          create(:ai_workflow_run, :completed, workflow: workflow,
                 total_cost: 0.10, created_at: (3 - i).days.ago)
        end
      end

      it "reports low confidence" do
        result = service.generate_budget_forecast

        expect(result[:confidence_level]).to eq("low")
      end
    end
  end

  # =========================================================================
  # #detect_cost_anomalies
  # =========================================================================
  describe "#detect_cost_anomalies" do
    context "with fewer than 7 days of data" do
      it "returns empty array" do
        result = service.detect_cost_anomalies

        expect(result).to eq([])
      end
    end

    context "with anomalous spending" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        # Normal days
        8.times do |i|
          create(:ai_workflow_run, :completed, workflow: workflow,
                 total_cost: 0.10, created_at: (10 - i).days.ago)
        end
        # Anomalous day (10x spike)
        create(:ai_workflow_run, :completed, workflow: workflow,
               total_cost: 5.0, created_at: 1.day.ago)
      end

      it "detects cost anomalies" do
        result = service.detect_cost_anomalies

        expect(result).not_to be_empty
        anomaly = result.first
        expect(anomaly).to include(:date, :cost, :expected_cost, :deviation, :severity)
      end

      it "sorts anomalies by deviation descending" do
        result = service.detect_cost_anomalies

        deviations = result.map { |a| a[:deviation].abs }
        expect(deviations).to eq(deviations.sort.reverse)
      end
    end

    context "with uniform spending" do
      let(:workflow) { create(:ai_workflow, :active, account: account) }

      before do
        10.times do |i|
          create(:ai_workflow_run, :completed, workflow: workflow,
                 total_cost: 0.10, created_at: (10 - i).days.ago)
        end
      end

      it "detects no anomalies" do
        result = service.detect_cost_anomalies

        expect(result).to be_empty
      end
    end
  end

  # =========================================================================
  # ROI ANALYTICS
  # =========================================================================

  # =========================================================================
  # #roi_dashboard
  # =========================================================================
  describe "#roi_dashboard" do
    it "returns ROI dashboard structure" do
      result = service.roi_dashboard

      expect(result).to include(
        :summary, :trends, :by_workflow, :by_agent,
        :by_provider, :projections, :recommendations,
        :generated_at
      )
    end

    it "uses the service time_range by default" do
      expect(service).to receive(:roi_summary_metrics).with(30.days).at_least(:once).and_call_original
      expect(service).to receive(:roi_trends).with(30.days).and_call_original

      service.roi_dashboard
    end

    it "accepts a custom period" do
      expect(service).to receive(:roi_summary_metrics).with(7.days).at_least(:once).and_call_original

      service.roi_dashboard(period: 7.days)
    end
  end

  # =========================================================================
  # #roi_summary_metrics
  # =========================================================================
  describe "#roi_summary_metrics" do
    context "with no data" do
      it "returns zero-valued summary" do
        result = service.roi_summary_metrics

        expect(result[:costs][:total]).to eq(0)
        expect(result[:value][:total]).to eq(0)
        expect(result[:roi][:percentage]).to eq(0)
        expect(result[:activity][:total_tasks]).to eq(0)
      end
    end

    context "with ROI metrics and cost attributions" do
      before do
        # Callback recalculates total_value_usd = time_saved_value_usd + error_reduction_value_usd + throughput_value_usd
        # and total_cost_usd = ai_cost_usd + infrastructure_cost_usd
        # So we set component values that produce the desired totals
        create(:ai_roi_metric,
               account: account,
               period_date: 5.days.ago.to_date,
               ai_cost_usd: 10.0,
               infrastructure_cost_usd: 2.0,
               time_saved_hours: 5.0,
               time_saved_value_usd: 50.0,
               error_reduction_value_usd: 30.0,
               throughput_value_usd: 20.0,
               tasks_completed: 50,
               tasks_automated: 40)
      end

      it "calculates positive ROI" do
        result = service.roi_summary_metrics

        expect(result[:costs][:ai]).to eq(10.0)
        expect(result[:costs][:infrastructure]).to eq(2.0)
        expect(result[:costs][:total]).to eq(12.0)
        # total_value = 50 + 30 + 20 = 100
        expect(result[:value][:total]).to eq(100.0)
        expect(result[:roi][:is_positive]).to be true
      end

      it "computes automation rate" do
        result = service.roi_summary_metrics

        expect(result[:activity][:automation_rate]).to eq(80.0)
        expect(result[:activity][:cost_per_task]).to be > 0
      end
    end
  end

  # =========================================================================
  # #roi_trends
  # =========================================================================
  describe "#roi_trends" do
    it "delegates to RoiMetric.roi_trends" do
      expect(Ai::RoiMetric).to receive(:roi_trends)
        .with(account, days: 30)
        .and_return([])

      service.roi_trends
    end

    it "accepts a custom period" do
      expect(Ai::RoiMetric).to receive(:roi_trends)
        .with(account, days: 7)
        .and_return([])

      service.roi_trends(7.days)
    end
  end

  # =========================================================================
  # #roi_daily_metrics
  # =========================================================================
  describe "#roi_daily_metrics" do
    context "with no metrics" do
      it "returns zero-valued entries for each day" do
        result = service.roi_daily_metrics(days: 3)

        expect(result.length).to eq(4) # 3 days ago through today
        result.each do |day|
          expect(day[:cost]).to eq(0)
          expect(day[:value]).to eq(0)
          expect(day[:roi]).to eq(0)
        end
      end
    end

    context "with metrics for specific days" do
      before do
        # Callback recalculates total_cost_usd and total_value_usd from components
        create(:ai_roi_metric,
               account: account,
               metric_type: "account_total",
               period_type: "daily",
               period_date: Date.current,
               ai_cost_usd: 8.0,
               infrastructure_cost_usd: 2.0,
               time_saved_value_usd: 30.0,
               error_reduction_value_usd: 10.0,
               throughput_value_usd: 10.0,
               tasks_completed: 20,
               time_saved_hours: 3.0)
      end

      it "returns real data for days with metrics" do
        result = service.roi_daily_metrics(days: 7)

        today_entry = result.find { |d| d[:date] == Date.current }
        # total_cost = 8 + 2 = 10, total_value = 30 + 10 + 10 = 50
        expect(today_entry[:cost]).to eq(10.0)
        expect(today_entry[:value]).to eq(50.0)
        expect(today_entry[:tasks]).to eq(20)
      end
    end
  end

  # =========================================================================
  # #roi_by_workflow
  # =========================================================================
  describe "#roi_by_workflow" do
    context "with no data" do
      it "returns empty array" do
        result = service.roi_by_workflow

        expect(result).to eq([])
      end
    end

    context "with workflow runs" do
      let(:workflow) { create(:ai_workflow, :active, account: account, name: "Test WF") }

      before do
        create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 0.10)
        create(:ai_workflow_run, :completed, workflow: workflow, total_cost: 0.20)
        create(:ai_workflow_run, :failed, workflow: workflow, total_cost: 0.05)
      end

      it "computes ROI per workflow" do
        result = service.roi_by_workflow

        wf = result.find { |w| w[:workflow_id] == workflow.id }
        expect(wf[:total_runs]).to eq(3)
        expect(wf[:successful_runs]).to eq(2)
        expect(wf[:total_cost]).to be > 0
        expect(wf[:time_saved_hours]).to eq(0.5) # 2 successful * 0.25
        expect(wf[:value_generated]).to eq(37.5) # 0.5 * 75
      end

      it "calculates success rate" do
        result = service.roi_by_workflow

        wf = result.find { |w| w[:workflow_id] == workflow.id }
        expect(wf[:success_rate]).to be_within(0.1).of(66.67)
      end

      it "sorts by ROI percentage descending" do
        result = service.roi_by_workflow

        rois = result.map { |w| w[:roi_percentage] }
        expect(rois).to eq(rois.sort.reverse)
      end
    end
  end

  # =========================================================================
  # #roi_by_agent
  # =========================================================================
  describe "#roi_by_agent" do
    context "with no data" do
      it "returns empty array" do
        result = service.roi_by_agent

        expect(result).to eq([])
      end
    end

    context "with agent executions" do
      let(:agent) { create(:ai_agent, account: account, provider: provider) }

      before do
        create(:ai_agent_execution, :completed, agent: agent,
               account: account, provider: provider,
               cost_usd: 0.05, tokens_used: 500)
        create(:ai_agent_execution, :completed, agent: agent,
               account: account, provider: provider,
               cost_usd: 0.10, tokens_used: 1000)
      end

      it "computes ROI per agent" do
        result = service.roi_by_agent

        ag = result.find { |a| a[:agent_id] == agent.id }
        expect(ag[:total_executions]).to eq(2)
        expect(ag[:successful_executions]).to eq(2)
        expect(ag[:total_cost]).to eq(0.15)
        # time_saved = 2 * (0.25 / 2) = 0.25
        expect(ag[:time_saved_hours]).to eq(0.25)
        # value = 0.25 * 75 = 18.75
        expect(ag[:value_generated]).to eq(18.75)
      end

      it "sorts by ROI percentage descending" do
        result = service.roi_by_agent

        rois = result.map { |a| a[:roi_percentage] }
        expect(rois).to eq(rois.sort.reverse)
      end
    end
  end

  # =========================================================================
  # #roi_cost_by_provider
  # =========================================================================
  describe "#roi_cost_by_provider" do
    it "delegates to CostAttribution.cost_breakdown_by_provider" do
      expect(Ai::CostAttribution).to receive(:cost_breakdown_by_provider)
        .with(account, start_date: 30.days.ago.to_date, end_date: Date.current)
        .and_return([])

      service.roi_cost_by_provider
    end
  end

  # =========================================================================
  # #roi_projections
  # =========================================================================
  describe "#roi_projections" do
    context "with fewer than 7 days of data" do
      it "returns nil" do
        result = service.roi_projections

        expect(result).to be_nil
      end
    end

    context "with sufficient data" do
      before do
        10.times do |i|
          # Callback recalculates totals from components
          create(:ai_roi_metric,
                 account: account,
                 period_date: (10 - i).days.ago.to_date,
                 ai_cost_usd: 8.0 + i,
                 infrastructure_cost_usd: 2.0,
                 time_saved_value_usd: 30.0 + i,
                 error_reduction_value_usd: 10.0 + (i * 0.5),
                 throughput_value_usd: 10.0 + (i * 0.5),
                 tasks_completed: 20 + i,
                 time_saved_hours: 2.0 + (i * 0.1))
        end
      end

      it "returns projection data" do
        result = service.roi_projections

        expect(result).to include(
          :based_on_days, :daily_averages, :growth_trends,
          :monthly_projection, :quarterly_projection, :yearly_projection
        )
      end

      it "provides daily averages" do
        result = service.roi_projections

        expect(result[:daily_averages]).to include(:cost, :value, :tasks, :roi)
        expect(result[:daily_averages][:cost]).to be > 0
      end

      it "provides monthly, quarterly, and yearly projections" do
        result = service.roi_projections

        expect(result[:monthly_projection][:cost]).to be > 0
        expect(result[:quarterly_projection][:cost]).to be > 0
        expect(result[:yearly_projection][:cost]).to be > 0
      end
    end
  end

  # =========================================================================
  # #roi_recommendations
  # =========================================================================
  describe "#roi_recommendations" do
    context "with no data" do
      it "returns empty array" do
        result = service.roi_recommendations

        expect(result).to be_an(Array)
      end
    end

    context "with negative ROI" do
      before do
        create(:ai_roi_metric, :negative_roi,
               account: account,
               period_date: 5.days.ago.to_date)
      end

      it "generates critical negative ROI recommendation" do
        result = service.roi_recommendations

        critical = result.select { |r| r[:type] == "critical" }
        expect(critical).not_to be_empty
        expect(critical.first[:title]).to include("Negative ROI")
      end
    end

    it "returns recommendations sorted by priority" do
      result = service.roi_recommendations

      priorities = result.map { |r| r[:priority] }
      expect(priorities).to eq(priorities.sort)
    end
  end

  # =========================================================================
  # #roi_calculate_for_date
  # =========================================================================
  describe "#roi_calculate_for_date" do
    it "delegates to RoiMetric.calculate_for_account" do
      expect(Ai::RoiMetric).to receive(:calculate_for_account)
        .with(account, period_type: "daily", period_date: Date.current)

      service.roi_calculate_for_date
    end

    it "accepts a custom date" do
      date = 5.days.ago.to_date
      expect(Ai::RoiMetric).to receive(:calculate_for_account)
        .with(account, period_type: "daily", period_date: date)

      service.roi_calculate_for_date(date: date)
    end
  end

  # =========================================================================
  # #roi_calculate_for_range
  # =========================================================================
  describe "#roi_calculate_for_range" do
    it "calculates metrics for each day in range" do
      start_date = 2.days.ago.to_date
      end_date = Date.current

      expect(Ai::RoiMetric).to receive(:calculate_for_account).exactly(3).times

      service.roi_calculate_for_range(start_date: start_date, end_date: end_date)
    end
  end

  # =========================================================================
  # #roi_aggregate_metrics
  # =========================================================================
  describe "#roi_aggregate_metrics" do
    it "delegates to RoiMetric.aggregate_for_period" do
      expect(Ai::RoiMetric).to receive(:aggregate_for_period)
        .with(account, period_type: "weekly", period_date: Date.current)

      service.roi_aggregate_metrics(period_type: "weekly")
    end

    it "defaults to weekly aggregation" do
      expect(Ai::RoiMetric).to receive(:aggregate_for_period)
        .with(account, period_type: "weekly", period_date: Date.current)

      service.roi_aggregate_metrics
    end
  end

  # =========================================================================
  # #roi_compare_periods
  # =========================================================================
  describe "#roi_compare_periods" do
    it "returns comparison between two periods" do
      result = service.roi_compare_periods

      expect(result).to include(:current_period, :previous_period, :changes)
      expect(result[:current_period]).to include(:start, :end, :metrics)
      expect(result[:previous_period]).to include(:start, :end, :metrics)
      expect(result[:changes]).to include(
        :cost_change, :value_change, :tasks_change,
        :roi_change, :time_saved_change
      )
    end

    it "uses correct date ranges" do
      result = service.roi_compare_periods(current_period: 7.days, previous_period: 7.days)

      expect(result[:current_period][:end]).to eq(Date.current)
      expect(result[:current_period][:start]).to eq(7.days.ago.to_date)
    end
  end

  # =========================================================================
  # FINOPS METHODS
  # =========================================================================

  # =========================================================================
  # #budget_enforcement
  # =========================================================================
  describe "#budget_enforcement" do
    context "with no budget configured" do
      it "returns not configured" do
        result = service.budget_enforcement

        expect(result[:configured]).to be false
        expect(result[:message]).to include("No monthly budget")
      end
    end

    context "with budget configured" do
      before do
        account.update!(settings: { "ai_monthly_budget" => 100.0 })
      end

      it "returns budget enforcement data" do
        result = service.budget_enforcement

        expect(result[:configured]).to be true
        expect(result[:monthly_budget]).to eq(100.0)
        expect(result[:utilization_percentage]).to be_a(Float)
        expect(result[:remaining]).to be_a(Float)
        expect(result[:alert]).to include(:level, :message)
      end

      context "when budget is exceeded" do
        let(:workflow) { create(:ai_workflow, :active, account: account) }

        before do
          create(:ai_workflow_run, :completed, workflow: workflow,
                 total_cost: 150.0, created_at: Time.current)
        end

        it "reports critical alert" do
          result = service.budget_enforcement

          expect(result[:alert][:level]).to eq("critical")
          expect(result[:utilization_percentage]).to be >= 100
        end
      end

      context "when budget is at warning level" do
        let(:workflow) { create(:ai_workflow, :active, account: account) }

        before do
          create(:ai_workflow_run, :completed, workflow: workflow,
                 total_cost: 92.0, created_at: Time.current)
        end

        it "reports warning alert" do
          result = service.budget_enforcement

          expect(result[:alert][:level]).to eq("warning")
        end
      end

      context "when budget is healthy" do
        let(:workflow) { create(:ai_workflow, :active, account: account) }

        before do
          create(:ai_workflow_run, :completed, workflow: workflow,
                 total_cost: 10.0, created_at: Time.current)
        end

        it "reports normal alert" do
          result = service.budget_enforcement

          expect(result[:alert][:level]).to eq("normal")
        end
      end
    end

    context "with custom account_id" do
      let(:other_account) { create(:account, settings: { "ai_monthly_budget" => 50.0 }) }

      it "analyzes the specified account" do
        result = service.budget_enforcement(account_id: other_account.id)

        expect(result[:configured]).to be true
        expect(result[:monthly_budget]).to eq(50.0)
      end
    end
  end

  # =========================================================================
  # #finops_optimization_score
  # =========================================================================
  describe "#finops_optimization_score" do
    it "delegates to TokenAnalyticsService" do
      token_service = instance_double(Ai::Finops::TokenAnalyticsService)
      expect(Ai::Finops::TokenAnalyticsService).to receive(:new)
        .with(account: account)
        .and_return(token_service)
      expect(token_service).to receive(:optimization_score)
        .and_return({ score: 85 })

      result = service.finops_optimization_score

      expect(result[:score]).to eq(85)
    end

    it "accepts custom account_id" do
      other_account = create(:account)
      token_service = instance_double(Ai::Finops::TokenAnalyticsService)
      expect(Ai::Finops::TokenAnalyticsService).to receive(:new)
        .with(account: other_account)
        .and_return(token_service)
      expect(token_service).to receive(:optimization_score)
        .and_return({ score: 70 })

      service.finops_optimization_score(account_id: other_account.id)
    end
  end
end
