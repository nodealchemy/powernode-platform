# frozen_string_literal: true

require "rails_helper"

# Phase 4 — "generic data source" API wiring. Covers the controller param +
# serializer changes that expose the new free-form source model over REST,
# served by Api::V1::Ai::DataSourcesController (+ the Ai::DataSourceSerialization
# and Ai::DataSourceEndpoints concerns):
#
#   POST   /api/v1/ai/data_sources                      -> persists category + protocol
#   PATCH  /api/v1/ai/data_sources/:id                  -> changes category + protocol
#   GET    /api/v1/ai/data_sources?category=weather     -> filters via the by_category scope
#   POST   /api/v1/ai/data_sources/:id/endpoints        -> persists endpoint.pagination (jsonb)
#
# Permission map (validate_permissions):
#   index           -> ai.data_sources.read
#   create          -> ai.data_sources.create
#   update          -> ai.data_sources.update
#   endpoints_create-> ai.data_sources.update OR ai.data_sources.manage
#
# Top-level member routes resolve the source via ActiveRecord#find, so URLs are
# built from the source UUID (not the slug that #to_param emits).
#
# HERMETIC: the Ai::DataSource after_commit KG sync is stubbed so factory + API
# creates never reach the embedding backend / Redis under DatabaseCleaner
# :deletion. No path here performs an outbound fetch.
RSpec.describe "Api::V1::Ai::DataSource Generic API wiring", type: :request do
  let(:account)  { create(:account) }
  let(:reader)   { user_with_permissions("ai.data_sources.read", account: account) }
  let(:creator)  { user_with_permissions("ai.data_sources.create", "ai.data_sources.read", account: account) }
  let(:editor)   { user_with_permissions("ai.data_sources.update", "ai.data_sources.read", account: account) }

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  # ---------------------------------------------------------------------------
  # POST /data_sources — persists category + protocol (round-trips in response)
  # ---------------------------------------------------------------------------
  describe "POST /data_sources (create)" do
    let(:valid_params) do
      {
        data_source: {
          name: "My Weather API",
          source_type: "my_api",
          category: "weather",
          protocol: "graphql",
          api_base_url: "https://api.example.com"
        }
      }
    end

    it "persists category + protocol and round-trips them in the response" do
      expect do
        post "/api/v1/ai/data_sources", params: valid_params,
             headers: auth_headers_for(creator), as: :json
      end.to change(Ai::DataSource, :count).by(1)

      expect(response).to have_http_status(:created)
      ds = json_response_data["data_source"]
      expect(ds["category"]).to eq("weather")
      expect(ds["protocol"]).to eq("graphql")
      expect(ds["source_type"]).to eq("my_api")

      persisted = Ai::DataSource.find(ds["id"])
      expect(persisted.category).to eq("weather")
      expect(persisted.protocol).to eq("graphql")
    end

    # Phase 4b-1 crawl politeness — the create modal sends these; strong params
    # must permit them and the serializer must round-trip them (else the UI
    # silently discards the operator's politeness settings).
    it "persists crawl-politeness (respect_robots + crawl_delay_seconds) and round-trips them" do
      post "/api/v1/ai/data_sources",
           params: { data_source: valid_params[:data_source].merge(
             respect_robots: true, crawl_delay_seconds: 5
           ) },
           headers: auth_headers_for(creator), as: :json

      expect(response).to have_http_status(:created)
      ds = json_response_data["data_source"]
      expect(ds["respect_robots"]).to eq(true)
      expect(ds["crawl_delay_seconds"]).to eq(5)

      persisted = Ai::DataSource.find(ds["id"])
      expect(persisted.respect_robots).to be(true)
      expect(persisted.crawl_delay_seconds).to eq(5)
    end

    include_examples "requires authentication", :post, "/api/v1/ai/data_sources"
    include_examples "requires permission", :post, "/api/v1/ai/data_sources", "ai.data_sources.create"
  end

  # ---------------------------------------------------------------------------
  # PATCH /data_sources/:id — changes category + protocol
  # ---------------------------------------------------------------------------
  describe "PATCH /data_sources/:id (update)" do
    let!(:data_source) do
      create(:ai_data_source, account: account, category: "weather", protocol: "rest")
    end
    let(:member_path) { "/api/v1/ai/data_sources/#{data_source.id}" }

    it "changes category and protocol" do
      patch member_path,
            params: { data_source: { category: "finance", protocol: "graphql" } },
            headers: auth_headers_for(editor), as: :json

      expect_success_response
      ds = json_response_data["data_source"]
      expect(ds["category"]).to eq("finance")
      expect(ds["protocol"]).to eq("graphql")

      data_source.reload
      expect(data_source.category).to eq("finance")
      expect(data_source.protocol).to eq("graphql")
    end

    it "forbids a read-only user from updating" do
      patch member_path, params: { data_source: { category: "finance" } },
            headers: auth_headers_for(reader), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(data_source.reload.category).to eq("weather")
    end
  end

  # ---------------------------------------------------------------------------
  # GET /data_sources?category=weather — filters via the by_category scope
  # ---------------------------------------------------------------------------
  describe "GET /data_sources?category=weather (index filter)" do
    let!(:weather_source) do
      create(:ai_data_source, account: account, name: "NOAA", category: "weather")
    end
    let!(:finance_source) do
      create(:ai_data_source, account: account, name: "FRED", category: "finance")
    end

    it "returns only sources in the requested category" do
      get "/api/v1/ai/data_sources?category=weather",
          headers: auth_headers_for(reader), as: :json

      expect_success_response
      items = json_response_data["items"]
      ids = items.map { |i| i["id"] }
      expect(ids).to include(weather_source.id)
      expect(ids).not_to include(finance_source.id)
      # The list serializer carries category through too.
      expect(items.first["category"]).to eq("weather")
    end

    include_examples "requires authentication", :get, "/api/v1/ai/data_sources"
  end

  # ---------------------------------------------------------------------------
  # POST /endpoints — persists pagination jsonb (round-trips in response)
  # ---------------------------------------------------------------------------
  describe "POST /endpoints (create) — pagination jsonb" do
    let!(:data_source) { create(:ai_data_source, account: account, slug: "open-meteo") }
    let(:base_path)    { "/api/v1/ai/data_sources/#{data_source.id}/endpoints" }
    let(:pagination) do
      {
        "type"      => "offset",
        "limit"     => 100,
        "max_pages" => 5,
        "params"    => { "offset" => "offset", "limit" => "limit" }
      }
    end

    it "persists pagination and round-trips it in the response" do
      post base_path,
           params: {
             endpoint: {
               name: "Paged Items",
               http_method: "GET",
               path_template: "/v1/items",
               pagination: pagination
             }
           },
           headers: auth_headers_for(editor), as: :json

      expect(response).to have_http_status(:created)
      ep = json_response_data["endpoint"]
      expect(ep["pagination"]).to eq(pagination)

      persisted = data_source.endpoints.find(ep["id"])
      expect(persisted.pagination).to eq(pagination)
    end
  end

  # ---------------------------------------------------------------------------
  # Serializer surface — category/protocol on the source, pagination on endpoint
  # ---------------------------------------------------------------------------
  describe "serializer surface" do
    let!(:data_source) do
      create(:ai_data_source, account: account, category: "weather", protocol: "graphql")
    end
    let!(:endpoint) do
      create(:ai_data_source_endpoint, data_source: data_source,
             pagination: { "type" => "page", "limit" => 50 })
    end

    it "emits category + protocol on the source (show)" do
      get "/api/v1/ai/data_sources/#{data_source.id}",
          headers: auth_headers_for(reader), as: :json

      expect_success_response
      ds = json_response_data["data_source"]
      expect(ds).to include("category" => "weather", "protocol" => "graphql")
    end

    it "emits pagination on the endpoint" do
      get "/api/v1/ai/data_sources/#{data_source.id}/endpoints",
          headers: auth_headers_for(reader), as: :json

      expect_success_response
      ep = json_response_data["items"].first
      expect(ep["pagination"]).to eq("type" => "page", "limit" => 50)
    end
  end

  # ---------------------------------------------------------------------------
  # Model — source_type is now free-form (lowercase token), not an enum
  # ---------------------------------------------------------------------------
  describe "Ai::DataSource#source_type (free-form)" do
    it "accepts an arbitrary lowercase token" do
      ds = build(:ai_data_source, account: account, source_type: "my_api")
      expect(ds).to be_valid
    end

    it "rejects a malformed (non-lowercase) token" do
      ds = build(:ai_data_source, account: account, source_type: "Bad Type!")
      expect(ds).not_to be_valid
      expect(ds.errors[:source_type]).to be_present
    end
  end
end
