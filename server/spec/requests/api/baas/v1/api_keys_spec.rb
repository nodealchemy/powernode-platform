# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::BaaS::V1::ApiKeys", type: :request do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }
  let(:service) { BaaS::ApiKeyService.new(tenant: tenant) }
  # Use an API key with api_keys scope for authentication
  let(:admin_key_result) { service.create_key(name: "Admin Key", environment: "development", scopes: ["api_keys"]) }
  let(:raw_key) { admin_key_result[:raw_key] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{raw_key}",
      "Content-Type" => "application/json"
    }
  end

  describe "GET /api/baas/v1/api_keys" do
    before do
      service.create_key(name: "Test Key 1", environment: "development")
      service.create_key(name: "Test Key 2", environment: "development")
      service.create_key(name: "Prod Key", environment: "production")
    end

    it "returns list of API keys" do
      get "/api/baas/v1/api_keys", headers: headers

      expect(response).to have_http_status(:ok)
      # Should include the admin key plus the 3 created in before block
      expect(json_response["data"].count).to be >= 3
    end

    it "filters by environment" do
      get "/api/baas/v1/api_keys", params: { environment: "development" }, headers: headers

      expect(response).to have_http_status(:ok)
      json_response["data"].each do |key|
        expect(key["environment"]).to eq("development")
      end
    end

    it "excludes key_hash from response" do
      get "/api/baas/v1/api_keys", headers: headers

      json_response["data"].each do |key|
        expect(key).not_to have_key("key_hash")
      end
    end
  end

  describe "GET /api/baas/v1/api_keys/:id" do
    let!(:api_key_result) { service.create_key(name: "Test Key", environment: "development") }
    let(:api_key) { api_key_result[:api_key] }

    it "returns the API key" do
      get "/api/baas/v1/api_keys/#{api_key.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["name"]).to eq("Test Key")
    end

    it "includes key_prefix for identification" do
      get "/api/baas/v1/api_keys/#{api_key.id}", headers: headers

      expect(json_response["data"]["key_prefix"]).to be_present
    end
  end

  describe "POST /api/baas/v1/api_keys" do
    let(:valid_params) do
      {
        name: "New API Key",
        environment: "development",
        scopes: ["read", "write"]
      }
    end

    it "creates a new API key" do
      # Access headers first to create admin key
      _ = headers
      initial_count = tenant.api_keys.count

      post "/api/baas/v1/api_keys", params: valid_params.to_json, headers: headers

      expect(tenant.api_keys.count).to eq(initial_count + 1)
      expect(response).to have_http_status(:created)
      expect(json_response["data"]["name"]).to eq("New API Key")
    end

    it "returns the raw key only once" do
      post "/api/baas/v1/api_keys", params: valid_params.to_json, headers: headers

      expect(json_response["data"]["raw_key"]).to be_present
      expect(json_response["data"]["raw_key"]).to start_with("sk_test_")
    end

    it "creates production key" do
      post "/api/baas/v1/api_keys",
        params: valid_params.merge(environment: "production").to_json,
        headers: headers

      expect(json_response["data"]["raw_key"]).to start_with("sk_live_")
    end

    it "returns 422 for invalid params" do
      post "/api/baas/v1/api_keys", params: { name: "" }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/baas/v1/api_keys/:id/roll" do
    let!(:api_key_result) { service.create_key(name: "Original Key", environment: "development") }
    let(:api_key) { api_key_result[:api_key] }

    it "rolls the API key" do
      post "/api/baas/v1/api_keys/#{api_key.id}/roll", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["raw_key"]).to be_present

      # Old key should be revoked
      expect(api_key.reload.revoked?).to be true
    end
  end

  describe "DELETE /api/baas/v1/api_keys/:id" do
    let!(:api_key_result) { service.create_key(name: "To Delete", environment: "development") }
    let(:api_key) { api_key_result[:api_key] }

    it "revokes the API key" do
      delete "/api/baas/v1/api_keys/#{api_key.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(api_key.reload.revoked?).to be true
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
