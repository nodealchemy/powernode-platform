# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Decoders::Xml do
  subject(:decoder) { described_class.new }

  def endpoint_with(mapping = {})
    instance_double(Ai::DataSourceEndpoint, response_mapping: mapping)
  end

  describe "feed auto-detection" do
    it "extracts RSS <item> nodes as records" do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
          <title>Feed</title>
          <item><title>First</title><id>1</id></item>
          <item><title>Second</title><id>2</id></item>
        </channel></rss>
      XML

      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to be_an(Array)
      expect(result).to all(be_a(Hash))
      expect(result).to eq(
        [
          { "title" => "First", "id" => "1" },
          { "title" => "Second", "id" => "2" }
        ]
      )
    end

    it "extracts Atom <entry> nodes even with a default namespace" do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Feed</title>
          <entry><title>A</title></entry>
          <entry><title>B</title></entry>
        </feed>
      XML

      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq([{ "title" => "A" }, { "title" => "B" }])
    end
  end

  describe "explicit record location via mapping" do
    let(:body) do
      <<~XML
        <response><results>
          <row><city>NYC</city><temp>72</temp></row>
          <row><city>LA</city><temp>81</temp></row>
        </results></response>
      XML
    end

    it "uses an explicit record_node element name" do
      result = decoder.decode(body, endpoint: endpoint_with("record_node" => "row"))

      expect(result).to eq(
        [
          { "city" => "NYC", "temp" => "72" },
          { "city" => "LA", "temp" => "81" }
        ]
      )
    end

    it "uses an explicit record_xpath" do
      result = decoder.decode(body, endpoint: endpoint_with("record_xpath" => "//results/row"))

      expect(result).to eq(
        [
          { "city" => "NYC", "temp" => "72" },
          { "city" => "LA", "temp" => "81" }
        ]
      )
    end

    it "degrades to the whole-document fallback (without raising) for an invalid record_xpath" do
      # An invalid XPath is caught and yields no record nodes, so the decoder
      # falls back to a single whole-document record rather than raising.
      result = nil
      expect do
        result = decoder.decode(body, endpoint: endpoint_with("record_xpath" => "//[bad("))
      end.not_to raise_error

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first).to be_a(Hash)
    end
  end

  describe "heuristic repeated-sibling detection" do
    it "treats the most-repeated child element as the record node" do
      body = <<~XML
        <catalog>
          <product><sku>A1</sku></product>
          <product><sku>A2</sku></product>
          <product><sku>A3</sku></product>
        </catalog>
      XML

      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq(
        [{ "sku" => "A1" }, { "sku" => "A2" }, { "sku" => "A3" }]
      )
    end

    it "falls back to a single whole-document record when nothing repeats" do
      body = "<config><name>prod</name><level>5</level></config>"
      result = decoder.decode(body, endpoint: endpoint_with)

      expect(result).to eq([{ "name" => "prod", "level" => "5" }])
    end
  end

  describe "node-to-hash mapping" do
    it "prefixes attributes with @ and keeps leaf elements as scalar text" do
      body = <<~XML
        <items>
          <item id="1" active="true"><name>Widget</name></item>
          <item id="2" active="false"><name>Gadget</name></item>
        </items>
      XML

      result = decoder.decode(body, endpoint: endpoint_with("record_node" => "item"))

      expect(result.first).to eq("@id" => "1", "@active" => "true", "name" => "Widget")
      expect(result.last).to eq("@id" => "2", "@active" => "false", "name" => "Gadget")
    end

    it "collects repeated child elements into an array" do
      body = <<~XML
        <list>
          <book><tag>a</tag><tag>b</tag><tag>c</tag></book>
          <book><tag>x</tag><tag>y</tag></book>
        </list>
      XML

      result = decoder.decode(body, endpoint: endpoint_with("record_node" => "book"))

      expect(result.first).to eq("tag" => %w[a b c])
      expect(result.last).to eq("tag" => %w[x y])
    end
  end

  describe "robustness" do
    it "returns an empty set for blank input" do
      expect(decoder.decode("", endpoint: endpoint_with)).to eq([])
      expect(decoder.decode("   \n", endpoint: endpoint_with)).to eq([])
    end

    it "does not raise on malformed XML" do
      expect { decoder.decode("<a><b></a>", endpoint: endpoint_with) }.not_to raise_error
    end
  end

  describe "UTF-8 transcoding" do
    it "transcodes a declared ISO-8859-1 body to valid UTF-8" do
      body = "<root><item><city>caf\xE9</city></item></root>".b
      result = decoder.decode(body, endpoint: endpoint_with("charset" => "ISO-8859-1", "record_node" => "item"))

      expect(result.first["city"]).to eq("café")
      expect(result.first["city"]).to be_valid_encoding
    end
  end
end
