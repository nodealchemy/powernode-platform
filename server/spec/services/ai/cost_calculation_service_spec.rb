# frozen_string_literal: true

require "rails_helper"

# Cache reads and writes are subsets of prompt_tokens (the Ai::Llm::Response
# usage invariant). Reads are priced at the catalog's cached_input rate and
# writes at its cache_write rate; an unmodelled (0) rate is the input rate.
RSpec.describe Ai::CostCalculationService do
  def price(**rates)
    Ai::ModelPricing.create!(model_id: "cost-spec-model", provider_type: "anthropic", source: "manual",
                             input_per_1k: 3.0, output_per_1k: 15.0, **rates)
  end

  it "prices uncached input, cache reads and cache writes at their own rates" do
    price(cached_input_per_1k: 0.3, cache_write_per_1k: 3.75)

    cost = described_class.calculate(model_id: "cost-spec-model", prompt_tokens: 1500, completion_tokens: 100,
                                     cached_tokens: 400, cache_creation_tokens: 100)

    # uncached 1000 * 3.0 + 400 * 0.3 + 100 * 3.75, per 1K; output 100 * 15.0
    expect(cost).to be_within(1e-9).of(3.0 + 0.12 + 0.375 + 1.5)
  end

  it "prices writes at the input rate when the catalog models no write rate" do
    price(cached_input_per_1k: 0.3)

    cost = described_class.calculate(model_id: "cost-spec-model", prompt_tokens: 1000, cache_creation_tokens: 1000)

    expect(cost).to be_within(1e-9).of(3.0)
  end

  it "is unchanged for a call without cache writes" do
    price(cached_input_per_1k: 0.3)

    cost = described_class.calculate(model_id: "cost-spec-model", prompt_tokens: 1000, cached_tokens: 400)

    expect(cost).to be_within(1e-9).of(0.6 * 3.0 + 0.4 * 0.3)
  end

  it "exposes the write rate on the pricing hash" do
    expect(price(cache_write_per_1k: 3.75).pricing_hash["cache_write"]).to eq(3.75)
  end
end
