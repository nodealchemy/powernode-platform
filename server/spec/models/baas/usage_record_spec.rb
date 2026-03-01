# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaaS::UsageRecord, type: :model do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:baas_tenant).class_name("BaaS::Tenant") }
  end

  describe "validations" do
    subject { build(:baas_usage_record, baas_tenant: tenant) }

    it { is_expected.to validate_presence_of(:customer_external_id) }
    it { is_expected.to validate_presence_of(:meter_id) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_presence_of(:action) }
    it { is_expected.to validate_presence_of(:event_timestamp) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_inclusion_of(:action).in_array(%w[set increment]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending processed invoiced failed]) }
  end

  describe "idempotency" do
    it "validates uniqueness of idempotency_key" do
      create(:baas_usage_record, baas_tenant: tenant, idempotency_key: "unique-key-123")
      duplicate = build(:baas_usage_record, baas_tenant: tenant, idempotency_key: "unique-key-123")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:idempotency_key]).to include("has already been taken")
    end

    it "allows nil idempotency_key" do
      create(:baas_usage_record, baas_tenant: tenant, idempotency_key: nil)
      record = build(:baas_usage_record, baas_tenant: tenant, idempotency_key: nil)
      expect(record).to be_valid
    end
  end

  describe "#pending?" do
    it "returns true when status is pending" do
      record = build(:baas_usage_record, status: "pending")
      expect(record.pending?).to be true
    end
  end

  describe "#processed?" do
    it "returns true when status is processed" do
      record = build(:baas_usage_record, status: "processed")
      expect(record.processed?).to be true
    end
  end

  describe "#invoiced?" do
    it "returns true when status is invoiced" do
      record = build(:baas_usage_record, status: "invoiced")
      expect(record.invoiced?).to be true
    end
  end

  describe "#mark_processed!" do
    let(:record) { create(:baas_usage_record, baas_tenant: tenant, status: "pending") }

    it "sets status to processed" do
      record.mark_processed!
      expect(record.status).to eq("processed")
    end

    it "sets processed_at timestamp" do
      record.mark_processed!
      expect(record.processed_at).to be_present
    end
  end

  describe "#mark_invoiced!" do
    let(:record) { create(:baas_usage_record, baas_tenant: tenant, status: "processed") }

    it "sets status to invoiced" do
      record.mark_invoiced!("invoice-123")
      expect(record.status).to eq("invoiced")
      expect(record.invoice_id).to eq("invoice-123")
    end
  end

  describe "#mark_failed!" do
    let(:record) { create(:baas_usage_record, baas_tenant: tenant, status: "pending") }

    it "sets status to failed" do
      record.mark_failed!("Test error")
      expect(record.status).to eq("failed")
      expect(record.metadata["failure_reason"]).to eq("Test error")
    end
  end

  describe "#summary" do
    let(:record) { create(:baas_usage_record, baas_tenant: tenant) }

    it "returns summary hash" do
      summary = record.summary
      expect(summary).to include(:id, :customer_id, :meter_id, :quantity, :action, :status)
    end
  end

  describe "scopes" do
    let!(:pending_record) { create(:baas_usage_record, baas_tenant: tenant, status: "pending") }
    let!(:processed_record) { create(:baas_usage_record, baas_tenant: tenant, status: "processed") }
    let!(:invoiced_record) { create(:baas_usage_record, baas_tenant: tenant, status: "invoiced") }

    it "filters pending records" do
      expect(described_class.pending).to include(pending_record)
    end

    it "filters processed records" do
      expect(described_class.processed).to include(processed_record)
    end

    it "filters invoiced records" do
      expect(described_class.invoiced).to include(invoiced_record)
    end
  end

  describe ".for_customer" do
    let!(:record1) { create(:baas_usage_record, baas_tenant: tenant, customer_external_id: "cust_123") }
    let!(:record2) { create(:baas_usage_record, baas_tenant: tenant, customer_external_id: "cust_456") }

    it "filters by customer_external_id" do
      expect(described_class.for_customer("cust_123")).to include(record1)
      expect(described_class.for_customer("cust_123")).not_to include(record2)
    end
  end

  describe ".for_meter" do
    let!(:api_record) { create(:baas_usage_record, baas_tenant: tenant, meter_id: "api_calls") }
    let!(:storage_record) { create(:baas_usage_record, baas_tenant: tenant, meter_id: "storage") }

    it "filters by meter_id" do
      expect(described_class.for_meter("api_calls")).to include(api_record)
      expect(described_class.for_meter("api_calls")).not_to include(storage_record)
    end
  end

  describe ".for_period" do
    let!(:old_record) { create(:baas_usage_record, baas_tenant: tenant, event_timestamp: 2.months.ago) }
    let!(:recent_record) { create(:baas_usage_record, baas_tenant: tenant, event_timestamp: 1.day.ago) }

    it "filters by time range" do
      records = described_class.for_period(1.week.ago, Time.current)
      expect(records).to include(recent_record)
      expect(records).not_to include(old_record)
    end
  end

  describe "metadata" do
    it "stores and retrieves metadata as JSON" do
      record = create(:baas_usage_record, baas_tenant: tenant, metadata: { source: "api", version: "v2" })
      record.reload
      expect(record.metadata["source"]).to eq("api")
      expect(record.metadata["version"]).to eq("v2")
    end
  end
end
