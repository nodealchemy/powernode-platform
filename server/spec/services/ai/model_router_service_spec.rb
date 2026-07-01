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

  describe "#models_for_tier (empty-models fallback)" do
    let(:service) { described_class.new(account: account) }

    it "returns a non-empty default when the provider has no models" do
      empty_provider = create(
        :ai_provider,
        account: account,
        provider_type: "openai",
        is_active: false,
        supported_models: []
      )

      result = service.send(:models_for_tier, "standard", empty_provider)

      expect(result).not_to be_empty
      expect(result.compact).to eq(result), "expected no nil model ids in #{result.inspect}"
    end

    it "still resolves tier-matched models when the provider has models" do
      stocked_provider = create(:ai_provider, :openai, account: account)

      result = service.send(:models_for_tier, "premium", stocked_provider)

      expect(result).not_to be_empty
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

    it "carries each candidate's estimated dollar cost (for savings analytics)" do
      svc = described_class.new(account: account, strategy: "cost_optimized")
      allow(svc).to receive(:get_provider_cost_per_1k) { |p| p.id == cheap_fast.id ? 0.001 : 0.10 }
      allow(svc).to receive(:get_provider_avg_latency).and_return(1000.0)
      allow(svc).to receive(:get_provider_success_rate).and_return(100.0)

      _, scoring = svc.send(:select_optimal_provider, providers: providers, request_context: {}, matching_rules: [])

      expect(scoring[:candidates]).to all(include(:estimated_cost))
    end
  end

  describe "#calculate_alternative_cost" do
    subject(:service) { described_class.new(account: account) }

    # Regression: returned the max routing SCORE (0–1) as alternative_cost_usd, which
    # RoutingDecision#record_outcome! then subtracts from a real dollar cost
    # (savings_usd = alternative_cost_usd - cost_usd) → fabricated dollar savings.
    it "returns the most expensive alternative's estimated dollar cost, not the routing score" do
      candidates = [
        { provider_id: "selected", score: 0.95, estimated_cost: 0.002 },
        { provider_id: "alt-1",    score: 0.80, estimated_cost: 0.05 },
        { provider_id: "alt-2",    score: 0.70, estimated_cost: 0.03 }
      ]

      result = service.send(:calculate_alternative_cost, candidates, "selected")

      expect(result).to eq(0.05) # max estimated_cost of the alternatives (a dollar amount)
    end

    it "returns nil when there are no alternatives" do
      candidates = [{ provider_id: "selected", score: 0.9, estimated_cost: 0.01 }]
      expect(service.send(:calculate_alternative_cost, candidates, "selected")).to be_nil
    end
  end

  describe "#models_for_tier Fable candidacy gate" do
    subject(:router) { described_class.new(account: account) }

    before { allow(provider).to receive(:available_models).and_return(%w[claude-opus-4-8 claude-fable-5]) }

    it "excludes Fable from the premium tier when the framework is OFF (default)" do
      models = router.send(:models_for_tier, "premium", provider)

      expect(models).to include("claude-opus-4-8")
      expect(models).not_to include("claude-fable-5")
    end

    it "includes Fable in the premium tier when the framework is ON" do
      account.update!(settings: { "fable_routing_enabled" => true })
      models = router.send(:models_for_tier, "premium", provider)

      expect(models).to include("claude-fable-5")
    end
  end
end
