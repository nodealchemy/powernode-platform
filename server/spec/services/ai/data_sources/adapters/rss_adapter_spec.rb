# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Adapters::RssAdapter do
  subject(:adapter) { described_class.new }

  def endpoint_double(http_method: "GET", path_template: "", response_mapping: {})
    instance_double(
      Ai::DataSourceEndpoint,
      http_method: http_method,
      path_template: path_template,
      query_template: {},
      body_template: {},
      metadata: {},
      response_format: "rss",
      response_mapping: response_mapping,
      expected_content_type: "application/rss+xml"
    )
  end

  let(:rss_feed) do
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Example Feed</title>
          <item>
            <title>First Post</title>
            <link>https://example.com/1</link>
            <description>Summary one</description>
            <pubDate>Mon, 01 Jan 2026 00:00:00 GMT</pubDate>
            <guid>tag:example,1</guid>
            <author>alice</author>
          </item>
          <item>
            <title>Second Post</title>
            <link>https://example.com/2</link>
            <description>Summary two</description>
            <pubDate>Tue, 02 Jan 2026 00:00:00 GMT</pubDate>
            <guid>tag:example,2</guid>
          </item>
        </channel>
      </rss>
    XML
  end

  let(:atom_feed) do
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Atom Example</title>
        <entry>
          <title>Atom Entry</title>
          <link rel="alternate" href="https://example.com/a"/>
          <link rel="self" href="https://example.com/self"/>
          <summary>Atom summary</summary>
          <published>2026-01-01T00:00:00Z</published>
          <id>urn:uuid:1</id>
        </entry>
      </feed>
    XML
  end

  describe "request shape (inherited GET)" do
    it "issues a GET (RssAdapter is a thin RestAdapter subclass)" do
      req = adapter.build_request(endpoint: endpoint_double(path_template: "/feed.xml"), params: {})

      expect(req[:method]).to eq("GET")
      expect(req[:url]).to eq("/feed.xml")
    end

    it "is a RestAdapter subclass" do
      expect(described_class.ancestors).to include(Ai::DataSources::Adapters::RestAdapter)
    end
  end

  describe "#parse RSS" do
    let(:records) { adapter.parse(rss_feed, endpoint: endpoint_double) }

    it "maps each item to a canonical record" do
      expect(records.size).to eq(2)
    end

    it "extracts canonical title/link/published/summary/guid" do
      first = records.first

      expect(first["title"]).to eq("First Post")
      expect(first["link"]).to eq("https://example.com/1")
      expect(first["summary"]).to eq("Summary one")
      expect(first["published"]).to eq("Mon, 01 Jan 2026 00:00:00 GMT")
      expect(first["guid"]).to eq("tag:example,1")
      expect(first["id"]).to eq("tag:example,1")
    end

    it "preserves the full decoded item under raw" do
      expect(records.first["raw"]).to include("author" => "alice")
    end
  end

  describe "#parse Atom" do
    let(:records) { adapter.parse(atom_feed, endpoint: endpoint_double) }

    it "maps the entry to a canonical record" do
      expect(records.size).to eq(1)
    end

    it "prefers the rel=alternate link href" do
      expect(records.first["link"]).to eq("https://example.com/a")
    end

    it "maps Atom published + summary + id->guid" do
      rec = records.first

      expect(rec["published"]).to eq("2026-01-01T00:00:00Z")
      expect(rec["summary"]).to eq("Atom summary")
      expect(rec["guid"]).to eq("urn:uuid:1")
    end
  end

  describe "resilience" do
    it "returns an empty set for a blank body" do
      expect(adapter.parse("", endpoint: endpoint_double)).to eq([])
    end

    it "never fabricates nil fields for omitted elements" do
      minimal = <<~XML
        <rss version="2.0"><channel><item><title>Only Title</title></item></channel></rss>
      XML

      rec = adapter.parse(minimal, endpoint: endpoint_double).first

      expect(rec).to include("title" => "Only Title")
      expect(rec).not_to have_key("link")
      expect(rec).not_to have_key("summary")
    end
  end
end
