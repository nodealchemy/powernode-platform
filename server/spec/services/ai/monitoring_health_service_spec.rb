# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::MonitoringHealthService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }

  subject(:service) { described_class.new(account: account) }

  before do
    # Stub CircuitBreakerRegistry to avoid Redis dependencies
    allow(Ai::CircuitBreakerRegistry).to receive(:health_summary).and_return({
      total_services: 5,
      healthy: 4,
      degraded: 1,
      unhealthy: 0,
      services: []
    })
  end

  # ===========================================================================
  # #comprehensive_health_check
  # ===========================================================================

  describe "#comprehensive_health_check" do
    it "returns complete health data with all sections" do
      health = service.comprehensive_health_check(skip_cache: true)

      expect(health[:timestamp]).to be_present
      expect(health[:system]).to be_a(Hash)
      expect(health[:database]).to be_a(Hash)
      expect(health[:redis]).to be_a(Hash)
      expect(health[:providers]).to be_a(Hash)
      expect(health[:workers]).to be_a(Hash)
      expect(health[:circuit_breakers]).to be_a(Hash)
      expect(health[:health_score]).to be_a(Numeric)
      expect(health[:status]).to be_present
    end

    it "calculates a health score between 0 and 100" do
      health = service.comprehensive_health_check(skip_cache: true)

      expect(health[:health_score]).to be_between(0, 100)
    end

    it "returns healthy status when all systems are up" do
      health = service.comprehensive_health_check(skip_cache: true)

      expect(health[:status]).to eq("healthy")
    end

    it "uses cache by default" do
      # First call populates cache
      health1 = service.comprehensive_health_check
      # Second call should use cache (same result)
      health2 = service.comprehensive_health_check

      expect(health1[:timestamp]).to eq(health2[:timestamp])
    end

    it "bypasses cache when skip_cache is true" do
      health1 = service.comprehensive_health_check(skip_cache: true)

      # Travel forward to get a different timestamp
      travel 5.seconds do
        health2 = service.comprehensive_health_check(skip_cache: true)

        # Timestamps should be different since cache is skipped
        expect(health2[:timestamp]).not_to eq(health1[:timestamp])
      end
    end
  end

  # ===========================================================================
  # #check_system_health
  # ===========================================================================

  describe "#check_system_health" do
    it "returns system health data" do
      result = service.check_system_health

      expect(result[:status]).to eq("healthy")
      expect(result).to have_key(:active_workflows)
      expect(result).to have_key(:active_agents)
      expect(result).to have_key(:running_executions)
    end

    it "counts active workflows for the account" do
      # The system checks is_active column, not status
      wf_active = create(:ai_workflow, account: account, creator: user, is_active: true)
      wf_inactive = create(:ai_workflow, account: account, creator: user, is_active: false)

      result = service.check_system_health

      expect(result[:active_workflows]).to eq(
        account.ai_workflows.where(is_active: true).count
      )
    end

    it "counts active agents for the account" do
      create(:ai_agent, account: account, provider: provider, status: "active")
      create(:ai_agent, account: account, provider: provider, status: "inactive")

      result = service.check_system_health

      expect(result[:active_agents]).to eq(1)
    end
  end

  # ===========================================================================
  # #check_database_health
  # ===========================================================================

  describe "#check_database_health" do
    it "returns healthy when database is connected" do
      result = service.check_database_health

      expect(result[:status]).to eq("healthy")
      expect(result[:connection]).to eq("active")
      expect(result[:connection_pool]).to be_a(Hash)
      expect(result[:connection_pool]).to have_key(:size)
    end

    it "returns unhealthy when database is unreachable" do
      allow(ActiveRecord::Base.connection).to receive(:execute)
        .and_raise(ActiveRecord::ConnectionNotEstablished.new("Connection failed"))

      result = service.check_database_health

      expect(result[:status]).to eq("unhealthy")
      expect(result[:error]).to be_present
    end
  end

  # ===========================================================================
  # #check_redis_health
  # ===========================================================================

  describe "#check_redis_health" do
    it "returns healthy when Redis is connected" do
      result = service.check_redis_health

      expect(result[:status]).to eq("healthy")
      expect(result[:used_memory]).to be_present
    end

    it "returns unhealthy when Redis is unreachable" do
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError.new("Connection refused"))

      result = service.check_redis_health

      expect(result[:status]).to eq("unhealthy")
      expect(result[:error]).to be_present
    end
  end

  # ===========================================================================
  # #check_provider_health
  # ===========================================================================

  describe "#check_provider_health" do
    it "returns provider health summary" do
      create(:ai_provider, account: account, is_active: true)

      result = service.check_provider_health

      expect(result[:total_providers]).to be >= 1
      expect(result[:providers]).to be_an(Array)
    end

    it "reports healthy when no recent failures" do
      create(:ai_provider, account: account, is_active: true)

      result = service.check_provider_health

      expect(result[:healthy_providers]).to be >= 1
    end

    it "excludes inactive providers" do
      create(:ai_provider, account: account, is_active: false)

      result = service.check_provider_health

      expect(result[:total_providers]).to eq(
        account.ai_providers.where(is_active: true).count
      )
    end
  end

  # ===========================================================================
  # #check_worker_health
  # ===========================================================================

  describe "#check_worker_health" do
    it "returns worker health status" do
      result = service.check_worker_health

      expect(result[:status]).to be_present
      expect(result).to have_key(:recent_completions)
      expect(result).to have_key(:recent_starts)
      expect(result).to have_key(:estimated_backlog)
    end

    it "reports healthy when no backlog exists" do
      result = service.check_worker_health

      expect(result[:status]).to eq("healthy")
      expect(result[:estimated_backlog]).to eq(0)
    end
  end

  # ===========================================================================
  # #detailed_health
  # ===========================================================================

  describe "#detailed_health" do
    it "returns detailed health for all services" do
      result = service.detailed_health

      expect(result[:timestamp]).to be_present
      expect(result[:services]).to be_a(Hash)
      expect(result[:services]).to have_key(:database)
      expect(result[:services]).to have_key(:redis)
      expect(result[:services]).to have_key(:providers)
      expect(result[:services]).to have_key(:workflows)
      expect(result[:services]).to have_key(:agents)
      expect(result[:services]).to have_key(:workers)
      expect(result[:recent_activity]).to be_a(Hash)
      expect(result[:performance_metrics]).to be_a(Hash)
    end
  end

  # ===========================================================================
  # #connectivity_check
  # ===========================================================================

  describe "#connectivity_check" do
    it "returns connectivity test results" do
      result = service.connectivity_check

      expect(result[:timestamp]).to be_present
      expect(result[:database]).to be_a(Hash)
      expect(result[:redis]).to be_a(Hash)
      expect(result[:providers]).to be_an(Array)
      expect(result[:workers]).to be_a(Hash)
      expect(result[:external_services]).to be_a(Hash)
    end

    it "measures database response time" do
      result = service.connectivity_check

      expect(result[:database][:status]).to eq("healthy")
      expect(result[:database][:response_time_ms]).to be_a(Numeric)
    end
  end

  # ===========================================================================
  # #calculate_overall_health_score / #determine_health_status
  # ===========================================================================

  describe "#calculate_overall_health_score" do
    it "returns 100 when all systems are healthy with no providers" do
      health_data = {
        database: { status: "healthy" },
        redis: { status: "healthy" },
        providers: { total_providers: 0, healthy_providers: 0 },
        workers: { status: "healthy" }
      }

      score = service.calculate_overall_health_score(health_data)

      expect(score).to eq(100)
    end

    it "reduces score when database is unhealthy" do
      healthy_data = {
        database: { status: "healthy" },
        redis: { status: "healthy" },
        providers: { total_providers: 0, healthy_providers: 0 },
        workers: { status: "healthy" }
      }
      unhealthy_data = healthy_data.merge(database: { status: "unhealthy" })

      healthy_score = service.calculate_overall_health_score(healthy_data)
      unhealthy_score = service.calculate_overall_health_score(unhealthy_data)

      expect(unhealthy_score).to be < healthy_score
    end

    it "reduces score when some providers are unhealthy" do
      data = {
        database: { status: "healthy" },
        redis: { status: "healthy" },
        providers: { total_providers: 4, healthy_providers: 2 },
        workers: { status: "healthy" }
      }

      score = service.calculate_overall_health_score(data)

      expect(score).to be < 100
    end
  end

  describe "#determine_health_status" do
    it "returns healthy for scores 80-100" do
      expect(service.determine_health_status(95)).to eq("healthy")
      expect(service.determine_health_status(80)).to eq("healthy")
    end

    it "returns degraded for scores 50-79" do
      expect(service.determine_health_status(75)).to eq("degraded")
      expect(service.determine_health_status(50)).to eq("degraded")
    end

    it "returns unhealthy for scores 20-49" do
      expect(service.determine_health_status(30)).to eq("unhealthy")
    end

    it "returns critical for scores below 20" do
      expect(service.determine_health_status(10)).to eq("critical")
    end
  end

  # ===========================================================================
  # Class methods
  # ===========================================================================

  describe "HealthChecks.invalidate_provider_health_cache" do
    it "clears provider health cache for an account" do
      expect(Rails.cache).to receive(:delete)
        .with("ai:monitoring:provider_health:#{account.id}")
      allow(Rails.cache).to receive(:delete_matched)

      described_class::HealthChecks.invalidate_provider_health_cache(account.id)
    end
  end
end
