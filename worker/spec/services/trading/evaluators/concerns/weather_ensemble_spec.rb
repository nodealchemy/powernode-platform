# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trading::Evaluators::Concerns::WeatherEnsemble do
  let(:test_class) do
    Class.new(Trading::Evaluators::Base) do
      include Trading::Evaluators::Concerns::WeatherEnsemble
    end
  end

  let(:params) { {} }
  let(:base_context) do
    {
      "strategy" => { "id" => "s1", "pair" => "WEATHER-YES", "parameters" => params },
      "market_data" => { "last_price" => 0.50, "bid" => 0.49, "ask" => 0.51, "volume_24h" => 1000 },
      "positions" => [],
      "allocated_capital" => 1000.0
    }
  end

  let(:evaluator) { test_class.new(base_context) }

  describe "#blend_weather_sources" do
    context "with a single source" do
      it "returns the source probability unchanged" do
        sources = [
          { source: "noaa_gfs", probability: 0.70, confidence: 0.9, freshness_hours: 2.0 }
        ]
        result = evaluator.blend_weather_sources(sources)
        expect(result[:blended_probability]).to eq(0.70)
        expect(result[:source_count]).to eq(1)
      end
    end

    context "with two agreeing sources" do
      it "blends probabilities with corroboration bonus" do
        sources = [
          { source: "noaa_gfs", probability: 0.72, confidence: 0.9, freshness_hours: 2.0 },
          { source: "noaa_observations", probability: 0.74, confidence: 0.7, freshness_hours: 0.5 }
        ]
        result = evaluator.blend_weather_sources(sources)
        expect(result[:blended_probability]).to be_between(0.70, 0.80)
        expect(result[:source_count]).to eq(2)
        expect(result[:source_details].size).to eq(2)
      end
    end

    context "with disagreeing sources" do
      it "applies disagreement penalty pulling toward 0.5" do
        sources = [
          { source: "noaa_gfs", probability: 0.80, confidence: 0.9, freshness_hours: 2.0 },
          { source: "noaa_observations", probability: 0.40, confidence: 0.7, freshness_hours: 0.5 }
        ]
        result = evaluator.blend_weather_sources(sources)
        # Disagreement pulls toward 0.5
        expect(result[:blended_probability]).to be_between(0.45, 0.75)
        expect(result[:spread]).to be > 0.15
      end
    end

    context "with multiple sources including stale data" do
      it "reduces weight for stale sources" do
        sources = [
          { source: "noaa_gfs", probability: 0.80, confidence: 0.9, freshness_hours: 1.0 },
          { source: "noaa_observations", probability: 0.75, confidence: 0.8, freshness_hours: 0.5 },
          { source: "noaa_cpc", probability: 0.60, confidence: 0.7, freshness_hours: 24.0 }, # very stale
          { source: "noaa_ncei", probability: 0.50, confidence: 0.6, freshness_hours: 0.0 }
        ]
        result = evaluator.blend_weather_sources(sources)
        expect(result[:source_count]).to eq(4)
        # Fresh GFS+observations should dominate over stale CPC
        expect(result[:blended_probability]).to be > 0.55
      end
    end

    context "with empty sources" do
      it "returns nil" do
        result = evaluator.blend_weather_sources([])
        expect(result).to be_nil
      end
    end

    context "with invalid probabilities" do
      it "filters out sources with nil probability" do
        sources = [
          { source: "noaa_gfs", probability: 0.70, confidence: 0.9, freshness_hours: 2.0 },
          { source: "noaa_observations", probability: nil, confidence: 0.7, freshness_hours: 0.5 }
        ]
        result = evaluator.blend_weather_sources(sources)
        expect(result[:source_count]).to eq(1)
        expect(result[:blended_probability]).to eq(0.70)
      end

      it "filters out sources with out-of-range probability" do
        sources = [
          { source: "noaa_gfs", probability: 0.70, confidence: 0.9, freshness_hours: 2.0 },
          { source: "noaa_observations", probability: 1.5, confidence: 0.7, freshness_hours: 0.5 }
        ]
        result = evaluator.blend_weather_sources(sources)
        expect(result[:source_count]).to eq(1)
      end
    end

    context "output clamping" do
      it "clamps blended probability to [0.01, 0.99]" do
        # All sources agree on very high probability
        sources = [
          { source: "noaa_gfs", probability: 0.99, confidence: 1.0, freshness_hours: 0.0 },
          { source: "noaa_observations", probability: 0.98, confidence: 1.0, freshness_hours: 0.0 }
        ]
        result = evaluator.blend_weather_sources(sources)
        expect(result[:blended_probability]).to be <= 0.99

        # All sources agree on very low probability
        sources_low = [
          { source: "noaa_gfs", probability: 0.01, confidence: 1.0, freshness_hours: 0.0 },
          { source: "noaa_observations", probability: 0.02, confidence: 1.0, freshness_hours: 0.0 }
        ]
        result_low = evaluator.blend_weather_sources(sources_low)
        expect(result_low[:blended_probability]).to be >= 0.01
      end
    end

    context "with custom weight overrides" do
      let(:params) do
        { "weather_source_weights" => { "noaa_gfs" => 0.5, "noaa_observations" => 2.0 } }
      end

      it "applies custom weights" do
        sources = [
          { source: "noaa_gfs", probability: 0.40, confidence: 0.9, freshness_hours: 2.0 },
          { source: "noaa_observations", probability: 0.80, confidence: 0.9, freshness_hours: 0.5 }
        ]
        result = evaluator.blend_weather_sources(sources)
        # Observations have 4x the base weight of GFS → blend should be closer to 0.80
        expect(result[:blended_probability]).to be > 0.60
      end
    end

    context "source_details structure" do
      it "includes source, probability, weight, and freshness for each source" do
        sources = [
          { source: "noaa_gfs", probability: 0.70, confidence: 0.9, freshness_hours: 2.0 },
          { source: "noaa_ncei", probability: 0.65, confidence: 0.6, freshness_hours: 0.0 }
        ]
        result = evaluator.blend_weather_sources(sources)

        result[:source_details].each do |detail|
          expect(detail).to have_key(:source)
          expect(detail).to have_key(:probability)
          expect(detail).to have_key(:weight)
          expect(detail).to have_key(:freshness_hours)
          expect(detail[:weight]).to be_between(0.0, 1.0)
        end

        # Weights should sum to ~1.0
        total_weight = result[:source_details].sum { |d| d[:weight] }
        expect(total_weight).to be_within(0.01).of(1.0)
      end
    end
  end
end
