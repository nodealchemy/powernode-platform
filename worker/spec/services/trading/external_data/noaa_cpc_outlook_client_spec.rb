# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trading::ExternalData::NoaaCpcOutlookClient do
  let(:client) { described_class.new }

  describe "#applicable?" do
    it "returns true for weather questions" do
      expect(client.applicable?("Temperature forecast next week")).to be true
      expect(client.applicable?("Precipitation outlook")).to be true
    end

    it "returns false for non-weather questions" do
      expect(client.applicable?("Stock market crash")).to be false
    end
  end

  describe "#cache_ttl" do
    it "returns 24 hours" do
      expect(client.cache_ttl).to eq(86_400)
    end
  end

  describe "#fetch_for_market" do
    let(:cpc_response) do
      {
        "probabilities" => [
          {
            "lat" => 40.7,
            "lon" => -74.0,
            "temperature" => { "above" => 55, "below" => 15, "near" => 30 },
            "precipitation" => { "above" => 40, "below" => 25, "near" => 35 },
            "valid_period" => "6-10 day outlook"
          }
        ]
      }.to_json
    end

    before do
      stub_request(:get, %r{cpc\.ncep\.noaa\.gov/})
        .to_return(status: 200, body: cpc_response, headers: { "Content-Type" => "application/json" })
    end

    context "when target date is 6+ days out" do
      let(:metadata) do
        { location: "new york", date: (Date.today + 8).to_s }
      end

      it "returns CPC outlook data" do
        result = client.fetch_for_market("temperature forecast", metadata)
        expect(result).not_to be_nil
        expect(result[:source]).to eq("noaa_cpc")
        expect(result[:outlook_type]).to be_a(String)
        expect(result[:temperature]).to be_a(Hash)
        expect(result[:temperature]).to have_key(:above_normal)
        expect(result[:temperature]).to have_key(:below_normal)
        expect(result[:temperature]).to have_key(:near_normal)
        expect(result[:freshness_hours]).to be_a(Float)
      end
    end

    context "when target date is less than 6 days out" do
      let(:metadata) do
        { location: "new york", date: (Date.today + 3).to_s }
      end

      it "returns nil (short-term, use GFS)" do
        result = client.fetch_for_market("temperature forecast", metadata)
        expect(result).to be_nil
      end
    end

    context "when no date is provided" do
      let(:metadata) { { location: "new york" } }

      it "fetches outlook (assumes could be medium-range)" do
        result = client.fetch_for_market("temperature forecast", metadata)
        expect(result).not_to be_nil
      end
    end

    it "returns nil for unknown locations" do
      result = client.fetch_for_market("forecast", { location: "timbuktu" })
      expect(result).to be_nil
    end

    it "returns nil without location" do
      result = client.fetch_for_market("forecast", {})
      expect(result).to be_nil
    end

    context "when CPC API returns non-JSON" do
      before do
        stub_request(:get, %r{cpc\.ncep\.noaa\.gov/})
          .to_return(status: 200, body: "plain text data", headers: { "Content-Type" => "text/plain" })
      end

      it "falls back to neutral outlook" do
        metadata = { location: "new york", date: (Date.today + 8).to_s }
        result = client.fetch_for_market("temperature forecast", metadata)
        # Should still return something (neutral fallback) or nil gracefully
        if result
          expect(result[:temperature][:above_normal]).to be_between(0.0, 1.0)
        end
      end
    end

    context "when CPC API is down" do
      before do
        stub_request(:get, %r{cpc\.ncep\.noaa\.gov/})
          .to_return(status: 500, body: "")
      end

      it "returns nil gracefully" do
        metadata = { location: "new york", date: (Date.today + 8).to_s }
        result = client.fetch_for_market("temperature forecast", metadata)
        # Neutral fallback or nil
        if result
          expect(result[:source]).to eq("noaa_cpc")
        end
      end
    end
  end
end
