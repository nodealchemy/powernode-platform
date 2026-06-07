# frozen_string_literal: true

require "rails_helper"

# Request specs for the Phase 2b read-only observability surface + the OpenAPI
# introspection write surface, served by Api::V1::Ai::DataSourcesController via
# the Ai::DataSourceEndpoints concern:
#
#   GET  /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/schema_history
#   GET  /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/quality
#   GET  /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/contract
#   POST /api/v1/ai/data_sources/:data_source_id/introspect
#
# Permission map (validate_permissions):
#   schema_history / quality / contract -> ai.data_sources.read
#   introspect (write surface, even dry_run) -> ai.data_sources.manage
#
# Response shapes match the frontend TS types (DataSourceSchemaHistoryResponse /
# DataSourceQualityResponse / DataSourceContractVerdict / DataSourceOpenApiImportResult).
#
# HERMETIC: the DataSource after_commit KG sync is stubbed so factory creates do
# not reach the embedding backend / Redis under DatabaseCleaner :deletion. The
# GET endpoints never perform an outbound fetch (they read recorded rows), and
# introspect is exercised with an inline parsed spec (no spec_url fetch).
RSpec.describe "Api::V1::Ai::DataSource Observability", type: :request do
  let(:account) { create(:account) }
  let(:reader) { user_with_permissions("ai.data_sources.read", account: account) }
  let(:manager) { user_with_permissions("ai.data_sources.manage", account: account) }

  let!(:data_source) { create(:ai_data_source, account: account, slug: "open-meteo") }
  let!(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source, slug: "forecast") }

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  # --------------------------------------------------------------------------
  # GET .../schema_history
  # --------------------------------------------------------------------------
  describe "GET .../endpoints/:endpoint_id/schema_history" do
    let(:path) { "/api/v1/ai/data_sources/#{data_source.id}/endpoints/#{endpoint.id}/schema_history" }

    let!(:version_one) do
      Ai::DataSources::SchemaDriftService.new(account).record_version!(
        endpoint, { "type" => "array", "items" => { "type" => "object", "properties" => { "city" => { "type" => "string" } } } }
      )
    end
    let!(:version_two) do
      Ai::DataSources::SchemaDriftService.new(account).record_version!(
        endpoint, { "type" => "array", "items" => { "type" => "object", "properties" => { "city" => { "type" => "string" }, "temp" => { "type" => "number" } } } }
      )
    end

    it "returns the schema-version history newest-first with a latest pointer" do
      get path, headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["endpoint_id"]).to eq(endpoint.id)
      expect(data["count"]).to eq(2)
      expect(data["versions"]).to be_an(Array)
      # Newest-first: version 2 leads.
      expect(data["versions"].first["version"]).to eq(2)
      expect(data["versions"].first["classification"]).to eq("additive")
      expect(data["versions"].first).to include("schema", "checksum", "diff")
      expect(data["latest"]["version"]).to eq(2)
    end

    it "returns an empty history for an endpoint with no recorded versions" do
      fresh = create(:ai_data_source_endpoint, data_source: data_source, slug: "history")

      get "/api/v1/ai/data_sources/#{data_source.id}/endpoints/#{fresh.id}/schema_history",
          headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["count"]).to eq(0)
      expect(data["versions"]).to eq([])
      expect(data["latest"]).to be_nil
    end

    it "forbids a user without ai.data_sources.read" do
      get path, headers: auth_headers_for(user_without_permissions(account: account)), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "does not expose history under another account's source" do
      other = create(:ai_data_source, account: create(:account))
      other_ep = create(:ai_data_source_endpoint, data_source: other)

      get "/api/v1/ai/data_sources/#{other.id}/endpoints/#{other_ep.id}/schema_history",
          headers: auth_headers_for(reader), as: :json

      expect_error_response("Data source not found", 404)
    end

    include_examples "requires authentication", :get,
                     "/api/v1/ai/data_sources/placeholder/endpoints/placeholder/schema_history"
  end

  # --------------------------------------------------------------------------
  # GET .../quality
  # --------------------------------------------------------------------------
  describe "GET .../endpoints/:endpoint_id/quality" do
    let(:path) { "/api/v1/ai/data_sources/#{data_source.id}/endpoints/#{endpoint.id}/quality" }

    let!(:expectation) do
      create(:ai_data_source_expectation, endpoint: endpoint, name: "non_empty",
                                          rule_type: "min_records", severity: "warn", config: { "min" => 1 })
    end
    let!(:recorded_query) do
      Ai::DataSourceQuery.create!(
        account_id: account.id, ai_data_source_id: data_source.id,
        ai_data_source_endpoint_id: endpoint.id, status: "success",
        quality_score: 0.92, quality_passed: true, quarantined: false,
        schema_drift: "none", metadata: { "anomalies" => [] }
      )
    end

    it "returns the latest quality outcome plus configured expectations" do
      get path, headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["endpoint_id"]).to eq(endpoint.id)
      expect(data["quality_checks_enabled"]).to be(false)
      expect(data["quarantine_on_failure"]).to be(false)
      expect(data["latest"]).to include(
        "quality_score" => 0.92, "quality_passed" => true, "quarantined" => false, "schema_drift" => "none"
      )
      expect(data["expectations"]).to be_an(Array)
      expect(data["expectations"].first).to include("name" => "non_empty", "rule_type" => "min_records", "severity" => "warn")
    end

    it "returns a nil latest when the endpoint has never run a quality-checked fetch" do
      fresh = create(:ai_data_source_endpoint, data_source: data_source, slug: "no-quality")

      get "/api/v1/ai/data_sources/#{data_source.id}/endpoints/#{fresh.id}/quality",
          headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["latest"]).to be_nil
      expect(data["expectations"]).to eq([])
    end

    it "forbids a user without ai.data_sources.read" do
      get path, headers: auth_headers_for(user_without_permissions(account: account)), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    include_examples "requires authentication", :get,
                     "/api/v1/ai/data_sources/placeholder/endpoints/placeholder/quality"
  end

  # --------------------------------------------------------------------------
  # GET .../contract — read-only verdict from the latest recorded row
  # --------------------------------------------------------------------------
  describe "GET .../endpoints/:endpoint_id/contract" do
    let(:path) { "/api/v1/ai/data_sources/#{data_source.id}/endpoints/#{endpoint.id}/contract" }

    it "returns a vacuously-met verdict when there is no prior query" do
      get path, headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["met"]).to be(true)
      expect(data["violations"]).to eq([])
      expect(data).to include("schema_valid", "quality_passed", "within_sla")
    end

    it "reports violations distilled from the latest recorded row" do
      Ai::DataSourceQuery.create!(
        account_id: account.id, ai_data_source_id: data_source.id,
        ai_data_source_endpoint_id: endpoint.id, status: "success",
        schema_valid: false, quality_passed: false
      )

      get path, headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["met"]).to be(false)
      expect(data["schema_valid"]).to be(false)
      expect(data["quality_passed"]).to be(false)
      expect(data["violations"]).to include("schema_invalid", "quality_failed")
    end

    it "must NOT trigger an outbound fetch (a GET is side-effect-free)" do
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      get path, headers: auth_headers_for(reader), as: :json

      expect_success_response
    end

    it "forbids a user without ai.data_sources.read" do
      get path, headers: auth_headers_for(user_without_permissions(account: account)), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    include_examples "requires authentication", :get,
                     "/api/v1/ai/data_sources/placeholder/endpoints/placeholder/contract"
  end

  # --------------------------------------------------------------------------
  # POST .../introspect — OpenAPI import (manage-gated; dry_run)
  # --------------------------------------------------------------------------
  describe "POST .../introspect" do
    let(:path) { "/api/v1/ai/data_sources/#{data_source.id}/introspect" }

    let(:spec) do
      {
        "openapi" => "3.0.0",
        "paths" => {
          "/forecast" => {
            "get" => {
              "operationId" => "get_forecast",
              "summary" => "Get forecast",
              "responses" => {
                "200" => {
                  "content" => {
                    "application/json" => {
                      "schema" => { "type" => "object", "properties" => { "temp" => { "type" => "number" } } }
                    }
                  }
                }
              }
            }
          }
        }
      }
    end

    it "imports endpoints from an inline parsed spec with the manage grant" do
      expect do
        post path, params: { spec: spec }, headers: auth_headers_for(manager), as: :json
      end.to change { data_source.endpoints.count }.by(1)

      expect_success_response
      data = json_response_data
      expect(data["dry_run"]).to be(false)
      expect(data["created"]).to be_an(Array)
      expect(data["created"].size).to eq(1)
      expect(data["created"].first).to include("slug" => "get_forecast", "http_method" => "GET")
      expect(data["errors"]).to eq([])
    end

    it "previews without persisting on dry_run" do
      expect do
        post path, params: { spec: spec, dry_run: true }, headers: auth_headers_for(manager), as: :json
      end.not_to change { data_source.endpoints.count }

      expect_success_response
      data = json_response_data
      expect(data["dry_run"]).to be(true)
      expect(data["created"]).to eq([])
      expect(data["preview"].size).to eq(1)
      expect(data["preview"].first).to include("path_template" => "/forecast")
    end

    it "returns 422 when neither spec nor url is supplied" do
      post path, params: {}, headers: auth_headers_for(manager), as: :json

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
      expect(json_response["success"]).to be false
      expect(json_response["error"]).to match(/spec or url is required/i)
    end

    it "forbids a reader (read grant is insufficient — introspect needs manage)" do
      post path, params: { spec: spec }, headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a user with no permissions at all" do
      post path, params: { spec: spec },
           headers: auth_headers_for(user_without_permissions(account: account)), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "does not import into another account's source" do
      other = create(:ai_data_source, account: create(:account))

      post "/api/v1/ai/data_sources/#{other.id}/introspect", params: { spec: spec },
           headers: auth_headers_for(manager), as: :json

      expect_error_response("Data source not found", 404)
    end

    include_examples "requires authentication", :post,
                     "/api/v1/ai/data_sources/placeholder/introspect"
  end
end
