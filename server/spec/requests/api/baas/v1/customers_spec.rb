# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::BaaS::V1::Customers", type: :request do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }
  let(:service) { BaaS::ApiKeyService.new(tenant: tenant) }
  let(:api_key_result) { service.create_key(name: "Test Key", environment: "development") }
  let(:raw_key) { api_key_result[:raw_key] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{raw_key}",
      "Content-Type" => "application/json"
    }
  end

  describe "GET /api/baas/v1/customers" do
    let!(:customers) { create_list(:baas_customer, 3, baas_tenant: tenant) }

    it "returns list of customers" do
      get "/api/baas/v1/customers", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"].count).to eq(3)
    end

    it "paginates results" do
      get "/api/baas/v1/customers", params: { page: 1, per_page: 2 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"].count).to eq(2)
    end

    it "returns 401 without API key" do
      get "/api/baas/v1/customers"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with invalid API key" do
      get "/api/baas/v1/customers", headers: { "Authorization" => "Bearer invalid" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/baas/v1/customers/:id" do
    let(:customer) { create(:baas_customer, baas_tenant: tenant) }

    it "returns the customer" do
      get "/api/baas/v1/customers/#{customer.external_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["external_id"]).to eq(customer.external_id)
    end

    it "returns 404 for non-existent customer" do
      get "/api/baas/v1/customers/nonexistent", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for customer from different tenant" do
      other_tenant = create(:baas_tenant, account: create(:account))
      other_customer = create(:baas_customer, baas_tenant: other_tenant)

      get "/api/baas/v1/customers/#{other_customer.external_id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/baas/v1/customers" do
    let(:valid_params) do
      {
        email: "newcustomer@example.com",
        name: "John Doe",
        metadata: { company: "Acme" }
      }
    end

    it "creates a new customer" do
      expect {
        post "/api/baas/v1/customers", params: valid_params.to_json, headers: headers
      }.to change { tenant.customers.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["email"]).to eq("newcustomer@example.com")
    end

    it "creates customer with auto-generated external_id when no params provided" do
      expect {
        post "/api/baas/v1/customers", params: {}.to_json, headers: headers
      }.to change { tenant.customers.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["external_id"]).to be_present
    end

    it "returns 422 for duplicate external_id" do
      create(:baas_customer, baas_tenant: tenant, external_id: "existing-id")

      post "/api/baas/v1/customers", params: { external_id: "existing-id" }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/baas/v1/customers/:id" do
    let(:customer) { create(:baas_customer, baas_tenant: tenant) }

    it "updates the customer" do
      patch "/api/baas/v1/customers/#{customer.external_id}",
        params: { name: "Jane Doe" }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["name"]).to eq("Jane Doe")
    end
  end

  describe "DELETE /api/baas/v1/customers/:id" do
    let!(:customer) { create(:baas_customer, baas_tenant: tenant) }

    it "archives the customer" do
      delete "/api/baas/v1/customers/#{customer.external_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(customer.reload.status).to eq("archived")
    end

    it "returns 422 when customer has active subscription" do
      create(:baas_subscription, baas_tenant: tenant, baas_customer: customer, status: "active")

      delete "/api/baas/v1/customers/#{customer.external_id}", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
