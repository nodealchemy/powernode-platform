# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::MonitoringHealthService, type: :service do
  let(:account) { create(:account) }
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
      expect(result).to have_key(:active_agents)
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
      expect(result[:error_class]).to eq("ActiveRecord::ConnectionNotEstablished")
      expect(result).not_to have_key(:error)
    end
  end

  # ===========================================================================
  # #check_redis_health
  # ===========================================================================

  describe "#check_redis_health" do
    it "returns healthy when Redis is connected" do
      result = service.check_redis_health

      expect(result[:status]).to eq("healthy")
      expect(result[:connected_clients]).to be_a(Integer)
    end

    it "returns unhealthy when Redis is unreachable" do
      client = instance_double(Redis)
      allow(client).to receive(:ping).and_raise(Redis::CannotConnectError.new("Connection refused"))
      allow(Powernode::Redis).to receive(:client).and_return(client)

      result = service.check_redis_health

      expect(result).to eq(status: "unhealthy", error_class: "Redis::CannotConnectError")
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
  # E7b: #calculate_overall_health_score and #determine_health_status are GONE
  # ===========================================================================
  #
  # This service reports measurements and stamps no verdict on them. The
  # status-plane rollup is the one health score (design section 4.4). The
  # examples that used to live here asserted the 4x25% blend and its
  # healthy/degraded/unhealthy/critical buckets; both are deleted, and
  # spec/lint/rival_health_producer_spec.rb keeps them deleted.

  describe "the deleted verdict" do
    it "does not stamp a score or a status onto the health payload" do
      health = service.comprehensive_health_check(skip_cache: true)

      expect(health).not_to have_key(:health_score)
      expect(health).not_to have_key(:status)
    end

    it "still returns the measurements the checks produce" do
      health = service.comprehensive_health_check(skip_cache: true)

      expect(health).to have_key(:database)
      expect(health).to have_key(:redis)
      expect(health).to have_key(:providers)
      expect(health).to have_key(:workers)
    end
  end

  # ===========================================================================
  # Class methods
  # ===========================================================================

  describe "HealthChecks.invalidate_provider_health_cache" do
    # Asserted on the cache's contents, not on a message expectation over the
    # process-wide Rails.cache: a global after-hook deletes its own key there
    # too, and a strict `expect(Rails.cache).to receive(:delete)` rejects it.
    it "clears provider health cache for an account, and no other account's" do
      key = "ai:monitoring:provider_health:#{account.id}"
      other_key = "ai:monitoring:provider_health:#{create(:account).id}"
      Rails.cache.write(key, { healthy: true })
      Rails.cache.write(other_key, { healthy: true })

      described_class::HealthChecks.invalidate_provider_health_cache(account.id)

      expect(Rails.cache.exist?(key)).to be(false)
      expect(Rails.cache.exist?(other_key)).to be(true)
    end
  end
end
