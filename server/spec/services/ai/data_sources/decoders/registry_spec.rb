# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Decoders::Registry do
  describe ".for format selection" do
    it "selects the JSON decoder for the json format token" do
      expect(described_class.for(format: "json")).to be_a(Ai::DataSources::Decoders::Json)
    end

    it "selects the NDJSON decoder for the ndjson format token" do
      expect(described_class.for(format: "ndjson")).to be_a(Ai::DataSources::Decoders::Ndjson)
    end

    it "selects the XML decoder for the xml format token" do
      expect(described_class.for(format: "xml")).to be_a(Ai::DataSources::Decoders::Xml)
    end

    it "selects the CSV decoder for the csv format token" do
      expect(described_class.for(format: "csv")).to be_a(Ai::DataSources::Decoders::Csv)
    end

    it "routes rss / atom / html formats to the XML decoder" do
      expect(described_class.for(format: "rss")).to be_a(Ai::DataSources::Decoders::Xml)
      expect(described_class.for(format: "atom")).to be_a(Ai::DataSources::Decoders::Xml)
      expect(described_class.for(format: "html")).to be_a(Ai::DataSources::Decoders::Xml)
    end

    it "normalises case and surrounding whitespace on the format token" do
      expect(described_class.for(format: "  JSON ")).to be_a(Ai::DataSources::Decoders::Json)
      expect(described_class.for(format: "CSV")).to be_a(Ai::DataSources::Decoders::Csv)
    end
  end

  describe ".for content-type probe (when format is absent)" do
    it "selects a decoder from the content type when no format is given" do
      expect(described_class.for(content_type: "text/csv")).to be_a(Ai::DataSources::Decoders::Csv)
      expect(described_class.for(content_type: "application/xml; charset=utf-8")).to be_a(Ai::DataSources::Decoders::Xml)
      expect(described_class.for(content_type: "application/x-ndjson")).to be_a(Ai::DataSources::Decoders::Ndjson)
    end

    it "honours structured +json / +xml media type suffixes" do
      expect(described_class.for(content_type: "application/vnd.api+json")).to be_a(Ai::DataSources::Decoders::Json)
      expect(described_class.for(content_type: "application/vnd.foo+xml")).to be_a(Ai::DataSources::Decoders::Xml)
    end

    it "prefers the explicit format over the content type" do
      decoder = described_class.for(format: "csv", content_type: "application/json")
      expect(decoder).to be_a(Ai::DataSources::Decoders::Csv)
    end
  end

  describe ".for generic fallback" do
    it "falls back to the JSON decoder when nothing is provided" do
      expect(described_class.for).to be_a(Ai::DataSources::Decoders::Json)
    end

    it "falls back to the JSON decoder for an unknown format" do
      expect(described_class.for(format: "protobuf")).to be_a(Ai::DataSources::Decoders::Json)
    end

    it "falls back to the JSON decoder for an unmapped content type" do
      expect(described_class.for(content_type: "application/octet-stream")).to be_a(Ai::DataSources::Decoders::Json)
    end

    it "never returns nil and never raises for garbage input" do
      expect(described_class.for(format: "???", content_type: "garbage/type")).to be_a(Ai::DataSources::Decoders::Json)
    end

    it "returns a fresh (stateless) instance per lookup" do
      a = described_class.for(format: "json")
      b = described_class.for(format: "json")
      expect(a).not_to equal(b)
    end
  end

  describe ".known_format?" do
    it "is true for mapped formats and false for the implicit fallback" do
      expect(described_class.known_format?("json")).to be(true)
      expect(described_class.known_format?("csv")).to be(true)
      expect(described_class.known_format?("protobuf")).to be(false)
      expect(described_class.known_format?(nil)).to be(false)
    end
  end

  describe "end-to-end decode through the selected decoder" do
    it "decodes a CSV body into canonical Array<Hash> records" do
      decoder = described_class.for(format: "csv")
      result = decoder.decode("city,temp\nNYC,72", endpoint: nil)

      expect(result).to eq([{ "city" => "NYC", "temp" => "72" }])
    end

    it "decodes a JSON array into canonical Array<Hash> records" do
      decoder = described_class.for(format: "json")
      result = decoder.decode('[{"a":1},{"a":2}]', endpoint: nil)

      expect(result).to eq([{ "a" => 1 }, { "a" => 2 }])
    end

    it "uses the endpoint's response_mapping when decoding via a persisted endpoint" do
      endpoint = create(:ai_data_source_endpoint, :json, :nested_records)
      decoder = described_class.for(format: endpoint.response_format)
      result = decoder.decode('{"data":{"items":[{"id":1}]}}', endpoint: endpoint)

      expect(result).to eq([{ "id" => 1 }])
    end
  end

  describe described_class::Charset do
    describe ".to_utf8" do
      it "transcodes Latin-1 bytes to valid UTF-8" do
        out = described_class.to_utf8("caf\xE9".b, charset: "ISO-8859-1")

        expect(out).to eq("café")
        expect(out.encoding).to eq(Encoding::UTF_8)
        expect(out).to be_valid_encoding
      end

      it "strips a UTF-8 BOM" do
        out = described_class.to_utf8("\xEF\xBB\xBFhello".b, charset: nil)
        expect(out).to eq("hello")
      end

      it "sniffs a BOM charset when none is declared" do
        # UTF-16LE BOM + 'hi'
        bytes = "\xFF\xFEh\x00i\x00".b
        out = described_class.to_utf8(bytes, charset: nil)

        expect(out).to eq("hi")
        expect(out).to be_valid_encoding
      end

      it "scrubs invalid bytes rather than raising" do
        out = described_class.to_utf8("ab\xFF\xFEcd".b, charset: "UTF-8")

        expect(out).to be_valid_encoding
        expect(out.encoding).to eq(Encoding::UTF_8)
      end

      it "falls back gracefully for an unknown charset name" do
        out = described_class.to_utf8("hello".b, charset: "NOT-A-REAL-CHARSET")

        expect(out).to be_valid_encoding
        expect(out.encoding).to eq(Encoding::UTF_8)
      end

      it "treats the UTF8 alias as UTF-8" do
        out = described_class.to_utf8("ok".b, charset: "utf8")
        expect(out).to eq("ok")
      end
    end
  end
end
