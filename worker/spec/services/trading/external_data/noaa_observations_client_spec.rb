# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trading::ExternalData::NoaaObservationsClient do
  let(:client) { described_class.new }

  describe "#applicable?" do
    it "returns true for weather questions" do
      expect(client.applicable?("Will temperature exceed 90°F?")).to be true
      expect(client.applicable?("Rain in Seattle")).to be true
    end

    it "returns false for non-weather questions" do
      expect(client.applicable?("Bitcoin price prediction")).to be false
    end
  end

  describe "#cache_ttl" do
    it "returns 30 minutes" do
      expect(client.cache_ttl).to eq(1800)
    end
  end

  describe "#fetch_for_market" do
    let(:stations_response) do
      {
        "features" => [
          {
            "properties" => {
              "stationIdentifier" => "KJFK",
              "name" => "JFK Airport"
            }
          }
        ]
      }.to_json
    end

    let(:observation_response) do
      {
        "properties" => {
          "timestamp" => (Time.now - 1800).iso8601,
          "temperature" => { "value" => 28.5 },
          "windSpeed" => { "value" => 15.3 },
          "precipitationLastHour" => { "value" => 0.0 },
          "relativeHumidity" => { "value" => 65.0 },
          "textDescription" => "Partly Cloudy"
        }
      }.to_json
    end

    before do
      stub_request(:get, %r{api\.weather\.gov/points/.*/stations})
        .to_return(status: 200, body: stations_response, headers: { "Content-Type" => "application/json" })

      stub_request(:get, %r{api\.weather\.gov/stations/KJFK/observations/latest})
        .to_return(status: 200, body: observation_response, headers: { "Content-Type" => "application/json" })
    end

    it "returns observation data for a known location" do
      result = client.fetch_for_market("temperature NYC", { location: "new york" })
      expect(result).not_to be_nil
      expect(result[:station_id]).to eq("KJFK")
      expect(result[:observed_temperature_c]).to eq(28.5)
      expect(result[:observed_wind_speed_kmh]).to eq(15.3)
      expect(result[:observed_precip_mm]).to eq(0.0)
      expect(result[:observed_humidity_pct]).to eq(65.0)
      expect(result[:text_description]).to eq("Partly Cloudy")
      expect(result[:source]).to eq("noaa_observations")
      expect(result[:freshness_hours]).to be_a(Float)
    end

    it "returns nil for unknown locations" do
      result = client.fetch_for_market("temperature", { location: "timbuktu" })
      expect(result).to be_nil
    end

    it "returns nil without location metadata" do
      result = client.fetch_for_market("temperature somewhere", {})
      expect(result).to be_nil
    end

    it "caches responses within TTL" do
      client.fetch_for_market("temperature NYC", { location: "new york" })
      client.fetch_for_market("temperature NYC", { location: "new york" })
      expect(WebMock).to have_requested(:get, %r{api\.weather\.gov/points/}).once
    end

    context "when station lookup fails" do
      before do
        stub_request(:get, %r{api\.weather\.gov/points/.*/stations})
          .to_return(status: 500, body: "")
      end

      it "returns nil gracefully" do
        result = client.fetch_for_market("temperature NYC", { location: "new york" })
        expect(result).to be_nil
      end
    end

    context "when observation request fails" do
      before do
        stub_request(:get, %r{api\.weather\.gov/stations/KJFK/observations/latest})
          .to_return(status: 404, body: "")
      end

      it "returns nil gracefully" do
        result = client.fetch_for_market("temperature NYC", { location: "new york" })
        expect(result).to be_nil
      end
    end

    context "when API times out" do
      before do
        stub_request(:get, %r{api\.weather\.gov/points/.*/stations})
          .to_timeout
      end

      it "returns nil gracefully" do
        result = client.fetch_for_market("temperature NYC", { location: "new york" })
        expect(result).to be_nil
      end
    end
  end
end
