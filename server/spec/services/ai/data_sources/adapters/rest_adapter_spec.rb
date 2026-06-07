# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Adapters::RestAdapter do
  subject(:adapter) { described_class.new }

  # Build a lightweight stand-in endpoint so build_request specs stay hermetic
  # and don't require DB round-trips. The adapter only reads these readers.
  def endpoint_double(
    http_method: "GET",
    path_template: "",
    query_template: {},
    body_template: {},
    metadata: {},
    response_format: "json",
    expected_content_type: "application/json"
  )
    instance_double(
      Ai::DataSourceEndpoint,
      http_method: http_method,
      path_template: path_template,
      query_template: query_template,
      body_template: body_template,
      metadata: metadata,
      response_format: response_format,
      expected_content_type: expected_content_type
    )
  end

  describe "#build_request" do
    describe "method + structure" do
      it "returns the canonical request hash shape" do
        req = adapter.build_request(endpoint: endpoint_double, params: {})

        expect(req.keys).to contain_exactly(:method, :url, :headers, :query, :body)
      end

      it "upper-cases the HTTP method" do
        ep = endpoint_double(http_method: "post")
        expect(adapter.build_request(endpoint: ep, params: {})[:method]).to eq("POST")
      end

      it "defaults a blank method to GET" do
        ep = endpoint_double(http_method: "")
        expect(adapter.build_request(endpoint: ep, params: {})[:method]).to eq("GET")
      end
    end

    describe "path interpolation" do
      it "splices an embedded placeholder into the path" do
        ep = endpoint_double(path_template: "/v1/stations/{station_id}/obs")

        req = adapter.build_request(endpoint: ep, params: { station_id: "KNYC" })

        expect(req[:url]).to eq("/v1/stations/KNYC/obs")
      end

      it "accepts string-keyed params interchangeably with symbol keys" do
        ep = endpoint_double(path_template: "/v1/stations/{station_id}/obs")

        req = adapter.build_request(endpoint: ep, params: { "station_id" => "KNYC" })

        expect(req[:url]).to eq("/v1/stations/KNYC/obs")
      end

      it "URL-path-escapes a caller-supplied path segment (no breakout, spaces as %20)" do
        ep = endpoint_double(path_template: "/v1/search/{term}")

        req = adapter.build_request(endpoint: ep, params: { term: "a/b c" })

        # ERB::Util.url_encode escapes "/" and encodes space as %20 (not "+").
        expect(req[:url]).to eq("/v1/search/a%2Fb%20c")
      end

      it "leaves an unknown placeholder intact so misconfig is visible" do
        ep = endpoint_double(path_template: "/v1/{unknown}/x")

        req = adapter.build_request(endpoint: ep, params: { station_id: "KNYC" })

        expect(req[:url]).to eq("/v1/{unknown}/x")
      end

      it "returns an empty path for a blank template" do
        ep = endpoint_double(path_template: "")
        expect(adapter.build_request(endpoint: ep, params: {})[:url]).to eq("")
      end
    end

    describe "query interpolation" do
      it "interpolates query values and passes literal values through" do
        ep = endpoint_double(query_template: { "limit" => "{limit}", "fmt" => "json" })

        req = adapter.build_request(endpoint: ep, params: { limit: 50 })

        expect(req[:query]).to eq("limit" => 50, "fmt" => "json")
      end

      it "preserves the raw param type for a whole-value placeholder" do
        ep = endpoint_double(query_template: { "limit" => "{limit}" })

        req = adapter.build_request(endpoint: ep, params: { limit: 25 })

        expect(req[:query]["limit"]).to eq(25)
        expect(req[:query]["limit"]).to be_an(Integer)
      end

      it "drops entries whose whole-value placeholder resolves to nil (optional params)" do
        ep = endpoint_double(query_template: { "limit" => "{limit}", "fmt" => "json" })

        req = adapter.build_request(endpoint: ep, params: { limit: nil })

        expect(req[:query]).to eq("fmt" => "json")
      end

      it "returns an empty hash when there is no query template" do
        expect(adapter.build_request(endpoint: endpoint_double, params: {})[:query]).to eq({})
      end
    end

    describe "body interpolation" do
      it "builds a structured body for write methods, preserving types" do
        ep = endpoint_double(
          http_method: "POST",
          body_template: { "ids" => "{ids}", "fixed" => true }
        )

        req = adapter.build_request(endpoint: ep, params: { ids: [1, 2, 3] })

        expect(req[:body]).to eq("ids" => [1, 2, 3], "fixed" => true)
      end

      it "interpolates nested hash/array body templates recursively" do
        ep = endpoint_double(
          http_method: "PUT",
          body_template: { "filter" => { "name" => "{name}" }, "tags" => ["{tag}", "static"] }
        )

        req = adapter.build_request(endpoint: ep, params: { name: "acme", tag: "x" })

        expect(req[:body]).to eq(
          "filter" => { "name" => "acme" },
          "tags" => ["x", "static"]
        )
      end

      it "returns nil body for GET (no request body)" do
        ep = endpoint_double(http_method: "GET", body_template: { "ids" => "{ids}" })

        expect(adapter.build_request(endpoint: ep, params: { ids: [1] })[:body]).to be_nil
      end

      it "returns nil body for DELETE" do
        ep = endpoint_double(http_method: "DELETE", body_template: { "ids" => "{ids}" })

        expect(adapter.build_request(endpoint: ep, params: { ids: [1] })[:body]).to be_nil
      end

      it "returns nil body for a write method with an empty template" do
        ep = endpoint_double(http_method: "POST", body_template: {})

        expect(adapter.build_request(endpoint: ep, params: {})[:body]).to be_nil
      end
    end

    describe "static headers" do
      it "stringifies header keys/values from endpoint metadata" do
        ep = endpoint_double(metadata: { "headers" => { "Accept" => "application/json", "X-Trace" => 7 } })

        req = adapter.build_request(endpoint: ep, params: {})

        expect(req[:headers]).to eq("Accept" => "application/json", "X-Trace" => "7")
      end

      it "returns an empty hash when metadata has no headers" do
        expect(adapter.build_request(endpoint: endpoint_double(metadata: {}), params: {})[:headers]).to eq({})
      end
    end
  end

  describe "#parse (delegates to the decoder registry)" do
    it "decodes a JSON array body into canonical records" do
      ep = endpoint_double(response_format: "json", expected_content_type: "application/json")

      records = adapter.parse('[{"city":"NYC","temp":72}]', endpoint: ep)

      expect(records).to eq([{ "city" => "NYC", "temp" => 72 }])
    end

    it "decodes a CSV body into an array of row hashes" do
      ep = endpoint_double(response_format: "csv", expected_content_type: "text/csv")

      records = adapter.parse("city,temp\nNYC,72", endpoint: ep)

      expect(records).to eq([{ "city" => "NYC", "temp" => "72" }])
    end

    it "never raises on a malformed body — yields an empty record set" do
      ep = endpoint_double(response_format: "json", expected_content_type: "application/json")

      expect { @records = adapter.parse("{not-valid-json", endpoint: ep) }.not_to raise_error
      expect(@records).to eq([])
    end

    it "always returns an Array" do
      ep = endpoint_double(response_format: "json")

      expect(adapter.parse('{"single":"object"}', endpoint: ep)).to be_an(Array)
    end
  end
end
