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
      cache_key = CacheVersioning.key("ai:dashboard:#{account.id}", 30.days.to_i)

      expect(Rails.cache).to receive(:fetch)
        .with(cache_key, expires_in: 15.minutes, force: false)
        .and_call_original

      service.generate
    end

    it "force-refreshes when requested" do
      cache_key = CacheVersioning.key("ai:dashboard:#{account.id}", 30.days.to_i)

      expect(Rails.cache).to receive(:fetch)
        .with(cache_key, expires_in: 15.minutes, force: true)
        .and_call_original

      service.generate(force_refresh: true)
    end
  end

  # =========================================================================
  # .invalidate_cache
  #
  # IMP-63a7d2f99c56. Used to call Rails.cache.delete_matched, which the
  # production default store (solid_cache) does not implement — see
  # CacheVersioning's header. A state oracle rather than a message
  # expectation, exercised against NoDeleteMatchedCacheStore
  # (spec/support/no_delete_matched_cache_store.rb) so passing here means
  # something on the store the app actually resolves in production, not on
  # the test env's MemoryStore (which implements delete_matched and would
  # hide the whole defect class).
  # =========================================================================
  describe ".invalidate_cache" do
    it "does not raise on a cache store that cannot delete_matched" do
      allow(Rails).to receive(:cache).and_return(NoDeleteMatchedCacheStore.new)

      expect { described_class.invalidate_cache(account.id) }.not_to raise_error
    end

    it "retires a previously cached #generate result for the account" do
      allow(Rails).to receive(:cache).and_return(NoDeleteMatchedCacheStore.new)
      service.generate # populate the cache under the pre-invalidation key
      stale_key = CacheVersioning.key("ai:dashboard:#{account.id}", 30.days.to_i)
      Rails.cache.write(stale_key, { stale: true })
      expect(service.generate).to include(stale: true) # still reading the stale entry

      described_class.invalidate_cache(account.id)

      expect(service.generate).not_to include(stale: true) # unaddressable, recomputed
    end
  end

  # =========================================================================
  # #generate_summary_metrics
  # =========================================================================
  describe "#generate_summary_metrics" do
    let(:agent) { create(:ai_agent, account: account, provider: provider) }

    context "with no data" do
      it "returns zero counts" do
        result = service.generate_summary_metrics

        expect(result[:agents][:total]).to eq(0)
        expect(result[:conversations][:total]).to eq(0)
        expect(result[:cost][:total]).to eq(0)
      end
    end

    context "with agent data" do
      before do
        create(:ai_agent_execution, :completed, agent: agent, account: account, provider: provider)
      end

      it "returns correct agent metrics" do
        result = service.generate_summary_metrics

        expect(result[:agents][:total]).to eq(1)
        expect(result[:agents][:executions]).to eq(1)
      end

      it "calculates success rates" do
        result = service.generate_summary_metrics

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

    context "with agent executions across multiple days" do
      let(:agent) { create(:ai_agent, account: account, provider: provider) }

      before do
        create(:ai_agent_execution, :completed, agent: agent, account: account, provider: provider, created_at: 2.days.ago)
        create(:ai_agent_execution, :completed, agent: agent, account: account, provider: provider, created_at: 1.day.ago)
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
        :top_agents, :recent_failures
      )
    end

    context "with failures" do
      let(:agent) { create(:ai_agent, account: account, provider: provider) }

      before do
        create(:ai_agent_execution, :failed, agent: agent, account: account, provider: provider)
      end

      it "includes recent failures" do
        result = service.generate_highlights

        expect(result[:recent_failures]).not_to be_empty
        expect(result[:recent_failures].first).to include(:execution_id, :agent_name, :error)
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
        expect(result[period]).to include(:cost, :messages)
      end
    end
  end

  # =========================================================================
  # #generate_resource_usage
  # =========================================================================
  describe "#generate_resource_usage" do
    it "returns resource usage keys" do
      result = service.generate_resource_usage

      expect(result).to include(:providers, :models)
    end
  end

  # =========================================================================
  # #generate_recent_activity
  # =========================================================================
  describe "#generate_recent_activity" do
    it "returns an array sorted by created_at desc" do
      create(:ai_conversation, account: account)

      result = service.generate_recent_activity

      expect(result).to be_an(Array)
      expect(result.length).to be <= 20
    end

    it "respects the limit parameter" do
      3.times { create(:ai_conversation, account: account) }

      result = service.generate_recent_activity(limit: 2)

      expect(result.length).to be <= 2
    end

    it "includes conversations" do
      create(:ai_conversation, account: account)

      result = service.generate_recent_activity
      types = result.map { |a| a[:type] }

      expect(types).to include("conversation")
    end

    it "returns activities with expected fields" do
      create(:ai_conversation, account: account)

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

    context "with running agent executions" do
      let(:agent) { create(:ai_agent, account: account, provider: provider) }

      before do
        create(:ai_agent_execution, :running, agent: agent, account: account, provider: provider)
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
        :health, :overview, :providers,
        :agents, :cost_analysis, :alerts, :circuit_breakers,
        :real_time, :generated_at
      )
    end

    it "accepts a custom time range" do
      result = service.aiops_dashboard(ops_time_range: 24.hours)

      expect(result[:overview][:time_range_seconds]).to eq(24.hours.to_i)
    end

    it "folds latency_aggregate into the overview" do
      result = service.aiops_dashboard

      expect(result[:overview]).to have_key(:latency_aggregate)
      expect(result[:overview][:latency_aggregate].keys).to contain_exactly(
        :avg_ms, :p95_ms, :p99_ms, :max_ms, :sample_provider_count
      )
    end
  end

  # =========================================================================
  # #ops_aggregate_latency
  # =========================================================================
  describe "#ops_aggregate_latency" do
    context "with metrics across multiple providers" do
      let!(:provider_a) { create(:ai_provider, account: account) }
      let!(:provider_b) { create(:ai_provider, account: account) }

      before do
        create(:ai_provider_metric,
               provider: provider_a, account: account, recorded_at: 5.minutes.ago,
               request_count: 5, success_count: 5, failure_count: 0,
               avg_latency_ms: 100, p95_latency_ms: 200, p99_latency_ms: 300, max_latency_ms: 400)
        create(:ai_provider_metric,
               provider: provider_b, account: account, recorded_at: 5.minutes.ago,
               request_count: 5, success_count: 5, failure_count: 0,
               avg_latency_ms: 300, p95_latency_ms: 500, p99_latency_ms: 700, max_latency_ms: 900)
      end

      it "aggregates avg/p95/p99/max and counts sampled providers" do
        result = service.ops_aggregate_latency(1.hour)

        expect(result[:avg_ms]).to eq(200.0)
        expect(result[:p95_ms]).to eq(500.0)
        expect(result[:p99_ms]).to eq(700.0)
        expect(result[:max_ms]).to eq(900.0)
        expect(result[:sample_provider_count]).to eq(2)
      end
    end

    context "with no metrics" do
      it "returns all zeros and a zero sample count" do
        result = service.ops_aggregate_latency

        expect(result).to eq(
          avg_ms: 0.0, p95_ms: 0.0, p99_ms: 0.0, max_ms: 0.0, sample_provider_count: 0
        )
      end
    end
  end

  # =========================================================================
  # #aiops_trends
  # =========================================================================
  describe "#aiops_trends" do
    it "returns the expected envelope keys" do
      result = service.aiops_trends(6.hours)

      expect(result).to include(
        :time_range_seconds, :bucket, :bucket_count,
        :latency, :error_rate, :throughput, :cost
      )
      expect(result[:bucket]).to eq("hour")
      expect(result[:time_range_seconds]).to eq(6.hours.to_i)
    end

    it "zero-fills every series to bucket_count == requested hours" do
      result = service.aiops_trends(6.hours)

      expect(result[:bucket_count]).to eq(6)
      expect(result[:latency].size).to eq(6)
      expect(result[:error_rate].size).to eq(6)
      expect(result[:throughput].size).to eq(6)
      expect(result[:cost].size).to eq(6)
    end

    it "uses ascending ISO8601 UTC bucket keys" do
      result = service.aiops_trends(6.hours)
      keys = result[:latency].map { |b| b[:bucket] }

      expect(keys).to eq(keys.sort)
      expect(keys).to all(end_with("Z"))
      expect { Time.iso8601(keys.first) }.not_to raise_error
      # Same bucket keys are shared across all series.
      expect(result[:error_rate].map { |b| b[:bucket] }).to eq(keys)
      expect(result[:throughput].map { |b| b[:bucket] }).to eq(keys)
      expect(result[:cost].map { |b| b[:bucket] }).to eq(keys)
    end

    it "caps bucket_count at 168 for ranges beyond 7 days" do
      result = service.aiops_trends(30.days)

      expect(result[:bucket_count]).to eq(168)
      expect(result[:latency].size).to eq(168)
      expect(result[:error_rate].size).to eq(168)
      expect(result[:throughput].size).to eq(168)
      expect(result[:cost].size).to eq(168)
    end

    context "with hourly provider metrics (primary source)" do
      before do
        create(:ai_provider_metric, :hourly,
               provider: provider, account: account,
               recorded_at: Time.current.utc.beginning_of_hour,
               request_count: 10, success_count: 9, failure_count: 1,
               avg_latency_ms: 200, p95_latency_ms: 400, p99_latency_ms: 480)
      end

      it "sources latency p95/p99 from provider metrics" do
        result = service.aiops_trends(2.hours)
        current = result[:latency].last

        expect(current[:avg_ms]).to eq(200.0)
        expect(current[:p95_ms]).to eq(400.0)
        expect(current[:p99_ms]).to eq(480.0)
      end

      it "computes error_rate as a 0.0-1.0 fraction per bucket" do
        result = service.aiops_trends(2.hours)
        current = result[:error_rate].last

        expect(current[:request_count]).to eq(10)
        expect(current[:error_rate]).to eq(0.1)
      end

      it "computes requests_per_minute as requests / 60.0" do
        result = service.aiops_trends(2.hours)
        current = result[:throughput].last

        expect(current[:requests]).to eq(10)
        expect(current[:requests_per_minute]).to eq(10 / 60.0)
      end
    end

    context "with only agent executions (no hourly provider metrics)" do
      let(:agent) { create(:ai_agent, account: account, provider: provider) }

      before do
        create(:ai_agent_execution, :completed,
               agent: agent, account: account, provider: provider,
               created_at: Time.current, duration_ms: 300)
      end

      it "falls back to executions with p95_ms == p99_ms == avg_ms" do
        result = service.aiops_trends(2.hours)
        current = result[:latency].last

        expect(current[:avg_ms]).to be > 0
        expect(current[:p95_ms]).to eq(current[:avg_ms])
        expect(current[:p99_ms]).to eq(current[:avg_ms])
      end
    end
  end

  # =========================================================================
  # #ops_recent_errors
  # =========================================================================
  describe "#ops_recent_errors" do
    let(:svc) { described_class.new(account: account, time_range: 24.hours) }
    let(:agent) { create(:ai_agent, account: account, provider: provider) }

    context "with failures" do
      let!(:older) do
        create(:ai_agent_execution, :failed, agent: agent, account: account,
               provider: provider, created_at: 3.hours.ago)
      end
      let!(:newer) do
        create(:ai_agent_execution, :failed, agent: agent, account: account,
               provider: provider, created_at: 1.hour.ago)
      end

      it "returns failures newest-first" do
        result = svc.ops_recent_errors

        expect(result.map { |e| e[:execution_id] }).to eq([ newer.id, older.id ])
      end

      it "respects the limit" do
        result = svc.ops_recent_errors(limit: 1)

        expect(result.length).to eq(1)
        expect(result.first[:execution_id]).to eq(newer.id)
      end

      it "returns entries with the expected fields" do
        result = svc.ops_recent_errors

        expect(result.first).to include(:execution_id, :agent_name, :error, :failed_at)
      end
    end

    context "with no failures" do
      it "returns an empty array" do
        expect(svc.ops_recent_errors).to eq([])
      end
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
        :providers, :agents, :infrastructure
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
  end

  # =========================================================================
  # #system_overview
  # =========================================================================
  describe "#system_overview" do
    let(:agent) { create(:ai_agent, account: account, provider: provider) }

    it "returns system overview with default 1-hour range" do
      result = service.system_overview

      expect(result[:time_range_seconds]).to eq(1.hour.to_i)
      expect(result).to include(:executions, :performance, :costs)
    end

    context "with completed and failed executions" do
      before do
        create(:ai_agent_execution, :completed, agent: agent, account: account, provider: provider, created_at: 30.minutes.ago)
        create(:ai_agent_execution, :failed, agent: agent, account: account, provider: provider, created_at: 20.minutes.ago)
      end

      it "computes correct counts and success rate" do
        result = service.system_overview

        expect(result[:executions][:total]).to eq(2)
        expect(result[:executions][:successful]).to eq(1)
        expect(result[:executions][:failed]).to eq(1)
        expect(result[:executions][:success_rate]).to eq(50.0)
      end
    end

    context "with no data" do
      it "returns 100% success rate when no executions exist" do
        result = service.system_overview

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

    context "with agent costs" do
      let(:agent) { create(:ai_agent, account: account, provider: provider) }

      before do
        create(:ai_agent_execution, :completed, agent: agent,
               account: account, provider: provider,
               created_at: 30.minutes.ago, cost_usd: 0.03)
      end

      it "sums agent costs" do
        result = service.ops_cost_analysis

        expect(result[:totals][:total_cost]).to be > 0
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
    it "returns the real-time AIOps metric keys consumed by the dashboard" do
      result = service.aiops_real_time_metrics

      expect(result).to include(
        :timestamp, :current_requests_per_second, :current_avg_latency_ms,
        :current_error_rate, :active_connections, :queue_depth
      )
    end

    context "with no recent activity" do
      it "returns zero values and a zero error rate" do
        result = service.aiops_real_time_metrics

        expect(result[:current_requests_per_second]).to eq(0.0)
        expect(result[:current_error_rate]).to eq(0.0)
        expect(result[:active_connections]).to eq(0)
        expect(result[:queue_depth]).to eq(0)
      end
    end

    context "with executions in flight" do
      let(:agent) { create(:ai_agent, account: account) }

      it "counts running executions as connections and pending as queue depth" do
        create(:ai_agent_execution, account: account, agent: agent, status: "running")
        create(:ai_agent_execution, account: account, agent: agent, status: "pending")
        create(:ai_agent_execution, account: account, agent: agent, status: "pending")

        result = service.aiops_real_time_metrics

        expect(result[:active_connections]).to eq(1)
        expect(result[:queue_depth]).to eq(2)
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

  # =========================================================================
  # Regression: success_rate_by_day computed the date via `total.key(count)`
  # (a value-based reverse lookup), so two days sharing the same execution
  # count collapsed to the first matching day's numerator — a 0%-success day
  # was reported with an earlier 100% day's rate.
  # =========================================================================
  describe "#generate_trend_data success_rate_by_day with colliding daily totals" do
    let(:agent) { create(:ai_agent, account: account, provider: provider) }

    it "computes each day's rate from its own completed count" do
      day_a = 2.days.ago.noon
      day_b = 1.day.ago.noon
      2.times { create(:ai_agent_execution, :completed, agent: agent, account: account, provider: provider, created_at: day_a) }
      2.times { create(:ai_agent_execution, :failed, agent: agent, account: account, provider: provider, created_at: day_b) }

      rates = service.generate_trend_data[:success_rate_by_day].values
      expect(rates).to contain_exactly(100.0, 0.0)
    end
  end
end
