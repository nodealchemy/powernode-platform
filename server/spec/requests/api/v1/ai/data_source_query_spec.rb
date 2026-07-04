# frozen_string_literal: true

require "rails_helper"

# Request specs for the governed external-fetch endpoint:
#
#   POST /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/query
#
# Served by Api::V1::Ai::DataSourcesController#endpoints_query (Ai::DataSourceEndpoints
# concern), which delegates to Ai::DataSources::EndpointQueryRunner ->
# Ai::DataSources::QueryService and renders the FetchEnvelope through
# render_success / render_error.
#
# Authorization: requires ai.data_sources.query.
#
# HERMETIC: QueryService is stubbed so no outbound HTTP is ever performed — these
# specs assert the controller's authorization, scoping, and envelope rendering,
# not the live fetch pipeline (covered by the QueryService unit specs).
RSpec.describe "Api::V1::Ai::DataSource Query", type: :request do
  let(:account) { create(:account) }
  let(:querier) { user_with_permissions("ai.data_sources.query", account: account) }

  let!(:data_source) { create(:ai_data_source, account: account, slug: "open-meteo") }
  let!(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source, slug: "forecast") }
  let(:query_path) { "/api/v1/ai/data_sources/#{data_source.id}/endpoints/#{endpoint.id}/query" }

  let(:success_envelope) do
    {
      success: true,
      data: [{ "city" => "NYC", "temp" => "72" }],
      provenance: {
        slug: "open-meteo",
        endpoint_id: endpoint.id,
        from_cache: false,
        response_sha256: "abc123",
        record_count: 1,
        anomalies: []
      },
      status: "success",
      duration_ms: 12,
      bytes: 42,
      error: nil
    }
  end

  def stub_query_service(envelope)
    fake = instance_double(Ai::DataSources::QueryService, call: envelope)
    allow(Ai::DataSources::QueryService).to receive(:new).and_return(fake)
    fake
  end

  describe "POST .../query (happy path)" do
    it "runs the governed fetch and renders the FetchEnvelope under data" do
      stub_query_service(success_envelope)

      post query_path, params: { params: { "latitude" => 40.7, "longitude" => -74.0 } },
           headers: auth_headers_for(querier), as: :json

      expect_success_response
      data = json_response_data
      expect(data["success"]).to be true
      expect(data["status"]).to eq("success")
      expect(data["data"]).to eq([{ "city" => "NYC", "temp" => "72" }])
      expect(data["provenance"]).to include("slug" => "open-meteo", "record_count" => 1)
      expect(data["bytes"]).to eq(42)
    end

    it "passes the data source, endpoint, caller params, and user into QueryService" do
      expect(Ai::DataSources::QueryService).to receive(:new).with(
        hash_including(
          data_source: data_source,
          endpoint: endpoint,
          params: hash_including("latitude" => 40.7)
        )
      ).and_return(instance_double(Ai::DataSources::QueryService, call: success_envelope))

      post query_path, params: { params: { "latitude" => 40.7 } },
           headers: auth_headers_for(querier), as: :json

      expect(response).to have_http_status(:success)
    end

    it "accepts an empty params body" do
      stub_query_service(success_envelope)

      post query_path, headers: auth_headers_for(querier), as: :json

      expect_success_response
    end
  end

  describe "POST .../query (failure envelopes map to HTTP statuses)" do
    it "maps a blocked (SSRF) envelope to 403 with provenance details" do
      stub_query_service(
        success_envelope.merge(
          success: false, status: "blocked", data: [],
          error: "request blocked by egress policy"
        )
      )

      post query_path, headers: auth_headers_for(querier), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json_response["success"]).to be false
      expect(json_response["error"]).to match(/egress policy/i)
      details = json_response["details"] || json_response.dig("data", "details")
      expect(details).to be_present
      expect(details["status"]).to eq("blocked")
    end

    it "maps a rate_limited envelope to 429" do
      stub_query_service(
        success_envelope.merge(success: false, status: "rate_limited", data: [],
                               error: "quota exceeded (requests_per_minute)")
      )

      post query_path, headers: auth_headers_for(querier), as: :json

      expect(response).to have_http_status(:too_many_requests)
      expect(json_response["success"]).to be false
    end

    it "maps a timeout envelope to 504" do
      stub_query_service(
        success_envelope.merge(success: false, status: "timeout", data: [], error: "request timed out")
      )

      post query_path, headers: auth_headers_for(querier), as: :json

      expect(response).to have_http_status(:gateway_timeout)
    end

    it "maps a generic error envelope to 502" do
      stub_query_service(
        success_envelope.merge(success: false, status: "error", data: [], error: "upstream returned HTTP 500")
      )

      post query_path, headers: auth_headers_for(querier), as: :json

      expect(response).to have_http_status(:bad_gateway)
    end
  end

  describe "authorization + scoping" do
    it "forbids a user without ai.data_sources.query" do
      reader = user_with_permissions("ai.data_sources.read", account: account)

      post query_path, headers: auth_headers_for(reader), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a user with no permissions at all" do
      post query_path, headers: auth_headers_for(user_without_permissions(account: account)), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "does not run the query for a source in another account" do
      other = create(:ai_data_source, account: create(:account), slug: "other")
      other_ep = create(:ai_data_source_endpoint, data_source: other, slug: "forecast")
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      post "/api/v1/ai/data_sources/#{other.id}/endpoints/#{other_ep.id}/query",
           headers: auth_headers_for(querier), as: :json

      expect_error_response("Data source not found", 404)
    end

    it "returns 404 when the endpoint does not belong to the source" do
      stranger = create(:ai_data_source_endpoint, data_source: create(:ai_data_source, account: account))

      post "/api/v1/ai/data_sources/#{data_source.id}/endpoints/#{stranger.id}/query",
           headers: auth_headers_for(querier), as: :json

      expect_error_response("Endpoint not found", 404)
    end

    include_examples "requires authentication", :post,
                     "/api/v1/ai/data_sources/placeholder/endpoints/placeholder/query"
  end

  # Parity with the agent path (Ai::Tools::DataSourceTool#guarded_fetch /
  # #write_endpoint?): a write/side-effecting endpoint needs the elevated
  # update/manage grant, not just the base query grant a read endpoint
  # requires — see Ai::DataSourceEndpoint#write_endpoint?.
  describe "write-endpoint gate (parity with the agent path)" do
    let!(:write_endpoint) do
      create(:ai_data_source_endpoint, :post, data_source: data_source, slug: "publish")
    end
    let(:write_query_path) { "/api/v1/ai/data_sources/#{data_source.id}/endpoints/#{write_endpoint.id}/query" }

    it "forbids a query-only user from executing a write endpoint" do
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      post write_query_path, headers: auth_headers_for(querier), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a write endpoint execution for a user with no permissions" do
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      post write_query_path, headers: auth_headers_for(user_without_permissions(account: account)), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "allows a user with ai.data_sources.update (no query grant) to execute a write endpoint" do
      stub_query_service(success_envelope)
      updater = user_with_permissions("ai.data_sources.update", account: account)

      post write_query_path, headers: auth_headers_for(updater), as: :json

      expect_success_response
    end

    it "allows a user with ai.data_sources.manage to execute a write endpoint" do
      stub_query_service(success_envelope)
      manager = user_with_permissions("ai.data_sources.manage", account: account)

      post write_query_path, headers: auth_headers_for(manager), as: :json

      expect_success_response
    end

    it "forbids a query-only user from executing a GET endpoint opted into metadata[side_effecting]" do
      side_effecting_get = create(:ai_data_source_endpoint, data_source: data_source, slug: "trigger",
                                   metadata: { "side_effecting" => true })
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      post "/api/v1/ai/data_sources/#{data_source.id}/endpoints/#{side_effecting_get.id}/query",
           headers: auth_headers_for(querier), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "still allows a read (GET, non-side-effecting) endpoint with only ai.data_sources.query" do
      stub_query_service(success_envelope)

      post query_path, headers: auth_headers_for(querier), as: :json

      expect_success_response
    end
  end
end
