# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Decoders::Json do
  subject(:decoder) { described_class.new }

  # Lightweight stub: the decoder only ever calls #response_mapping on the
  # endpoint, so a double keeps these specs hermetic (no DB rows needed).
  def endpoint_with(mapping = {})
    instance_double(Ai::DataSourceEndpoint, response_mapping: mapping)
  end

  describe "#decode canonical output" do
    it "returns Array<Hash> for a top-level JSON array" do
      result = decoder.decode('[{"city":"NYC","temp":72},{"city":"LA","temp":81}]', endpoint: endpoint_with)

      expect(result).to be_an(Array)
      expect(result).to all(be_a(Hash))
      expect(result).to eq(
        [{ "city" => "NYC", "temp" => 72 }, { "city" => "LA", "temp" => 81 }]
      )
    end

    it "wraps a top-level Hash as a single record" do
      result = decoder.decode('{"city":"NYC","temp":72}', endpoint: endpoint_with)

      expect(result).to eq([{ "city" => "NYC", "temp" => 72 }])
    end

    it "wraps a top-level scalar under the value key" do
      result = decoder.decode("42", endpoint: endpoint_with)

      expect(result).to eq([{ "value" => 42 }])
    end

    it "wraps non-Hash array elements under the value key" do
      result = decoder.decode('["a","b"]', endpoint: endpoint_with)

      expect(result).to eq([{ "value" => "a" }, { "value" => "b" }])
    end
  end

  describe "records_path resolution" do
    let(:body) { '{"data":{"items":[{"id":1},{"id":2}]}}' }

    it "follows a dotted records_path into a nested array" do
      result = decoder.decode(body, endpoint: endpoint_with("records_path" => "data.items"))

      expect(result).to eq([{ "id" => 1 }, { "id" => 2 }])
    end

    it "follows a JSON-pointer style records_path" do
      result = decoder.decode(body, endpoint: endpoint_with("records_path" => "/data/items"))

      expect(result).to eq([{ "id" => 1 }, { "id" => 2 }])
    end

    it "indexes into arrays with numeric path segments" do
      nested = '{"pages":[{"rows":[{"x":1}]},{"rows":[{"x":2}]}]}'
      result = decoder.decode(nested, endpoint: endpoint_with("records_path" => "pages.1.rows"))

      expect(result).to eq([{ "x" => 2 }])
    end

    it "returns an empty set when the records_path does not resolve" do
      result = decoder.decode(body, endpoint: endpoint_with("records_path" => "data.missing"))

      expect(result).to eq([])
    end

    it "honours the 'root' alias for the records path" do
      result = decoder.decode(body, endpoint: endpoint_with("root" => "data.items"))

      expect(result).to eq([{ "id" => 1 }, { "id" => 2 }])
    end
  end

  describe "robustness" do
    it "returns an empty set for blank input" do
      expect(decoder.decode("", endpoint: endpoint_with)).to eq([])
      expect(decoder.decode("   \n ", endpoint: endpoint_with)).to eq([])
    end

    it "degrades to an empty set on malformed JSON rather than raising" do
      expect { decoder.decode("{not json", endpoint: endpoint_with) }.not_to raise_error
      expect(decoder.decode("{not json", endpoint: endpoint_with)).to eq([])
    end

    it "tolerates a nil endpoint" do
      expect(decoder.decode('[{"a":1}]', endpoint: nil)).to eq([{ "a" => 1 }])
    end
  end

  describe "UTF-8 transcoding" do
    it "transcodes a declared ISO-8859-1 body to valid UTF-8" do
      # 0xE9 is e-acute in Latin-1; the JSON string value must survive transcoding.
      latin1 = %({"city":"caf\xE9"}).b
      result = decoder.decode(latin1, endpoint: endpoint_with("charset" => "ISO-8859-1"))

      expect(result.first["city"]).to eq("café")
      expect(result.first["city"].encoding).to eq(Encoding::UTF_8)
      expect(result.first["city"]).to be_valid_encoding
    end

    it "strips a UTF-8 BOM before parsing" do
      body = "\xEF\xBB\xBF".b + '{"ok":true}'
      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq([{ "ok" => true }])
    end
  end
end
