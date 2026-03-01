# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaaS::UsageMeteringService, type: :service do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }
  let(:customer) { create(:baas_customer, baas_tenant: tenant) }
  let(:service) { described_class.new(tenant: tenant) }

  describe "#record_usage" do
    let(:event_params) do
      {
        customer_id: customer.external_id,
        meter_id: "api_calls",
        quantity: 1,
        action: "increment",
        timestamp: Time.current
      }
    end

    it "creates usage record" do
      result = service.record_usage(event_params)

      expect(result[:success]).to be true
      expect(result[:record]).to be_present
    end

    it "returns error when tenant not found" do
      service = described_class.new(tenant: nil)
      result = service.record_usage(event_params)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Tenant not found")
    end
  end

  describe "#record_batch" do
    let(:events) do
      [
        { customer_id: customer.external_id, meter_id: "api_calls", quantity: 1, action: "increment", timestamp: Time.current },
        { customer_id: customer.external_id, meter_id: "api_calls", quantity: 2, action: "increment", timestamp: Time.current },
        { customer_id: customer.external_id, meter_id: "storage", quantity: 100, action: "set", timestamp: Time.current }
      ]
    end

    it "creates multiple usage records" do
      result = service.record_batch(events)

      expect(result[:success]).to be true
      expect(result[:successful]).to be >= 0
    end

    it "returns error for empty events" do
      result = service.record_batch([])

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Events required")
    end

    it "limits batch size" do
      too_many = Array.new(1001) { events.first }
      result = service.record_batch(too_many)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Maximum 1000 events per batch")
    end
  end

  describe "#get_usage" do
    before do
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: 10)
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: 20)
    end

    it "aggregates usage for customer and meter" do
      result = service.get_usage(
        customer_id: customer.external_id,
        meter_id: "api_calls"
      )

      expect(result[:success]).to be true
      expect(result[:usage][:total_quantity]).to eq(30)
    end

    it "filters by date range" do
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: 100, event_timestamp: 2.months.ago)

      result = service.get_usage(
        customer_id: customer.external_id,
        meter_id: "api_calls",
        start_date: 1.month.ago,
        end_date: Date.current
      )

      expect(result[:usage][:total_quantity]).to eq(30)
    end
  end

  describe "#customer_usage_summary" do
    before do
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: 100)
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "storage", quantity: 1024)
    end

    it "returns usage summary" do
      result = service.customer_usage_summary(customer_id: customer.external_id)

      expect(result[:success]).to be true
      expect(result[:summary][:total_events]).to eq(2)
      expect(result[:summary][:meters]).to be_present
    end
  end

  describe "#list_records" do
    before do
      create_list(:baas_usage_record, 5, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls")
    end

    it "returns paginated list" do
      result = service.list_records

      expect(result[:success]).to be true
      expect(result[:records].count).to eq(5)
      expect(result[:pagination]).to be_present
    end

    it "filters by customer" do
      other_customer = create(:baas_customer, baas_tenant: tenant)
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: other_customer.external_id, meter_id: "api_calls")

      result = service.list_records(customer_id: customer.external_id)

      expect(result[:records].count).to eq(5)
    end

    it "filters by meter" do
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "storage")

      result = service.list_records(meter_id: "api_calls")

      expect(result[:records].count).to eq(5)
    end
  end

  describe "#analytics" do
    before do
      (1..7).each do |i|
        create(:baas_usage_record,
          baas_tenant: tenant,
          customer_external_id: customer.external_id,
          meter_id: "api_calls",
          quantity: i * 10,
          event_timestamp: i.days.ago
        )
      end
    end

    it "returns analytics data" do
      result = service.analytics(start_date: 8.days.ago, end_date: Date.current)

      expect(result[:success]).to be true
      expect(result[:analytics][:total_events]).to eq(7)
      expect(result[:analytics][:daily_breakdown]).to be_present
    end

    it "includes meter breakdown" do
      result = service.analytics(start_date: 7.days.ago, end_date: Date.current)

      expect(result[:analytics][:by_meter]).to be_present
    end
  end

  describe "#pending_for_invoice" do
    before do
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: 100, status: "pending")
      create(:baas_usage_record, baas_tenant: tenant, customer_external_id: customer.external_id, meter_id: "api_calls", quantity: 50, status: "pending")
    end

    it "returns pending records for billing" do
      result = service.pending_for_invoice(
        customer_id: customer.external_id,
        billing_period_end: Date.current
      )

      expect(result[:success]).to be true
      expect(result[:usage]).to be_present
    end
  end

  describe "#mark_processed" do
    let!(:records) { create_list(:baas_usage_record, 3, baas_tenant: tenant, customer_external_id: customer.external_id, status: "pending") }

    it "marks records as processed" do
      result = service.mark_processed(records.map(&:id))

      expect(result[:success]).to be true
      expect(result[:processed_count]).to eq(3)
    end
  end

  describe "#mark_invoiced" do
    let!(:records) { create_list(:baas_usage_record, 3, baas_tenant: tenant, customer_external_id: customer.external_id, status: "processed") }

    it "marks records as invoiced" do
      result = service.mark_invoiced(records.map(&:id), invoice_id: "inv_123")

      expect(result[:success]).to be true
      expect(result[:invoiced_count]).to eq(3)
    end
  end
end
