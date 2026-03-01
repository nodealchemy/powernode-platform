# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaaS::Invoice, type: :model do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }
  let(:customer) { create(:baas_customer, baas_tenant: tenant) }

  describe "associations" do
    it { is_expected.to belong_to(:baas_tenant).class_name("BaaS::Tenant") }
    it { is_expected.to belong_to(:baas_customer).class_name("BaaS::Customer") }
    it { is_expected.to belong_to(:baas_subscription).class_name("BaaS::Subscription").optional }
  end

  describe "validations" do
    subject { build(:baas_invoice, baas_tenant: tenant, baas_customer: customer) }

    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_uniqueness_of(:external_id).scoped_to(:baas_tenant_id) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[draft open paid void uncollectible]) }
  end

  describe "callbacks" do
    it "generates invoice number on create" do
      invoice = create(:baas_invoice, baas_tenant: tenant, baas_customer: customer)
      expect(invoice.number).to be_present
      expect(invoice.number).to match(/^INV-\d{6}$/)
    end
  end

  describe "#draft?" do
    it "returns true when status is draft" do
      invoice = build(:baas_invoice, status: "draft")
      expect(invoice.draft?).to be true
    end
  end

  describe "#open?" do
    it "returns true when status is open" do
      invoice = build(:baas_invoice, status: "open")
      expect(invoice.open?).to be true
    end
  end

  describe "#paid?" do
    it "returns true when status is paid" do
      invoice = build(:baas_invoice, status: "paid")
      expect(invoice.paid?).to be true
    end
  end

  describe "#overdue?" do
    it "returns true when open and past due date" do
      invoice = build(:baas_invoice, status: "open", due_date: 1.day.ago)
      expect(invoice.overdue?).to be true
    end

    it "returns false when before due date" do
      invoice = build(:baas_invoice, status: "open", due_date: 1.day.from_now)
      expect(invoice.overdue?).to be false
    end

    it "returns false when paid" do
      invoice = build(:baas_invoice, status: "paid", due_date: 1.day.ago)
      expect(invoice.overdue?).to be false
    end
  end

  describe "#finalize!" do
    let(:invoice) { create(:baas_invoice, baas_tenant: tenant, baas_customer: customer, status: "draft") }

    it "transitions from draft to open" do
      invoice.finalize!
      expect(invoice.status).to eq("open")
    end

    it "returns false when not draft" do
      invoice.update!(status: "open")
      expect(invoice.finalize!).to be false
    end
  end

  describe "#mark_paid!" do
    let(:invoice) { create(:baas_invoice, :open, baas_tenant: tenant, baas_customer: customer, total_cents: 10000) }

    it "sets status to paid" do
      invoice.mark_paid!
      expect(invoice.status).to eq("paid")
    end

    it "sets paid_at timestamp" do
      invoice.mark_paid!
      expect(invoice.paid_at).to be_present
    end

    it "updates amount_paid_cents and amount_due_cents" do
      invoice.mark_paid!
      expect(invoice.amount_paid_cents).to eq(10000)
      expect(invoice.amount_due_cents).to eq(0)
    end

    it "returns false when not open" do
      invoice.update!(status: "draft")
      expect(invoice.mark_paid!).to be false
    end
  end

  describe "#void!" do
    let(:invoice) { create(:baas_invoice, :open, baas_tenant: tenant, baas_customer: customer) }

    it "sets status to void" do
      invoice.void!(reason: "Test reason")
      expect(invoice.status).to eq("void")
    end

    it "sets voided_at timestamp" do
      invoice.void!(reason: "Test reason")
      expect(invoice.voided_at).to be_present
    end

    it "returns false when already paid" do
      invoice.update!(status: "paid")
      expect(invoice.void!).to be false
    end
  end

  describe "#add_line_item" do
    let(:invoice) { create(:baas_invoice, baas_tenant: tenant, baas_customer: customer, line_items: []) }

    it "adds a line item and recalculates totals" do
      invoice.add_line_item(description: "Test Item", amount_cents: 5000, quantity: 2)
      expect(invoice.line_items.size).to eq(1)
      expect(invoice.subtotal_cents).to eq(10000)
    end
  end

  describe "#subtotal" do
    it "returns subtotal_cents as dollars" do
      invoice = build(:baas_invoice, subtotal_cents: 10000)
      expect(invoice.subtotal).to eq(100.0)
    end
  end

  describe "#total" do
    it "returns total_cents as dollars" do
      invoice = build(:baas_invoice, total_cents: 10000)
      expect(invoice.total).to eq(100.0)
    end
  end

  describe "#amount_due" do
    it "returns amount_due_cents as dollars" do
      invoice = build(:baas_invoice, amount_due_cents: 10000)
      expect(invoice.amount_due).to eq(100.0)
    end
  end

  describe "#summary" do
    let(:invoice) { create(:baas_invoice, baas_tenant: tenant, baas_customer: customer) }

    it "returns summary hash" do
      summary = invoice.summary
      expect(summary).to include(:id, :external_id, :number, :customer_id, :status)
    end
  end

  describe "scopes" do
    let!(:draft_invoice) { create(:baas_invoice, baas_tenant: tenant, baas_customer: customer, status: "draft") }
    let!(:open_invoice) { create(:baas_invoice, baas_tenant: tenant, baas_customer: customer, status: "open") }
    let!(:paid_invoice) { create(:baas_invoice, :paid, baas_tenant: tenant, baas_customer: customer) }

    it "filters draft invoices" do
      expect(described_class.draft).to include(draft_invoice)
    end

    it "filters open invoices" do
      expect(described_class.open).to include(open_invoice)
    end

    it "filters paid invoices" do
      expect(described_class.paid).to include(paid_invoice)
    end

    it "filters unpaid invoices" do
      expect(described_class.unpaid).to include(open_invoice)
      expect(described_class.unpaid).not_to include(paid_invoice, draft_invoice)
    end
  end
end
