# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::BaaS::V1::Subscriptions", type: :request do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }
  let(:service) { BaaS::ApiKeyService.new(tenant: tenant) }
  let(:api_key_result) { service.create_key(name: "Test Key", environment: "development") }
  let(:raw_key) { api_key_result[:raw_key] }
  let(:customer) { create(:baas_customer, baas_tenant: tenant) }

  let(:headers) do
    {
      "Authorization" => "Bearer #{raw_key}",
      "Content-Type" => "application/json"
    }
  end

  describe "GET /api/baas/v1/subscriptions" do
    let!(:subscriptions) { create_list(:baas_subscription, 3, baas_tenant: tenant, baas_customer: customer) }

    it "returns list of subscriptions" do
      get "/api/baas/v1/subscriptions", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"].count).to eq(3)
    end

    it "filters by status" do
      create(:baas_subscription, :canceled, baas_tenant: tenant, baas_customer: customer)

      get "/api/baas/v1/subscriptions", params: { status: "active" }, headers: headers

      expect(response).to have_http_status(:ok)
      json_response["data"].each do |sub|
        expect(sub["status"]).to eq("active")
      end
    end

    it "filters by customer_id" do
      other_customer = create(:baas_customer, baas_tenant: tenant)
      create(:baas_subscription, baas_tenant: tenant, baas_customer: other_customer)

      get "/api/baas/v1/subscriptions", params: { customer_id: customer.external_id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"].count).to eq(3)
    end
  end

  describe "GET /api/baas/v1/subscriptions/:id" do
    let(:subscription) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer) }

    it "returns the subscription" do
      get "/api/baas/v1/subscriptions/#{subscription.external_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["external_id"]).to eq(subscription.external_id)
    end

    it "returns 404 for non-existent subscription" do
      get "/api/baas/v1/subscriptions/nonexistent", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/baas/v1/subscriptions" do
    let(:valid_params) do
      {
        customer_id: customer.external_id,
        plan_id: "plan_pro",
        unit_amount: 9900,
        billing_interval: "month",
        trial_days: 0
      }
    end

    it "creates a new subscription" do
      expect {
        post "/api/baas/v1/subscriptions", params: valid_params.to_json, headers: headers
      }.to change { tenant.subscriptions.count }.by(1)

      expect(response).to have_http_status(:created)
    end

    it "creates trialing subscription with trial_days" do
      post "/api/baas/v1/subscriptions",
        params: valid_params.merge(trial_days: 14).to_json,
        headers: headers

      expect(response).to have_http_status(:created)
    end

    it "returns 422 for invalid params" do
      post "/api/baas/v1/subscriptions", params: { customer_id: customer.external_id }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/baas/v1/subscriptions/:id" do
    let(:subscription) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer) }

    it "updates the subscription" do
      patch "/api/baas/v1/subscriptions/#{subscription.external_id}",
        params: { quantity: 5 }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/baas/v1/subscriptions/:id/cancel" do
    let(:subscription) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer) }

    it "cancels immediately" do
      post "/api/baas/v1/subscriptions/#{subscription.external_id}/cancel",
        params: { at_period_end: false }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["status"]).to eq("canceled")
    end

    it "cancels at period end" do
      post "/api/baas/v1/subscriptions/#{subscription.external_id}/cancel",
        params: { at_period_end: true }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["cancel_at_period_end"]).to be true
    end
  end

  describe "POST /api/baas/v1/subscriptions/:id/pause" do
    let(:subscription) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer) }

    it "pauses the subscription" do
      post "/api/baas/v1/subscriptions/#{subscription.external_id}/pause", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["status"]).to eq("paused")
    end
  end

  describe "POST /api/baas/v1/subscriptions/:id/resume" do
    let(:subscription) { create(:baas_subscription, :paused, baas_tenant: tenant, baas_customer: customer) }

    it "resumes the subscription" do
      post "/api/baas/v1/subscriptions/#{subscription.external_id}/resume", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["status"]).to eq("active")
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
