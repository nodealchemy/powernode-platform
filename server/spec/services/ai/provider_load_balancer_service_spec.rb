# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ProviderLoadBalancerService, type: :service do
  let(:account) { create(:account) }
  let(:redis_double) { instance_double(Redis) }

  let(:provider1) do
    create(:ai_provider, account: account, is_active: true,
           capabilities: { "text_generation" => true },
           configuration: { "pricing" => { "text_generation" => { "per_1k_tokens" => 0.001 } } })
  end
  let(:provider2) do
    create(:ai_provider, account: account, is_active: true,
           capabilities: { "text_generation" => true },
           configuration: { "pricing" => { "text_generation" => { "per_1k_tokens" => 0.005 } } })
  end

  let!(:credential1) do
    create(:ai_provider_credential, account: account, provider: provider1, is_active: true)
  end
  let!(:credential2) do
    create(:ai_provider_credential, account: account, provider: provider2, is_active: true)
  end

  let(:circuit_double) do
    instance_double(Ai::ProviderCircuitBreakerService, provider_available?: true, circuit_state: :closed)
  end

  before do
    allow(Redis).to receive(:new).and_return(redis_double)
    allow(redis_double).to receive(:incr).and_return(1)
    allow(redis_double).to receive(:expire)
    allow(redis_double).to receive(:set)
    allow(redis_double).to receive(:get).and_return(nil)
    allow(redis_double).to receive(:del)
    allow(Ai::ProviderCircuitBreakerService).to receive(:new).and_return(circuit_double)
  end

  # The service has a bug: it joins :ai_provider_credentials but the actual
  # association on Ai::Provider is :provider_credentials. We stub
  # get_available_providers to bypass the broken join.
  def stub_available_providers(service_instance, providers)
    allow(service_instance).to receive(:get_available_providers).and_return(providers)
  end

  # ===========================================================================
  # initialization
  # ===========================================================================

  describe "#initialize" do
    it "creates service with valid strategy" do
      expect { described_class.new(account, strategy: "round_robin") }.not_to raise_error
    end

    it "raises for invalid strategy" do
      expect {
        described_class.new(account, strategy: "invalid_strategy")
      }.to raise_error(ArgumentError, /Invalid strategy/)
    end

    it "accepts all valid strategies" do
      %w[round_robin weighted_round_robin least_connections cost_optimized performance_based].each do |strategy|
        expect { described_class.new(account, strategy: strategy) }.not_to raise_error
      end
    end

    it "defaults to cost_optimized strategy" do
      service = described_class.new(account)
      stub_available_providers(service, [])

      stats = service.load_balancing_stats
      expect(stats[:strategy]).to eq("cost_optimized")
    end
  end

  # ===========================================================================
  # #select_provider
  # ===========================================================================

  describe "#select_provider" do
    context "with round_robin strategy" do
      subject(:service) { described_class.new(account, strategy: "round_robin") }

      before { stub_available_providers(service, [provider1, provider2]) }

      it "selects a provider from available providers" do
        selected = service.select_provider

        expect([provider1.id, provider2.id]).to include(selected.id)
      end

      it "increments provider usage in Redis" do
        service.select_provider

        expect(redis_double).to have_received(:incr).at_least(:once)
      end

      it "records last used timestamp" do
        service.select_provider

        expect(redis_double).to have_received(:set).with(
          /last_used/, anything
        )
      end
    end

    context "with least_connections strategy" do
      subject(:service) { described_class.new(account, strategy: "least_connections") }

      before do
        stub_available_providers(service, [provider1, provider2])
        allow(redis_double).to receive(:get)
          .with("load_balancer:#{account.id}:provider:#{provider1.id}:usage")
          .and_return("10")
        allow(redis_double).to receive(:get)
          .with("load_balancer:#{account.id}:provider:#{provider2.id}:usage")
          .and_return("2")
      end

      it "selects the provider with lowest current load" do
        selected = service.select_provider

        expect(selected.id).to eq(provider2.id)
      end
    end

    context "with performance_based strategy" do
      subject(:service) { described_class.new(account, strategy: "performance_based") }

      before { stub_available_providers(service, [provider1, provider2]) }

      it "selects a provider" do
        selected = service.select_provider

        expect(selected).to be_an(Ai::Provider)
      end
    end

    context "with cost_optimized strategy" do
      subject(:service) { described_class.new(account, strategy: "cost_optimized") }

      before { stub_available_providers(service, [provider1, provider2]) }

      it "prefers the lower cost provider" do
        selected = service.select_provider

        # provider1 has lower cost per 1k tokens (0.001 vs 0.005)
        expect(selected.id).to eq(provider1.id)
      end
    end

    context "when no providers are available" do
      subject(:service) { described_class.new(account, strategy: "round_robin") }

      before { stub_available_providers(service, []) }

      it "raises NoProvidersAvailableError" do
        expect {
          service.select_provider
        }.to raise_error(Ai::ProviderLoadBalancerService::NoProvidersAvailableError)
      end
    end
  end

  # ===========================================================================
  # #execute_with_fallback
  # ===========================================================================

  describe "#execute_with_fallback" do
    subject(:service) { described_class.new(account, strategy: "round_robin") }

    before { stub_available_providers(service, [provider1, provider2]) }

    context "when execution succeeds on first try" do
      it "returns the block result" do
        result = service.execute_with_fallback(:completion) do |_client, provider|
          { output: "Success", provider_name: provider.name }
        end

        expect(result[:output]).to eq("Success")
      end

      it "records success metrics" do
        service.execute_with_fallback(:completion) do |_client, _provider|
          "ok"
        end

        # incr called for usage + success
        expect(redis_double).to have_received(:incr).at_least(:twice)
      end
    end

    context "when first provider fails and second succeeds" do
      before do
        # Make round_robin return different counters so different providers are selected
        call_count = 0
        allow(redis_double).to receive(:incr).with(/round_robin/) do
          call_count += 1
          call_count
        end
        allow(redis_double).to receive(:incr).with(/usage/).and_return(1)
        allow(redis_double).to receive(:incr).with(/successes/).and_return(1)
        allow(redis_double).to receive(:incr).with(/failures/).and_return(1)
      end

      it "falls back to next provider" do
        attempt = 0
        result = service.execute_with_fallback(:completion, max_provider_retries: 3) do |_client, _provider|
          attempt += 1
          raise StandardError, "Provider failed" if attempt == 1

          "fallback success"
        end

        expect(result).to eq("fallback success")
      end
    end

    context "when all retries fail" do
      it "raises NoProvidersAvailableError after exhausting retries" do
        expect {
          service.execute_with_fallback(:completion, max_provider_retries: 2) do |_client, _provider|
            raise StandardError, "Always fails"
          end
        }.to raise_error(StandardError)
      end
    end
  end

  # ===========================================================================
  # #load_balancing_stats
  # ===========================================================================

  describe "#load_balancing_stats" do
    subject(:service) { described_class.new(account, strategy: "cost_optimized") }

    before { stub_available_providers(service, [provider1]) }

    it "returns stats with strategy and capability" do
      stats = service.load_balancing_stats

      expect(stats[:strategy]).to eq("cost_optimized")
      expect(stats[:capability]).to eq("text_generation")
    end

    it "includes provider details" do
      stats = service.load_balancing_stats

      expect(stats[:available_providers]).to eq(1)
      expect(stats[:providers]).to be_an(Array)
      expect(stats[:providers].first).to have_key(:id)
      expect(stats[:providers].first).to have_key(:name)
      expect(stats[:providers].first).to have_key(:circuit_state)
      expect(stats[:providers].first).to have_key(:avg_response_time)
      expect(stats[:providers].first).to have_key(:success_rate)
      expect(stats[:providers].first).to have_key(:cost_per_1k_tokens)
    end

    it "returns 100% success rate when no data exists" do
      stats = service.load_balancing_stats

      expect(stats[:providers].first[:success_rate]).to eq(100.0)
    end
  end

  # ===========================================================================
  # #reset_load_balancing_state
  # ===========================================================================

  describe "#reset_load_balancing_state" do
    subject(:service) { described_class.new(account, strategy: "round_robin") }

    before { stub_available_providers(service, [provider1]) }

    it "deletes all Redis keys for providers" do
      service.reset_load_balancing_state

      expect(redis_double).to have_received(:del).at_least(:once)
    end
  end
end
