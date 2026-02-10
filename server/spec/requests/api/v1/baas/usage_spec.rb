# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::BaaS::Usage", type: :request do
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

  describe "POST /api/v1/baas/usage_events" do
    let(:valid_params) do
      {
        customer_id: customer.external_id,
        meter_id: "api_calls",
        quantity: 1,
        action: "increment"
      }
    end

    it "records a usage event" do
      expect {
        post "/api/v1/baas/usage_events", params: valid_params.to_json, headers: headers
      }.to change { tenant.usage_records.count }.by(1)

      expect(response).to have_http_status(:created)
    end

    it "handles idempotency key" do
      params_with_key = valid_params.merge(idempotency_key: "unique-123")

      post "/api/v1/baas/usage_events", params: params_with_key.to_json, headers: headers
      post "/api/v1/baas/usage_events", params: params_with_key.to_json, headers: headers

      expect(tenant.usage_records.count).to eq(1)
    end

    it "returns 422 for invalid params" do
      post "/api/v1/baas/usage_events", params: { meter_id: "" }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    context "batch events" do
      let(:batch_params) do
        {
          events: [
            { customer_id: customer.external_id, meter_id: "api_calls", quantity: 1, action: "increment" },
            { customer_id: customer.external_id, meter_id: "api_calls", quantity: 2, action: "increment" },
            { customer_id: customer.external_id, meter_id: "storage", quantity: 100, action: "set" }
          ]
        }
      end

      it "records multiple events" do
        expect {
          post "/api/v1/baas/usage_events/batch", params: batch_params.to_json, headers: headers
        }.to change { tenant.usage_records.count }.by(3)

        expect(response).to have_http_status(:created)
      end

      it "handles partial failures" do
        params = {
          events: [
            { customer_id: customer.external_id, meter_id: "api_calls", quantity: 1, action: "increment" },
            { customer_id: customer.external_id, meter_id: nil, quantity: 1, action: "increment" }
          ]
        }

        post "/api/v1/baas/usage_events/batch", params: params.to_json, headers: headers

        expect(response).to have_http_status(:multi_status)
      end
    end
  end

  describe "GET /api/v1/baas/usage" do
    before do
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: 10)
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: 20)
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "storage", quantity: 100)
    end

    it "returns usage records" do
      get "/api/v1/baas/usage", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"].count).to eq(3)
    end

    it "filters by meter_id" do
      get "/api/v1/baas/usage", params: { meter_id: "api_calls" }, headers: headers

      expect(response).to have_http_status(:ok)
      json_response["data"].each do |record|
        expect(record["meter_id"]).to eq("api_calls")
      end
    end

    it "filters by date range" do
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", event_timestamp: 2.months.ago)

      get "/api/v1/baas/usage",
        params: { start_date: 1.month.ago.iso8601, end_date: 1.day.from_now.iso8601 },
        headers: headers

      expect(response).to have_http_status(:ok)
      # 3 recent records should be in range (created around now), 1 old record (2 months ago) should be excluded
      expect(json_response["data"].count).to eq(3)
    end
  end

  describe "GET /api/v1/baas/usage/summary" do
    before do
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: 10)
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "storage", quantity: 100)
    end

    it "returns usage summary" do
      get "/api/v1/baas/usage/summary", params: { customer_id: customer.external_id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]).to be_present
    end
  end

  describe "GET /api/v1/baas/usage/analytics" do
    before do
      (1..7).each do |i|
        create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: i * 10, event_timestamp: i.days.ago)
      end
    end

    it "returns usage analytics" do
      get "/api/v1/baas/usage/analytics", params: { start_date: 8.days.ago.iso8601, end_date: Time.current.iso8601 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]).to be_present
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
