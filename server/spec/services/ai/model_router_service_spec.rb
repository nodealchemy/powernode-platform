# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ModelRouterService do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account, provider_type: "openai", api_base_url: "https://api.openai.com/v1") }
  let(:credential) { create(:ai_provider_credential, provider: provider, account: account, credentials: { "api_key" => "sk-test-key-that-is-long-enough-for-validation-1234567890" }) }

  describe "#initialize" do
    it "creates service with default strategy" do
      service = described_class.new(account: account)
      expect(service).to be_present
    end

    it "raises on invalid strategy" do
      expect { described_class.new(account: account, strategy: "invalid") }
        .to raise_error(ArgumentError, /Invalid strategy/)
    end

    it "accepts all valid strategies" do
      described_class::STRATEGIES.each do |strategy|
        expect { described_class.new(account: account, strategy: strategy) }.not_to raise_error
      end
    end
  end

  describe "MODEL_TIERS" do
    it "defines economy, standard, and premium tiers" do
      expect(described_class::MODEL_TIERS.keys).to contain_exactly("economy", "standard", "premium")
    end

    it "includes expected models in each tier" do
      expect(described_class::MODEL_TIERS["economy"]).to include("gpt-4.1-nano")
      expect(described_class::MODEL_TIERS["standard"]).to include("gpt-4.1-mini")
      expect(described_class::MODEL_TIERS["premium"]).to include("gpt-4.1")
    end
  end

  describe "TASK_TIER_MAP" do
    it "maps classification tasks to economy" do
      expect(described_class::TASK_TIER_MAP["classification"]).to eq("economy")
    end

    it "maps analysis tasks to standard" do
      expect(described_class::TASK_TIER_MAP["analysis"]).to eq("standard")
    end

    it "maps reasoning tasks to premium" do
      expect(described_class::TASK_TIER_MAP["reasoning"]).to eq("premium")
    end

    it "covers all expected task types" do
      expect(described_class::TASK_TIER_MAP.keys).to include(
        "classification", "extraction", "summarization", "code_generation", "reasoning"
      )
    end
  end

  describe "#route_for_task" do
    let(:service) { described_class.new(account: account) }

    before do
      credential # ensure exists
      allow(service).to receive(:route).and_return({
        provider: provider,
        decision_id: "test-id",
        strategy_used: "cost_optimized",
        scoring: {},
        estimated_cost: 0.001,
        estimated_latency_ms: 500
      })
      allow(service).to receive(:models_for_tier).and_return(["gpt-4.1-nano"])
    end

    it "returns routing with model tier" do
      result = service.route_for_task(task_type: "classification")
      expect(result[:model_tier]).to eq("economy")
    end

    it "includes recommended models" do
      result = service.route_for_task(task_type: "classification")
      expect(result[:recommended_models]).to eq(["gpt-4.1-nano"])
    end

    it "defaults unknown task types to standard tier" do
      result = service.route_for_task(task_type: "unknown_task")
      expect(result[:model_tier]).to eq("standard")
    end

    it "passes model_tier and task_type to route" do
      expect(service).to receive(:route).with(hash_including(model_tier: "premium", task_type: "reasoning"))
      service.route_for_task(task_type: "reasoning")
    end
  end

  describe "#client_for_routing" do
    let(:service) { described_class.new(account: account) }

    it "builds WorkerLlmClient from routing result" do
      credential # ensure exists
      routing = { provider: provider }
      client = service.client_for_routing(routing)
      expect(client).to be_a(WorkerLlmClient)
    end

    it "raises when no credentials available" do
      routing = { provider: provider }
      expect { service.client_for_routing(routing) }
        .to raise_error(Ai::ModelRouterService::RoutingError, /No active credentials/)
    end
  end

  describe "#route_and_build_client" do
    let(:service) { described_class.new(account: account) }

    before do
      credential # ensure exists
      allow(service).to receive(:route_for_task).and_return({
        provider: provider,
        model_tier: "economy",
        recommended_models: ["gpt-4.1-nano"],
        decision_id: "test-id",
        strategy_used: "cost_optimized",
        scoring: {},
        estimated_cost: 0.001,
        estimated_latency_ms: 500
      })
    end

    it "returns client, model, and routing" do
      result = service.route_and_build_client(task_type: "classification")
      expect(result[:client]).to be_a(WorkerLlmClient)
      expect(result[:model]).to eq("gpt-4.1-nano")
      expect(result[:routing][:model_tier]).to eq("economy")
    end
  end

  describe "#select_optimal_provider strategy direction" do
    # Regression: cost_optimized/latency_optimized used min_by on cost_score/latency_score,
    # but those are 1/(1+x) (cheaper/faster => HIGHER score), so min_by deterministically
    # selected the MOST expensive / SLOWEST provider — the opposite of intent.
    let(:cheap_fast) { create(:ai_provider, account: account, provider_type: "openai", api_base_url: "https://api.openai.com/v1") }
    let(:pricey_slow) { create(:ai_provider, account: account, provider_type: "anthropic", api_base_url: "https://api.anthropic.com") }
    let(:providers) { [pricey_slow, cheap_fast] } # order should not matter

    def select_with(strategy)
      svc = described_class.new(account: account, strategy: strategy)
      allow(svc).to receive(:get_provider_cost_per_1k) { |p| p.id == cheap_fast.id ? 0.001 : 0.10 }
      allow(svc).to receive(:get_provider_avg_latency) { |p| p.id == cheap_fast.id ? 100.0 : 2000.0 }
      allow(svc).to receive(:get_provider_success_rate).and_return(100.0)
      provider, = svc.send(:select_optimal_provider, providers: providers, request_context: {}, matching_rules: [])
      provider
    end

    it "cost_optimized selects the cheaper provider" do
      expect(select_with("cost_optimized")).to eq(cheap_fast)
    end

    it "latency_optimized selects the faster provider" do
      expect(select_with("latency_optimized")).to eq(cheap_fast)
    end

    it "quality_optimized still selects the higher-success provider" do
      svc = described_class.new(account: account, strategy: "quality_optimized")
      allow(svc).to receive(:get_provider_cost_per_1k).and_return(0.002)
      allow(svc).to receive(:get_provider_avg_latency).and_return(1000.0)
      allow(svc).to receive(:get_provider_success_rate) { |p| p.id == cheap_fast.id ? 99.0 : 50.0 }
      provider, = svc.send(:select_optimal_provider, providers: providers, request_context: {}, matching_rules: [])
      expect(provider).to eq(cheap_fast)
    end
  end
end
