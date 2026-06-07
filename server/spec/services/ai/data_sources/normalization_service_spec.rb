# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::NormalizationService, type: :service do
  # `apply` returns [normalized_records, provenance]. Provenance is an array of
  # per-conversion hashes: { record_index:, field:, type:, from:, to:, ... }.

  describe "date / time normalization (UTC ISO-8601)" do
    it "coerces a Time value to UTC ISO-8601 and records provenance" do
      # 2024-01-02 12:00:00 in a +05:00 zone => 07:00:00Z
      t = Time.new(2024, 1, 2, 12, 0, 0, "+05:00")
      service = described_class.new("dates" => { "fields" => ["observed_at"] })

      normalized, provenance = service.apply([{ "observed_at" => t }])

      expect(normalized.first["observed_at"]).to eq("2024-01-02T07:00:00Z")

      entry = provenance.find { |p| p[:field] == "observed_at" }
      expect(entry[:type]).to eq("date")
      expect(entry[:to]).to eq("2024-01-02T07:00:00Z")
    end

    it "parses a declared date-field string with an explicit offset to UTC" do
      service = described_class.new("dates" => { "fields" => ["published"] })

      normalized, _provenance = service.apply([{ "published" => "2024-03-04T10:00:00+02:00" }])

      expect(normalized.first["published"]).to eq("2024-03-04T08:00:00Z")
    end

    it "interprets a naive date string in the configured assume_zone before converting to UTC" do
      service = described_class.new(
        "dates" => { "fields" => ["ts"], "assume_zone" => "America/New_York" }
      )

      # 2024-07-01 12:00 EDT (-04:00) => 16:00:00Z
      normalized, _provenance = service.apply([{ "ts" => "2024-07-01 12:00:00" }])

      expect(normalized.first["ts"]).to eq("2024-07-01T16:00:00Z")
    end

    it "infers ISO-ish date strings even without an explicit date rule (infer_dates default on)" do
      # An ISO-ish string with an explicit offset is recognized by inference and
      # coerced to UTC. Using an offset (rather than an already-canonical "...Z")
      # makes the coercion a real value change, so a provenance entry is emitted
      # — consistent with the no-op contract (an unchanged value records nothing,
      # see the NFC and infer_dates:false cases).
      normalized, provenance = described_class.new.apply([{ "when" => "2024-05-06T05:00:00+05:00" }])

      expect(normalized.first["when"]).to eq("2024-05-06T00:00:00Z")
      expect(provenance.any? { |p| p[:field] == "when" && p[:type] == "date" }).to be(true)
    end

    it "does not coerce arbitrary non-date strings" do
      normalized, _provenance = described_class.new.apply([{ "note" => "hello world" }])

      expect(normalized.first["note"]).to eq("hello world")
    end

    it "leaves date strings untouched when infer_dates is disabled and no date rule applies" do
      service = described_class.new("infer_dates" => false)

      normalized, provenance = service.apply([{ "when" => "2024-05-06T00:00:00Z" }])

      expect(normalized.first["when"]).to eq("2024-05-06T00:00:00Z")
      expect(provenance.any? { |p| p[:field] == "when" && p[:type] == "date" }).to be(false)
    end
  end

  describe "Unicode NFC normalization" do
    it "normalizes a decomposed string to NFC and records provenance" do
      decomposed = "é" # e + combining acute accent
      composed   = "é"  # é

      normalized, provenance = described_class.new.apply([{ "city" => decomposed }])

      expect(normalized.first["city"]).to eq(composed)
      expect(normalized.first["city"].unicode_normalize(:nfc)).to eq(normalized.first["city"])

      entry = provenance.find { |p| p[:field] == "city" }
      expect(entry[:type]).to eq("unicode_nfc")
      expect(entry[:to]).to eq(composed)
    end

    it "does not record provenance for already-NFC strings" do
      _normalized, provenance = described_class.new.apply([{ "city" => "NYC" }])

      expect(provenance.any? { |p| p[:type] == "unicode_nfc" }).to be(false)
    end

    it "skips fields listed under strings.exclude" do
      decomposed = "é"
      service = described_class.new("strings" => { "exclude" => ["raw_blob"] })

      normalized, provenance = service.apply([{ "raw_blob" => decomposed }])

      expect(normalized.first["raw_blob"]).to eq(decomposed)
      expect(provenance.any? { |p| p[:field] == "raw_blob" }).to be(false)
    end

    it "respects normalize_all: false to opt out of NFC entirely" do
      decomposed = "é"
      service = described_class.new("strings" => { "normalize_all" => false })

      normalized, _provenance = service.apply([{ "city" => decomposed }])

      expect(normalized.first["city"]).to eq(decomposed)
    end
  end

  describe "ISO-4217 currency normalization (money gem)" do
    it "normalizes a numeric value with a fixed currency to a canonical money hash" do
      service = described_class.new(
        "currency" => { "fields" => { "price" => { "currency" => "USD" } } }
      )

      normalized, provenance = service.apply([{ "price" => 1234.5 }])

      money = normalized.first["price"]
      expect(money["currency"]).to eq("USD")
      expect(money["amount"]).to eq("1234.50")
      expect(money["minor_units"]).to eq(123_450)

      entry = provenance.find { |p| p[:field] == "price" && p[:type] == "currency" }
      expect(entry[:currency]).to eq("USD")
    end

    it "resolves the currency from a sibling field" do
      service = described_class.new(
        "currency" => { "fields" => { "price" => { "currency_field" => "ccy" } } }
      )

      normalized, _provenance = service.apply([{ "price" => 10, "ccy" => "eur" }])

      money = normalized.first["price"]
      expect(money["currency"]).to eq("EUR")
      expect(money["amount"]).to eq("10.00")
    end

    it "uses the currency's natural precision (0 decimals for JPY)" do
      service = described_class.new(
        "currency" => { "fields" => { "price" => { "currency" => "JPY" } } }
      )

      normalized, _provenance = service.apply([{ "price" => 500 }])

      money = normalized.first["price"]
      expect(money["currency"]).to eq("JPY")
      expect(money["amount"]).to eq("500")
      expect(money["minor_units"]).to eq(500)
    end

    it "leaves the value unchanged and notes when the currency is not ISO-4217" do
      service = described_class.new(
        "currency" => { "fields" => { "price" => { "currency" => "ZZZ" } } }
      )

      normalized, provenance = service.apply([{ "price" => 10 }])

      expect(normalized.first["price"]).to eq(10)
      entry = provenance.find { |p| p[:field] == "price" && p[:type] == "currency" }
      expect(entry[:note]).to match(/not ISO-4217/)
    end

    it "strips currency symbols/separators from string amounts" do
      service = described_class.new(
        "currency" => { "fields" => { "price" => { "currency" => "USD" } } }
      )

      normalized, _provenance = service.apply([{ "price" => "$1,234.50" }])

      money = normalized.first["price"]
      expect(money["amount"]).to eq("1234.50")
      expect(money["minor_units"]).to eq(123_450)
    end

    it "leaves a non-numeric amount unchanged" do
      service = described_class.new(
        "currency" => { "fields" => { "price" => { "currency" => "USD" } } }
      )

      normalized, provenance = service.apply([{ "price" => "n/a" }])

      expect(normalized.first["price"]).to eq("n/a")
      entry = provenance.find { |p| p[:field] == "price" && p[:type] == "currency" }
      expect(entry[:note]).to match(/non-numeric/)
    end
  end

  describe "provenance log" do
    it "returns an empty result and empty provenance for blank input" do
      normalized, provenance = described_class.new.apply([])

      expect(normalized).to eq([])
      expect(provenance).to eq([])
    end

    it "passes non-Hash records through untouched but notes them" do
      normalized, provenance = described_class.new.apply(["plain string"])

      expect(normalized).to eq(["plain string"])
      entry = provenance.find { |p| p[:type] == "skipped" }
      expect(entry).not_to be_nil
      expect(entry[:record_index]).to eq(0)
    end

    it "tags provenance entries with the correct record_index across multiple records" do
      service = described_class.new("dates" => { "fields" => ["ts"] })

      _normalized, provenance = service.apply(
        [
          { "ts" => Time.new(2024, 1, 1, 0, 0, 0, "+01:00") },
          { "ts" => Time.new(2024, 1, 2, 0, 0, 0, "+01:00") }
        ]
      )

      indexes = provenance.select { |p| p[:field] == "ts" }.map { |p| p[:record_index] }
      expect(indexes).to contain_exactly(0, 1)
    end

    it "recurses into nested hashes for normalization" do
      decomposed = "é"
      normalized, provenance = described_class.new.apply(
        [{ "properties" => { "name" => decomposed } }]
      )

      expect(normalized.first["properties"]["name"]).to eq("é")
      entry = provenance.find { |p| p[:field] == "properties.name" }
      expect(entry[:type]).to eq("unicode_nfc")
    end

    it "normalizes string elements inside arrays" do
      decomposed = "é"
      normalized, _provenance = described_class.new.apply([{ "tags" => [decomposed, "ok"] }])

      expect(normalized.first["tags"]).to eq(["é", "ok"])
    end
  end
end
