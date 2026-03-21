# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trading::ExternalData::NoaaGfsClient do
  let(:client) { described_class.new }

  describe "#applicable?" do
    it "returns true for weather-related questions" do
      expect(client.applicable?("Will the temperature in NYC exceed 90°F?")).to be true
      expect(client.applicable?("Will there be rain in Chicago tomorrow?")).to be true
      expect(client.applicable?("Hurricane landfall probability")).to be true
    end

    it "returns false for non-weather questions" do
      expect(client.applicable?("Will Bitcoin hit $100k?")).to be false
      expect(client.applicable?("Election outcome")).to be false
    end
  end

  describe "#cache_ttl" do
    it "returns 6 hours" do
      expect(client.cache_ttl).to eq(21_600)
    end
  end

  describe "#fetch_for_market" do
    let(:raw_gridpoint_response) do
      {
        "properties" => {
          "updateTime" => (Time.now - 3600).iso8601,
          "maxTemperature" => {
            "uom" => "wmoUnit:degC",
            "values" => [
              { "validTime" => "#{Date.today}/PT12H", "value" => 32.0 },
              { "validTime" => "#{Date.today}/PT12H", "value" => 34.0 }
            ]
          },
          "temperature" => {
            "uom" => "wmoUnit:degC",
            "values" => [
              { "validTime" => "#{Date.today}/PT1H", "value" => 28.0 },
              { "validTime" => "#{Date.today}/PT1H", "value" => 30.0 },
              { "validTime" => "#{Date.today}/PT1H", "value" => 32.0 }
            ]
          },
          "probabilityOfPrecipitation" => {
            "values" => [
              { "validTime" => "#{Date.today}/PT1H", "value" => 40 },
              { "validTime" => "#{Date.today}/PT1H", "value" => 60 }
            ]
          },
          "windSpeed" => {
            "uom" => "wmoUnit:km_h-1",
            "values" => [
              { "validTime" => "#{Date.today}/PT1H", "value" => 15.0 },
              { "validTime" => "#{Date.today}/PT1H", "value" => 25.0 }
            ]
          }
        }
      }.to_json
    end

    before do
      stub_request(:get, %r{api\.weather\.gov/gridpoints/})
        .to_return(status: 200, body: raw_gridpoint_response, headers: { "Content-Type" => "application/json" })
    end

    it "returns forecast data for a known location" do
      result = client.fetch_for_market("temperature NYC", { location: "new york" })
      expect(result).not_to be_nil
      expect(result[:model]).to eq("GFS")
      expect(result[:location]).to eq("new york")
      expect(result[:forecast]).to be_a(Hash)
      expect(result[:grid_point]).to eq({ office: "OKX", x: 33, y: 37 })
    end

    it "returns nil for unknown locations" do
      result = client.fetch_for_market("temperature Timbuktu", { location: "timbuktu" })
      expect(result).to be_nil
    end

    it "returns nil when location is missing" do
      result = client.fetch_for_market("temperature somewhere", {})
      expect(result).to be_nil
    end

    it "caches responses" do
      client.fetch_for_market("temperature NYC", { location: "nyc" })
      client.fetch_for_market("temperature NYC", { location: "nyc" })
      expect(WebMock).to have_requested(:get, %r{api\.weather\.gov/gridpoints/}).once
    end

    context "when API returns an error" do
      before do
        stub_request(:get, %r{api\.weather\.gov/gridpoints/})
          .to_return(status: 500, body: "Internal Server Error")
      end

      it "returns nil gracefully" do
        result = client.fetch_for_market("temperature NYC", { location: "new york" })
        expect(result).to be_nil
      end
    end

    context "when API times out" do
      before do
        stub_request(:get, %r{api\.weather\.gov/gridpoints/})
          .to_timeout
      end

      it "returns nil gracefully" do
        result = client.fetch_for_market("temperature NYC", { location: "new york" })
        expect(result).to be_nil
      end
    end
  end

  describe "#calculate_probability" do
    let(:forecast_data) do
      {
        forecast: {
          "properties" => {
            "maxTemperature" => {
              "uom" => "wmoUnit:degC",
              "values" => [
                { "validTime" => "#{Date.today}/PT12H", "value" => 30.0 },
                { "validTime" => "#{Date.today}/PT12H", "value" => 32.0 },
                { "validTime" => "#{Date.today}/PT12H", "value" => 35.0 },
                { "validTime" => "#{Date.today}/PT12H", "value" => 28.0 }
              ]
            },
            "probabilityOfPrecipitation" => {
              "values" => [
                { "validTime" => "#{Date.today}/PT1H", "value" => 20 },
                { "validTime" => "#{Date.today}/PT1H", "value" => 40 },
                { "validTime" => "#{Date.today}/PT1H", "value" => 80 },
                { "validTime" => "#{Date.today}/PT1H", "value" => 60 }
              ]
            },
            "windSpeed" => {
              "uom" => "wmoUnit:km_h-1",
              "values" => [
                { "validTime" => "#{Date.today}/PT1H", "value" => 10.0 },
                { "validTime" => "#{Date.today}/PT1H", "value" => 20.0 },
                { "validTime" => "#{Date.today}/PT1H", "value" => 30.0 },
                { "validTime" => "#{Date.today}/PT1H", "value" => 40.0 }
              ]
            }
          }
        }
      }
    end

    context "temperature metric" do
      it "calculates fraction of periods exceeding threshold" do
        # 30°C = 86°F, threshold 85°F → 3 of 4 exceed (30, 32, 35 all >= ~29.4°C)
        prob = client.calculate_probability(forecast_data, metric: "high_temperature", threshold: 85, unit: "F")
        expect(prob).to be_a(Float)
        expect(prob).to be_between(0.0, 1.0)
      end

      it "returns nil for nil forecast data" do
        prob = client.calculate_probability(nil, metric: "temperature", threshold: 90, unit: "F")
        expect(prob).to be_nil
      end
    end

    context "precipitation metric" do
      it "returns average precipitation probability as fraction" do
        prob = client.calculate_probability(forecast_data, metric: "precipitation", threshold: 0, unit: "inches")
        expect(prob).to be_a(Float)
        # Average of 20, 40, 80, 60 = 50 → 0.5
        expect(prob).to eq(0.5)
      end
    end

    context "wind speed metric" do
      it "calculates fraction exceeding wind threshold" do
        # Values are 10, 20, 30, 40 km/h. Threshold 15 mph = ~24.1 km/h → 2 of 4 exceed
        prob = client.calculate_probability(forecast_data, metric: "wind_speed", threshold: 15, unit: "mph")
        expect(prob).to be_a(Float)
        expect(prob).to eq(0.5)
      end
    end

    context "unknown metric" do
      it "returns nil" do
        prob = client.calculate_probability(forecast_data, metric: "humidity", threshold: 80, unit: "%")
        expect(prob).to be_nil
      end
    end
  end
end
