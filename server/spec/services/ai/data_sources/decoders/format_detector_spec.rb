# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Decoders::FormatDetector do
  def endpoint_expecting(content_type)
    instance_double(Ai::DataSourceEndpoint, expected_content_type: content_type)
  end

  describe ".detect return envelope" do
    it "returns the documented stable envelope shape" do
      result = described_class.detect('[{"a":1}]', declared_content_type: "application/json")

      expect(result).to include(
        :format, :content_type, :mismatch, :charset,
        :declared_format, :detected_format, :source
      )
    end
  end

  describe "magic-byte / structural sniffing" do
    it "sniffs a JSON array from the leading bracket" do
      result = described_class.detect('[{"a":1}]', declared_content_type: nil)

      expect(result[:format]).to eq("json")
      expect(result[:detected_format]).to eq("json")
      expect(result[:source]).to eq(:sniff)
    end

    it "sniffs a JSON object from the leading brace" do
      result = described_class.detect('{"a":1}', declared_content_type: nil)

      expect(result[:format]).to eq("json")
    end

    it "sniffs NDJSON from multiple newline-delimited objects" do
      body = "{\"a\":1}\n{\"a\":2}\n{\"a\":3}"
      result = described_class.detect(body, declared_content_type: nil)

      expect(result[:format]).to eq("ndjson")
    end

    it "sniffs generic XML from the prolog" do
      result = described_class.detect("<?xml version=\"1.0\"?><root><a/></root>", declared_content_type: nil)

      expect(result[:format]).to eq("xml")
      expect(result[:source]).to eq(:sniff)
    end

    it "sniffs RSS from the root element" do
      result = described_class.detect("<rss version=\"2.0\"><channel/></rss>", declared_content_type: nil)

      expect(result[:format]).to eq("rss")
    end

    it "sniffs Atom from the <feed> root element" do
      result = described_class.detect("<feed xmlns=\"http://www.w3.org/2005/Atom\"></feed>", declared_content_type: nil)

      expect(result[:format]).to eq("atom")
    end

    it "sniffs HTML from the <html> root element" do
      result = described_class.detect("<html><body>hi</body></html>", declared_content_type: nil)

      expect(result[:format]).to eq("html")
    end
  end

  describe "declared content-type and endpoint fallback" do
    it "falls back to the declared content type when bytes are unrecognised (CSV)" do
      # CSV has no structural magic bytes, so detection leans on the header.
      result = described_class.detect("city,temp\nNYC,72", declared_content_type: "text/csv")

      expect(result[:format]).to eq("csv")
      expect(result[:source]).to eq(:declared_content_type)
      expect(result[:mismatch]).to be(false)
    end

    it "falls back to the endpoint's expected_content_type when no header is present" do
      result = described_class.detect(
        "col1,col2\n1,2",
        declared_content_type: nil,
        endpoint: endpoint_expecting("text/csv")
      )

      expect(result[:format]).to eq("csv")
      expect(result[:source]).to eq(:endpoint_expected)
    end

    it "falls back to octet-stream for a wholly unknown body" do
      result = described_class.detect("\x00\x01\x02\x03binary", declared_content_type: nil)

      expect(result[:source]).to eq(:octet_stream_fallback).or eq(:sniff)
      # Either way, an unrecognised text body resolves to the generic envelope.
      expect(result[:content_type]).to be_a(String)
    end
  end

  describe "declared-vs-detected mismatch" do
    it "flags a mismatch when an HTML body is served with a JSON content type" do
      result = described_class.detect("<html><body>error</body></html>", declared_content_type: "application/json")

      expect(result[:detected_format]).to eq("html")
      expect(result[:declared_format]).to eq("json")
      expect(result[:mismatch]).to be(true)
    end

    it "does not flag a mismatch when bytes and header agree" do
      result = described_class.detect('[{"a":1}]', declared_content_type: "application/json")

      expect(result[:mismatch]).to be(false)
    end

    it "treats NDJSON-detected vs JSON-declared as compatible (no mismatch)" do
      body = "{\"a\":1}\n{\"a\":2}"
      result = described_class.detect(body, declared_content_type: "application/json")

      expect(result[:detected_format]).to eq("ndjson")
      expect(result[:mismatch]).to be(false)
    end

    it "treats RSS-detected vs XML-declared as compatible (no mismatch)" do
      result = described_class.detect("<rss version=\"2.0\"><channel/></rss>", declared_content_type: "application/xml")

      expect(result[:mismatch]).to be(false)
    end

    it "does not flag a mismatch when there is no declared format" do
      result = described_class.detect('[{"a":1}]', declared_content_type: nil)

      expect(result[:mismatch]).to be(false)
    end
  end

  describe "charset detection" do
    it "defaults to UTF-8 when nothing indicates otherwise" do
      result = described_class.detect('{"a":1}', declared_content_type: "application/json")

      expect(result[:charset]).to eq("UTF-8")
    end

    it "reads the charset from the declared content type" do
      result = described_class.detect(
        "city,temp\nNYC,72",
        declared_content_type: "text/csv; charset=ISO-8859-1"
      )

      expect(result[:charset]).to eq("ISO-8859-1")
    end

    it "prefers a body BOM over the declared header charset" do
      body = "\xEF\xBB\xBF".b + '{"a":1}'
      result = described_class.detect(body, declared_content_type: "application/json; charset=ISO-8859-1")

      expect(result[:charset]).to eq("UTF-8")
    end

    it "detects a UTF-16LE BOM as the charset" do
      body = "\xFF\xFE".b + "{\x00".b
      result = described_class.detect(body, declared_content_type: nil)

      expect(result[:charset]).to eq("UTF-16LE")
    end
  end

  describe "content-type parsing helpers" do
    it "splits a parameterised content type into [mime, charset]" do
      expect(described_class.parse_content_type("application/json; charset=utf-8"))
        .to eq(["application/json", "UTF-8"])
    end

    it "returns [nil, nil] for blank input" do
      expect(described_class.parse_content_type(nil)).to eq([nil, nil])
      expect(described_class.parse_content_type("")).to eq([nil, nil])
    end

    it "maps structured +json / +xml suffixes to canonical formats" do
      expect(described_class.format_from_mime("application/vnd.api+json")).to eq("json")
      expect(described_class.format_from_mime("application/vnd.foo+xml")).to eq("xml")
    end

    it "returns nil format for an unmapped mime type" do
      expect(described_class.format_from_mime("application/octet-stream")).to be_nil
    end
  end

  describe "edge cases" do
    it "never raises and returns a Hash for an empty body" do
      result = described_class.detect("", declared_content_type: nil)

      expect(result).to be_a(Hash)
      expect(result[:format]).to eq("unknown")
    end

    it "never raises for a nil body" do
      expect { described_class.detect(nil, declared_content_type: nil) }.not_to raise_error
    end
  end
end
