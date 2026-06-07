# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Adapters::GraphqlAdapter do
  subject(:adapter) { described_class.new }

  # Hermetic endpoint stand-in: the adapter only reads these readers.
  def endpoint_double(
    path_template: "",
    query_template: {},
    body_template: {},
    metadata: {},
    response_mapping: {},
    expected_content_type: "application/json"
  )
    instance_double(
      Ai::DataSourceEndpoint,
      http_method: "POST",
      path_template: path_template,
      query_template: query_template,
      body_template: body_template,
      metadata: metadata,
      response_mapping: response_mapping,
      expected_content_type: expected_content_type
    )
  end

  describe "#build_request" do
    it "always POSTs to the endpoint path with a JSON body" do
      ep = endpoint_double(path_template: "/graphql")

      req = adapter.build_request(endpoint: ep, params: { "query" => "{ me { id } }" })

      expect(req[:method]).to eq("POST")
      expect(req[:url]).to eq("/graphql")
      expect(req[:query]).to eq({})
      expect(req[:headers]["Content-Type"]).to eq("application/json")
    end

    it "uses a caller-supplied query over the stored body_template query" do
      ep = endpoint_double(body_template: { "query" => "{ stored }" })

      req = adapter.build_request(endpoint: ep, params: { "query" => "{ live }" })

      expect(req[:body]["query"]).to eq("{ live }")
    end

    it "falls back to the body_template query when no caller query is given" do
      ep = endpoint_double(body_template: { "query" => "query Q($id: ID!) { node(id: $id) { id } }" })

      req = adapter.build_request(endpoint: ep, params: { "id" => "abc" })

      expect(req[:body]["query"]).to include("node(id: $id)")
    end

    it "folds loose params into variables" do
      ep = endpoint_double(body_template: { "query" => "q" })

      req = adapter.build_request(endpoint: ep, params: { "id" => "abc", "limit" => 5 })

      expect(req[:body]["variables"]).to eq("id" => "abc", "limit" => 5)
    end

    it "merges an explicit variables hash over loose params and template variables" do
      ep = endpoint_double(
        body_template: { "query" => "q", "variables" => { "page" => "{page}" } }
      )

      req = adapter.build_request(
        endpoint: ep,
        params: { "page" => 2, "variables" => { "page" => 9, "extra" => true } }
      )

      expect(req[:body]["variables"]).to include("page" => 9, "extra" => true)
    end

    it "never leaks query/variables control keys or the monitor etag hint into variables" do
      ep = endpoint_double(body_template: { "query" => "q" })

      req = adapter.build_request(
        endpoint: ep,
        params: { "query" => "q", "variables" => { "a" => 1 }, "__conditional_etag" => "W/123", "real" => "x" }
      )

      expect(req[:body]["variables"].keys).to contain_exactly("a", "real")
    end
  end

  describe "#parse" do
    it "unwraps a single-field data object into its records" do
      body = { data: { stations: [{ id: 1 }, { id: 2 }] } }.to_json

      records = adapter.parse(body, endpoint: endpoint_double)

      expect(records).to eq([{ "id" => 1 }, { "id" => 2 }])
    end

    it "returns the data object itself as a single record when it has multiple keys" do
      body = { data: { a: 1, b: 2 } }.to_json

      records = adapter.parse(body, endpoint: endpoint_double)

      expect(records).to eq([{ "a" => 1, "b" => 2 }])
    end

    it "honors an explicit response_mapping records_path against the whole document" do
      ep = endpoint_double(response_mapping: { "records_path" => "data.viewer.repos" })
      body = { data: { viewer: { repos: [{ name: "x" }] } } }.to_json

      records = adapter.parse(body, endpoint: ep)

      expect(records).to eq([{ "name" => "x" }])
    end

    it "wraps scalar records under value" do
      body = { data: { tags: %w[a b] } }.to_json

      records = adapter.parse(body, endpoint: endpoint_double)

      expect(records).to eq([{ "value" => "a" }, { "value" => "b" }])
    end

    it "returns an empty set for a GraphQL error body with null data" do
      body = { data: nil, errors: [{ message: "boom" }] }.to_json

      records = adapter.parse(body, endpoint: endpoint_double)

      expect(records).to eq([])
    end

    it "returns an empty set (never raises) for malformed JSON" do
      expect(adapter.parse("<<not json>>", endpoint: endpoint_double)).to eq([])
    end

    it "returns an empty set for a blank body" do
      expect(adapter.parse("", endpoint: endpoint_double)).to eq([])
    end
  end
end
