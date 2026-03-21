# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::StrategyEvaluator do
  subject(:evaluator) { described_class.new }

  describe "#evict" do
    it "removes the correct evaluator from cache" do
      evaluator.evaluator_cache["abc123_momentum"] = double("evaluator")
      evaluator.evaluator_cache["def456_arbitrage"] = double("evaluator")

      evaluator.evict("abc123")

      expect(evaluator.evaluator_cache.keys).to eq(["def456_arbitrage"])
    end

    it "is a no-op when strategy_id not in cache" do
      evaluator.evaluator_cache["abc_momentum"] = double("evaluator")

      expect { evaluator.evict("nonexistent") }.not_to change { evaluator.evaluator_cache.size }
    end
  end

  describe "#prune_cache!" do
    it "removes all evaluators not in the active set" do
      evaluator.evaluator_cache["aaa_momentum"] = double("evaluator")
      evaluator.evaluator_cache["bbb_arbitrage"] = double("evaluator")
      evaluator.evaluator_cache["ccc_sentiment"] = double("evaluator")

      evaluator.prune_cache!(["aaa", "ccc"])

      expect(evaluator.evaluator_cache.keys).to contain_exactly("aaa_momentum", "ccc_sentiment")
    end

    it "handles string and non-string IDs in active set" do
      evaluator.evaluator_cache["123_momentum"] = double("evaluator")
      evaluator.evaluator_cache["456_arbitrage"] = double("evaluator")

      evaluator.prune_cache!([123, 456])

      expect(evaluator.evaluator_cache.size).to eq(2)
    end

    it "clears entire cache when active set is empty" do
      evaluator.evaluator_cache["aaa_momentum"] = double("evaluator")

      evaluator.prune_cache!([])

      expect(evaluator.evaluator_cache).to be_empty
    end
  end
end
