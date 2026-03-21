# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trading::ExternalData::NoaaGeoResolver do
  describe ".normalize_location" do
    it "downcases and strips whitespace" do
      expect(described_class.normalize_location("  New York  ")).to eq("new york")
    end

    it "resolves common aliases" do
      expect(described_class.normalize_location("nyc")).to eq("new york")
      expect(described_class.normalize_location("NYC")).to eq("new york")
      expect(described_class.normalize_location("la")).to eq("los angeles")
      expect(described_class.normalize_location("sf")).to eq("san francisco")
      expect(described_class.normalize_location("dc")).to eq("washington")
      expect(described_class.normalize_location("d.c.")).to eq("washington")
      expect(described_class.normalize_location("washington dc")).to eq("washington")
    end

    it "returns the original normalized string for unknown locations" do
      expect(described_class.normalize_location("Tallahassee")).to eq("tallahassee")
    end
  end

  describe ".resolve_coordinates" do
    it "returns lat/lon for known cities" do
      result = described_class.resolve_coordinates("new york")
      expect(result).to eq({ lat: 40.7128, lon: -74.0060 })
    end

    it "resolves aliases to coordinates" do
      result = described_class.resolve_coordinates("nyc")
      expect(result).to eq({ lat: 40.7128, lon: -74.0060 })
    end

    it "returns nil for unknown locations" do
      result = described_class.resolve_coordinates("timbuktu")
      expect(result).to be_nil
    end
  end

  describe ".resolve_grid_point" do
    it "returns office/x/y for known cities" do
      result = described_class.resolve_grid_point("chicago")
      expect(result).to eq({ office: "LOT", x: 65, y: 76 })
    end

    it "resolves aliases to grid points" do
      result = described_class.resolve_grid_point("sf")
      expect(result).to eq({ office: "MTR", x: 85, y: 105 })
    end

    it "returns nil for unknown locations" do
      result = described_class.resolve_grid_point("unknown city")
      expect(result).to be_nil
    end
  end

  describe ".known_location?" do
    it "returns true for known cities" do
      expect(described_class.known_location?("denver")).to be true
    end

    it "returns true for aliases" do
      expect(described_class.known_location?("nyc")).to be true
    end

    it "returns false for unknown cities" do
      expect(described_class.known_location?("juneau")).to be false
    end
  end

  describe ".fips_code" do
    it "returns FIPS code for known cities" do
      expect(described_class.fips_code("new york")).to eq("36061")
      expect(described_class.fips_code("los angeles")).to eq("06037")
    end

    it "resolves aliases" do
      expect(described_class.fips_code("nyc")).to eq("36061")
    end

    it "returns nil for unknown cities" do
      expect(described_class.fips_code("unknown")).to be_nil
    end
  end

  describe "CITY_COORDINATES" do
    it "has at least 16 cities" do
      expect(described_class::CITY_COORDINATES.size).to be >= 16
    end

    it "has complete data for every city" do
      described_class::CITY_COORDINATES.each do |city, data|
        expect(data).to have_key(:lat), "#{city} missing lat"
        expect(data).to have_key(:lon), "#{city} missing lon"
        expect(data).to have_key(:office), "#{city} missing office"
        expect(data).to have_key(:x), "#{city} missing x"
        expect(data).to have_key(:y), "#{city} missing y"
        expect(data).to have_key(:fips), "#{city} missing fips"
      end
    end
  end
end
