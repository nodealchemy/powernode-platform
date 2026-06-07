# frozen_string_literal: true

require "rails_helper"

# Request specs for the nested data-source ENDPOINT CRUD surface, served by
# Api::V1::Ai::DataSourcesController via the Ai::DataSourceEndpoints concern:
#
#   GET    /api/v1/ai/data_sources/:data_source_id/endpoints
#   POST   /api/v1/ai/data_sources/:data_source_id/endpoints
#   PATCH  /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
#   DELETE /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
#
# Permission map (validate_permissions):
#   index            -> ai.data_sources.read
#   create/update/destroy -> ai.data_sources.update OR ai.data_sources.manage
#
# The controller resolves the parent source via ActiveRecord#find, so URLs use
# the source/endpoint UUIDs (not slugs).
RSpec.describe "Api::V1::Ai::DataSource Endpoints", type: :request do
  let(:account) { create(:account) }
  let(:reader) { user_with_permissions("ai.data_sources.read", account: account) }
  let(:editor) { user_with_permissions("ai.data_sources.read", "ai.data_sources.update", account: account) }

  let!(:data_source) { create(:ai_data_source, account: account, slug: "open-meteo") }
  let(:base_path) { "/api/v1/ai/data_sources/#{data_source.id}/endpoints" }

  describe "GET /endpoints (index)" do
    let!(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source, name: "Forecast", slug: "forecast") }

    it "lists endpoints for the source" do
      get base_path, headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["count"]).to eq(1)
      ep = data["items"].first
      expect(ep["slug"]).to eq("forecast")
      expect(ep).to include("http_method", "path_template", "response_format", "ai_data_source_id")
    end

    it "returns 404 for an unknown parent source" do
      get "/api/v1/ai/data_sources/#{SecureRandom.uuid}/endpoints",
          headers: auth_headers_for(reader), as: :json

      expect_error_response("Data source not found", 404)
    end

    it "does not expose endpoints under another account's source" do
      other = create(:ai_data_source, account: create(:account))
      create(:ai_data_source_endpoint, data_source: other)

      get "/api/v1/ai/data_sources/#{other.id}/endpoints",
          headers: auth_headers_for(reader), as: :json

      expect_error_response("Data source not found", 404)
    end

    include_examples "requires authentication", :get,
                     "/api/v1/ai/data_sources/placeholder/endpoints"

    it "forbids users without ai.data_sources.read" do
      get base_path, headers: auth_headers_for(user_without_permissions(account: account)), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /endpoints (create)" do
    let(:valid_params) do
      {
        endpoint: {
          name: "Forecast",
          http_method: "GET",
          path_template: "/v1/forecast",
          response_format: "json",
          expected_content_type: "application/json",
          cache_ttl_seconds: 300
        }
      }
    end

    it "creates an endpoint with update permission" do
      expect do
        post base_path, params: valid_params, headers: auth_headers_for(editor), as: :json
      end.to change { data_source.endpoints.count }.by(1)

      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data["endpoint"]["name"]).to eq("Forecast")
      expect(data["endpoint"]["slug"]).to eq("forecast") # auto-generated
    end

    it "allows the manage super-grant to create endpoints" do
      manager = user_with_permissions("ai.data_sources.manage", account: account)

      post base_path, params: valid_params, headers: auth_headers_for(manager), as: :json

      expect(response).to have_http_status(:created)
    end

    it "returns a validation error for an invalid http_method" do
      bad = { endpoint: { name: "Bad", http_method: "TELEPORT" } }

      post base_path, params: bad, headers: auth_headers_for(editor), as: :json

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
      expect(json_response["success"]).to be false
    end

    it "forbids a read-only user from creating endpoints" do
      post base_path, params: valid_params, headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    include_examples "requires authentication", :post,
                     "/api/v1/ai/data_sources/placeholder/endpoints"
  end

  describe "PATCH /endpoints/:endpoint_id (update)" do
    let!(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source, name: "Forecast", slug: "forecast") }
    let(:member_path) { "#{base_path}/#{endpoint.id}" }

    it "updates an endpoint with update permission" do
      patch member_path,
            params: { endpoint: { name: "Forecast v2", cache_ttl_seconds: 600 } },
            headers: auth_headers_for(editor), as: :json

      expect_success_response
      expect(endpoint.reload.name).to eq("Forecast v2")
      expect(endpoint.cache_ttl_seconds).to eq(600)
    end

    it "returns 404 for an unknown endpoint under the source" do
      patch "#{base_path}/#{SecureRandom.uuid}",
            params: { endpoint: { name: "x" } },
            headers: auth_headers_for(editor), as: :json

      expect_error_response("Endpoint not found", 404)
    end

    it "forbids a read-only user from updating" do
      patch member_path, params: { endpoint: { name: "Nope" } },
            headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(endpoint.reload.name).to eq("Forecast")
    end
  end

  describe "DELETE /endpoints/:endpoint_id (destroy)" do
    let!(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source, slug: "forecast") }
    let(:member_path) { "#{base_path}/#{endpoint.id}" }

    it "deletes an endpoint with update permission" do
      expect do
        delete member_path, headers: auth_headers_for(editor), as: :json
      end.to change { data_source.endpoints.count }.by(-1)

      expect_success_response
      expect(json_response_data["message"]).to match(/deleted/i)
    end

    it "forbids a read-only user from deleting" do
      delete member_path, headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Ai::DataSourceEndpoint.exists?(endpoint.id)).to be true
    end
  end
end
