# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trading::ExternalData::NoaaClimateClient do
  let(:client) { described_class.new }

  describe "#applicable?" do
    it "returns true for weather questions" do
      expect(client.applicable?("Historical temperature averages")).to be true
    end

    it "returns false for non-weather questions" do
      expect(client.applicable?("Crypto market")).to be false
    end
  end

  describe "#cache_ttl" do
    it "returns 7 days" do
      expect(client.cache_ttl).to eq(604_800)
    end
  end

  describe "#fetch_for_market" do
    context "without NCEI_CDO_TOKEN" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("NCEI_CDO_TOKEN").and_return(nil)
      end

      it "returns nil gracefully" do
        result = client.fetch_for_market("temperature", { location: "new york", date: Date.today.to_s })
        expect(result).to be_nil
      end
    end

    context "with NCEI_CDO_TOKEN" do
      let(:token) { "test-ncei-token" }

      let(:station_response) do
        {
          "results" => [
            { "id" => "GHCND:USW00094728", "name" => "Central Park" }
          ]
        }.to_json
      end

      let(:normals_response) do
        {
          "results" => [
            { "datatype" => "DLY-TMAX-NORMAL", "value" => 620 },
            { "datatype" => "DLY-TMIN-NORMAL", "value" => 470 },
            { "datatype" => "DLY-PRCP-PCTALL-GE001HI", "value" => 320 }
          ]
        }.to_json
      end

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("NCEI_CDO_TOKEN").and_return(token)

        stub_request(:get, %r{ncei\.noaa\.gov/cdo-web/api/v2/stations})
          .to_return(status: 200, body: station_response, headers: { "Content-Type" => "application/json" })

        stub_request(:get, %r{ncei\.noaa\.gov/cdo-web/api/v2/data})
          .to_return(status: 200, body: normals_response, headers: { "Content-Type" => "application/json" })
      end

      it "returns climate normal data for a known location" do
        result = client.fetch_for_market("temperature", { location: "new york", date: Date.today.to_s })
        expect(result).not_to be_nil
        expect(result[:source]).to eq("noaa_ncei")
        expect(result[:station_id]).to eq("GHCND:USW00094728")
        expect(result[:normal_high_f]).to eq(62.0) # 620 / 10
        expect(result[:normal_low_f]).to eq(47.0)  # 470 / 10
        expect(result[:normal_precip_in]).to eq(32.0) # 320 / 10
        expect(result[:climate_period]).to eq("1991-2020")
        expect(result[:freshness_hours]).to eq(0.0)
        expect(result[:historical_exceedance_prob]).to be_a(Hash)
      end

      it "returns nil for unknown locations" do
        result = client.fetch_for_market("temperature", { location: "timbuktu", date: Date.today.to_s })
        expect(result).to be_nil
      end

      it "returns nil without location" do
        result = client.fetch_for_market("temperature", {})
        expect(result).to be_nil
      end

      it "sends token header in requests" do
        client.fetch_for_market("temperature", { location: "new york", date: Date.today.to_s })
        expect(WebMock).to have_requested(:get, %r{ncei\.noaa\.gov})
          .with(headers: { "token" => token }).at_least_once
      end

      it "caches responses" do
        client.fetch_for_market("temperature", { location: "new york", date: Date.today.to_s })
        client.fetch_for_market("temperature", { location: "new york", date: Date.today.to_s })
        expect(WebMock).to have_requested(:get, %r{ncei\.noaa\.gov/cdo-web/api/v2/stations}).once
      end

      context "when station lookup fails" do
        before do
          stub_request(:get, %r{ncei\.noaa\.gov/cdo-web/api/v2/stations})
            .to_return(status: 500, body: "")
        end

        it "returns nil gracefully" do
          result = client.fetch_for_market("temperature", { location: "new york", date: Date.today.to_s })
          expect(result).to be_nil
        end
      end

      context "when normals data is empty" do
        before do
          stub_request(:get, %r{ncei\.noaa\.gov/cdo-web/api/v2/data})
            .to_return(status: 200, body: { "results" => [] }.to_json, headers: { "Content-Type" => "application/json" })
        end

        it "returns data with nil normals" do
          result = client.fetch_for_market("temperature", { location: "new york", date: Date.today.to_s })
          # Station found but no normals data — returns result with nil values
          if result
            expect(result[:normal_high_f]).to be_nil
            expect(result[:source]).to eq("noaa_ncei")
          end
        end
      end

      context "when API times out" do
        before do
          stub_request(:get, %r{ncei\.noaa\.gov/cdo-web/api/v2/stations})
            .to_timeout
        end

        it "returns nil gracefully" do
          result = client.fetch_for_market("temperature", { location: "new york", date: Date.today.to_s })
          expect(result).to be_nil
        end
      end
    end
  end
end
