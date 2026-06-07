# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Decoders::Csv do
  subject(:decoder) { described_class.new }

  def endpoint_with(mapping = {})
    instance_double(Ai::DataSourceEndpoint, response_mapping: mapping)
  end

  describe "#decode canonical output" do
    it "maps the header row to keys, one Hash per data row" do
      result = decoder.decode("city,temp\nNYC,72", endpoint: endpoint_with)

      expect(result).to be_an(Array)
      expect(result).to all(be_a(Hash))
      expect(result).to eq([{ "city" => "NYC", "temp" => "72" }])
    end

    it "produces one record per data row across multiple rows" do
      body = "city,temp\nNYC,72\nLA,81\nSF,65"
      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq(
        [
          { "city" => "NYC", "temp" => "72" },
          { "city" => "LA", "temp" => "81" },
          { "city" => "SF", "temp" => "65" }
        ]
      )
    end

    it "keeps all values as strings (no type coercion)" do
      result = decoder.decode("a,b\n1,2.5", endpoint: endpoint_with)

      expect(result).to eq([{ "a" => "1", "b" => "2.5" }])
    end
  end

  describe "delimiter sniffing" do
    it "sniffs a semicolon-delimited dialect" do
      result = decoder.decode("city;temp\nNYC;72", endpoint: endpoint_with)

      expect(result).to eq([{ "city" => "NYC", "temp" => "72" }])
    end

    it "sniffs a tab-delimited dialect" do
      result = decoder.decode("city\ttemp\nNYC\t72", endpoint: endpoint_with)

      expect(result).to eq([{ "city" => "NYC", "temp" => "72" }])
    end

    it "sniffs a pipe-delimited dialect" do
      result = decoder.decode("city|temp\nNYC|72", endpoint: endpoint_with)

      expect(result).to eq([{ "city" => "NYC", "temp" => "72" }])
    end

    it "honours an explicit delimiter from the mapping" do
      result = decoder.decode("city;temp\nNYC;72", endpoint: endpoint_with("delimiter" => ";"))

      expect(result).to eq([{ "city" => "NYC", "temp" => "72" }])
    end

    it "decodes a literal \\t tab-delimiter escape from the mapping" do
      result = decoder.decode("city\ttemp\nNYC\t72", endpoint: endpoint_with("delimiter" => "\\t"))

      expect(result).to eq([{ "city" => "NYC", "temp" => "72" }])
    end
  end

  describe "header detection" do
    it "names columns positionally when there is no header row" do
      # All-numeric first row should not be treated as a header.
      result = decoder.decode("1,2,3\n4,5,6", endpoint: endpoint_with)

      expect(result).to eq(
        [
          { "column_1" => "1", "column_2" => "2", "column_3" => "3" },
          { "column_1" => "4", "column_2" => "5", "column_3" => "6" }
        ]
      )
    end

    it "uses an explicit headers array from the mapping" do
      result = decoder.decode("NYC,72\nLA,81", endpoint: endpoint_with("headers" => %w[city temp]))

      expect(result).to eq(
        [
          { "city" => "NYC", "temp" => "72" },
          { "city" => "LA", "temp" => "81" }
        ]
      )
    end

    it "forces positional columns when headers is explicitly false" do
      result = decoder.decode("city,temp\nNYC,72", endpoint: endpoint_with("headers" => false))

      expect(result).to eq(
        [
          { "column_1" => "city", "column_2" => "temp" },
          { "column_1" => "NYC", "column_2" => "72" }
        ]
      )
    end
  end

  describe "quoting and robustness" do
    it "respects quoted fields containing the delimiter" do
      result = decoder.decode("name,note\n\"Smith, John\",hello", endpoint: endpoint_with)

      expect(result).to eq([{ "name" => "Smith, John", "note" => "hello" }])
    end

    it "skips fully blank lines" do
      body = "city,temp\nNYC,72\n\n\nLA,81\n"
      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq(
        [{ "city" => "NYC", "temp" => "72" }, { "city" => "LA", "temp" => "81" }]
      )
    end

    it "normalises CRLF line endings" do
      result = decoder.decode("city,temp\r\nNYC,72\r\n", endpoint: endpoint_with)

      expect(result).to eq([{ "city" => "NYC", "temp" => "72" }])
    end

    it "returns an empty set for blank input" do
      expect(decoder.decode("", endpoint: endpoint_with)).to eq([])
      expect(decoder.decode("  \n ", endpoint: endpoint_with)).to eq([])
    end

    it "does not raise on a wholly unparseable body" do
      expect { decoder.decode("\"unterminated", endpoint: endpoint_with) }.not_to raise_error
    end
  end

  describe "UTF-8 transcoding" do
    it "transcodes a declared ISO-8859-1 body to valid UTF-8" do
      body = "city,note\nNYC,caf\xE9".b
      result = decoder.decode(body, endpoint: endpoint_with("charset" => "ISO-8859-1"))

      expect(result.first["note"]).to eq("café")
      expect(result.first["note"]).to be_valid_encoding
    end
  end
end
