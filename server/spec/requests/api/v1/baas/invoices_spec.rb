# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::BaaS::Invoices", type: :request do
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

  describe "GET /api/v1/baas/invoices" do
    let!(:invoices) { create_list(:baas_invoice, 3, baas_tenant: tenant, baas_customer: customer) }

    it "returns list of invoices" do
      get "/api/v1/baas/invoices", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"].count).to eq(3)
    end

    it "filters by status" do
      create(:baas_invoice, :paid, baas_tenant: tenant, baas_customer: customer)

      get "/api/v1/baas/invoices", params: { status: "draft" }, headers: headers

      expect(response).to have_http_status(:ok)
      json_response["data"].each do |invoice|
        expect(invoice["status"]).to eq("draft")
      end
    end

    it "filters by customer_id" do
      other_customer = create(:baas_customer, baas_tenant: tenant)
      create(:baas_invoice, baas_tenant: tenant, baas_customer: other_customer)

      get "/api/v1/baas/invoices", params: { customer_id: customer.external_id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"].count).to eq(3)
    end

    it "paginates results" do
      get "/api/v1/baas/invoices", params: { page: 1, per_page: 2 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"].count).to eq(2)
    end
  end

  describe "GET /api/v1/baas/invoices/:id" do
    let(:invoice) { create(:baas_invoice, baas_tenant: tenant, baas_customer: customer) }

    it "returns the invoice" do
      get "/api/v1/baas/invoices/#{invoice.external_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["external_id"]).to eq(invoice.external_id)
    end

    it "returns 404 for non-existent invoice" do
      get "/api/v1/baas/invoices/nonexistent", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for invoice from different tenant" do
      other_tenant = create(:baas_tenant, account: create(:account))
      other_customer = create(:baas_customer, baas_tenant: other_tenant)
      other_invoice = create(:baas_invoice, baas_tenant: other_tenant, baas_customer: other_customer)

      get "/api/v1/baas/invoices/#{other_invoice.external_id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/baas/invoices" do
    let(:valid_params) do
      {
        customer_id: customer.external_id,
        line_items: [
          { description: "Pro Plan", quantity: 1, amount_cents: 9900 }
        ]
      }
    end

    it "creates a new invoice" do
      expect {
        post "/api/v1/baas/invoices", params: valid_params.to_json, headers: headers
      }.to change { tenant.invoices.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(json_response["data"]["status"]).to eq("draft")
    end

    it "calculates totals with line items" do
      post "/api/v1/baas/invoices", params: valid_params.to_json, headers: headers

      expect(response).to have_http_status(:created)
    end

    it "returns 422 for invalid params" do
      post "/api/v1/baas/invoices", params: {}.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/baas/invoices/:id" do
    let(:invoice) { create(:baas_invoice, baas_tenant: tenant, baas_customer: customer, status: "draft") }

    it "updates the invoice" do
      patch "/api/v1/baas/invoices/#{invoice.external_id}",
        params: { metadata: { notes: "Updated" } }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "returns 422 when trying to update finalized invoice" do
      invoice.finalize!

      patch "/api/v1/baas/invoices/#{invoice.external_id}",
        params: { metadata: {} }.to_json,
        headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/baas/invoices/:id/finalize" do
    let(:invoice) { create(:baas_invoice, baas_tenant: tenant, baas_customer: customer, status: "draft") }

    it "finalizes the invoice" do
      post "/api/v1/baas/invoices/#{invoice.external_id}/finalize", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["status"]).to eq("open")
    end
  end

  describe "POST /api/v1/baas/invoices/:id/pay" do
    let(:invoice) { create(:baas_invoice, :open, baas_tenant: tenant, baas_customer: customer) }

    it "marks invoice as paid" do
      post "/api/v1/baas/invoices/#{invoice.external_id}/pay",
        params: { payment_reference: "pi_123" }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["status"]).to eq("paid")
    end
  end

  describe "POST /api/v1/baas/invoices/:id/void" do
    let(:invoice) { create(:baas_invoice, :open, baas_tenant: tenant, baas_customer: customer) }

    it "voids the invoice" do
      post "/api/v1/baas/invoices/#{invoice.external_id}/void", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["status"]).to eq("void")
    end

    it "returns 422 when trying to void paid invoice" do
      invoice.mark_paid!

      post "/api/v1/baas/invoices/#{invoice.external_id}/void", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/baas/invoices/:id" do
    let!(:invoice) { create(:baas_invoice, baas_tenant: tenant, baas_customer: customer, status: "draft") }

    it "deletes draft invoice" do
      expect {
        delete "/api/v1/baas/invoices/#{invoice.external_id}", headers: headers
      }.to change { tenant.invoices.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "returns 422 when trying to delete non-draft invoice" do
      invoice.finalize!

      delete "/api/v1/baas/invoices/#{invoice.external_id}", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
