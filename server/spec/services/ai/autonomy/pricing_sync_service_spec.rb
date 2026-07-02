# frozen_string_literal: true

require "rails_helper"

# The stored ModelPricing#tier label must derive from the SAME price bands as
# Ai::ModelTiers (single source of truth for price -> tier). The 3-valued label
# vocabulary (economy/standard/premium) is preserved: :frontier folds into
# "premium" via Ai::ModelTiers.to_label, so no tier consumer breaks.
RSpec.describe Ai::Autonomy::PricingSyncService do
  describe ".classify_tier" do
    def classify(price)
      described_class.send(:classify_tier, price)
    end

    it "labels frontier-band prices (>= $0.008/1k in) as premium" do
      expect(classify(0.010)).to eq("premium")
      expect(classify(0.008)).to eq("premium")
    end

    it "labels reasoning-band prices (>= $0.004/1k in) as premium" do
      expect(classify(0.005)).to eq("premium")
      expect(classify(0.004)).to eq("premium")
    end

    it "labels standard-band prices (>= $0.0015/1k in) as standard" do
      expect(classify(0.003)).to eq("standard")
      expect(classify(0.002)).to eq("standard")
      expect(classify(0.0015)).to eq("standard")
    end

    it "labels below-band prices as economy" do
      expect(classify(0.001)).to eq("economy")
      expect(classify(0.0005)).to eq("economy")
      expect(classify(0.0)).to eq("economy")
    end

    it "agrees with the Ai::ModelTiers price-band ladder for every band edge" do
      edges = Ai::ModelTiers::PRICE_BANDS.flat_map { |threshold, _| [threshold, threshold - 0.0001] } + [0.0]
      edges.each do |price|
        expect(classify(price))
          .to eq(Ai::ModelTiers.to_label(Ai::ModelTiers.tier_for_price(price))),
              "classify_tier(#{price}) diverged from the ModelTiers price-band ladder"
      end
    end
  end

  describe ".sync! stored tier (litellm path)" do
    def litellm_payload(input_per_token)
      {
        "claude-opus-4-8" => {
          "input_cost_per_token" => input_per_token,
          "output_cost_per_token" => input_per_token * 5,
          "litellm_provider" => "anthropic"
        }
      }
    end

    it "persists the ModelTiers-derived tier label on the upserted pricing row" do
      allow(described_class).to receive(:fetch_litellm_pricing)
        .and_return(litellm_payload(0.000005)) # $0.005/1k in => reasoning band => "premium"
      allow(described_class).to receive(:propagate_to_providers)

      result = described_class.sync!

      expect(result[:source]).to eq("litellm")
      row = Ai::ModelPricing.find_by(model_id: "claude-opus-4-8")
      expect(row).to be_present
      expect(row.tier).to eq("premium")
    end

    it "persists standard for a standard-band price that the old thresholds called premium" do
      allow(described_class).to receive(:fetch_litellm_pricing)
        .and_return(litellm_payload(0.000003)) # $0.003/1k in => standard band (old ladder: premium)
      allow(described_class).to receive(:propagate_to_providers)

      described_class.sync!

      expect(Ai::ModelPricing.find_by(model_id: "claude-opus-4-8").tier).to eq("standard")
    end
  end
end
