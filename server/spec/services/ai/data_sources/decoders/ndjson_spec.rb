# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Decoders::Ndjson do
  subject(:decoder) { described_class.new }

  def endpoint_with(mapping = {})
    instance_double(Ai::DataSourceEndpoint, response_mapping: mapping)
  end

  describe "#decode canonical output" do
    it "returns one Hash per non-blank line" do
      body = <<~NDJSON
        {"id":1,"name":"a"}
        {"id":2,"name":"b"}
        {"id":3,"name":"c"}
      NDJSON

      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to be_an(Array)
      expect(result).to all(be_a(Hash))
      expect(result).to eq(
        [
          { "id" => 1, "name" => "a" },
          { "id" => 2, "name" => "b" },
          { "id" => 3, "name" => "c" }
        ]
      )
    end

    it "skips blank and whitespace-only lines" do
      body = "{\"id\":1}\n\n   \n{\"id\":2}\n"
      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq([{ "id" => 1 }, { "id" => 2 }])
    end

    it "wraps non-Hash line values under the value key" do
      body = "42\n\"hello\"\n[1,2]\n"
      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq(
        [{ "value" => 42 }, { "value" => "hello" }, { "value" => [1, 2] }]
      )
    end
  end

  describe "line-ending handling" do
    it "handles CRLF line endings" do
      body = "{\"id\":1}\r\n{\"id\":2}\r\n"
      expect(decoder.decode(body, endpoint: endpoint_with)).to eq([{ "id" => 1 }, { "id" => 2 }])
    end

    it "handles bare CR line endings" do
      body = "{\"id\":1}\r{\"id\":2}"
      expect(decoder.decode(body, endpoint: endpoint_with)).to eq([{ "id" => 1 }, { "id" => 2 }])
    end
  end

  describe "robustness" do
    it "skips a single malformed line but keeps the rest of the stream" do
      body = "{\"id\":1}\n{bad line\n{\"id\":3}\n"
      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq([{ "id" => 1 }, { "id" => 3 }])
    end

    it "preserves an explicit JSON null line (distinct from a parse failure)" do
      body = "{\"id\":1}\nnull\n{\"id\":2}\n"
      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq([{ "id" => 1 }, { "value" => nil }, { "id" => 2 }])
    end

    it "returns an empty set for blank input" do
      expect(decoder.decode("", endpoint: endpoint_with)).to eq([])
    end

    it "does not raise on an all-malformed payload" do
      body = (["not json"] * 10).join("\n")
      expect { decoder.decode(body, endpoint: endpoint_with) }.not_to raise_error
      expect(decoder.decode(body, endpoint: endpoint_with)).to eq([])
    end
  end

  describe "UTF-8 transcoding" do
    it "transcodes a declared ISO-8859-1 body to valid UTF-8" do
      body = (%({"city":"caf\xE9"}) + "\n").b
      result = decoder.decode(body, endpoint: endpoint_with("charset" => "ISO-8859-1"))

      expect(result.first["city"]).to eq("café")
      expect(result.first["city"]).to be_valid_encoding
    end
  end
end
