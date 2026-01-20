# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaaS::Customer, type: :model do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:baas_tenant).class_name("BaaS::Tenant") }
    it { is_expected.to have_many(:subscriptions).class_name("BaaS::Subscription").dependent(:destroy) }
    it { is_expected.to have_many(:invoices).class_name("BaaS::Invoice").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:baas_customer, baas_tenant: tenant) }

    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_uniqueness_of(:external_id).scoped_to(:baas_tenant_id) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active archived deleted]) }
  end

  describe "#active?" do
    it "returns true when status is active" do
      customer = build(:baas_customer, status: "active")
      expect(customer.active?).to be true
    end

    it "returns false when status is not active" do
      customer = build(:baas_customer, status: "archived")
      expect(customer.active?).to be false
    end
  end

  describe "#archived?" do
    it "returns true when status is archived" do
      customer = build(:baas_customer, status: "archived")
      expect(customer.archived?).to be true
    end
  end

  describe "#archive!" do
    let(:customer) { create(:baas_customer, baas_tenant: tenant, status: "active") }

    it "sets status to archived" do
      customer.archive!
      expect(customer.status).to eq("archived")
    end
  end

  describe "#reactivate!" do
    let(:customer) { create(:baas_customer, baas_tenant: tenant, status: "archived") }

    it "sets status to active" do
      customer.reactivate!
      expect(customer.status).to eq("active")
    end
  end

  describe "#has_active_subscriptions?" do
    let(:customer) { create(:baas_customer, baas_tenant: tenant) }

    it "returns true when has active subscriptions" do
      create(:baas_subscription, baas_tenant: tenant, baas_customer: customer, status: "active")
      expect(customer.has_active_subscriptions?).to be true
    end

    it "returns false when no active subscriptions" do
      expect(customer.has_active_subscriptions?).to be false
    end
  end

  describe "#total_spent" do
    let(:customer) { create(:baas_customer, baas_tenant: tenant) }

    it "calculates total from paid invoices" do
      create(:baas_invoice, :paid, baas_tenant: tenant, baas_customer: customer, total_cents: 10000)
      create(:baas_invoice, :paid, baas_tenant: tenant, baas_customer: customer, total_cents: 20000)
      create(:baas_invoice, baas_tenant: tenant, baas_customer: customer, total_cents: 5000) # draft

      expect(customer.total_spent).to eq(300.0)
    end
  end

  describe "#add_balance" do
    let(:customer) { create(:baas_customer, baas_tenant: tenant, balance_cents: 1000) }

    it "adds to balance" do
      customer.add_balance(500)
      expect(customer.balance_cents).to eq(1500)
    end
  end

  describe "#deduct_balance" do
    let(:customer) { create(:baas_customer, baas_tenant: tenant, balance_cents: 1000) }

    it "deducts from balance" do
      customer.deduct_balance(500)
      expect(customer.balance_cents).to eq(500)
    end

    it "does not go below zero" do
      customer.deduct_balance(1500)
      expect(customer.balance_cents).to eq(0)
    end
  end

  describe "#full_address" do
    it "returns combined address parts" do
      customer = build(:baas_customer,
        address_line1: "123 Main St",
        city: "San Francisco",
        state: "CA",
        postal_code: "94102",
        country: "US"
      )
      expect(customer.full_address).to eq("123 Main St, San Francisco, CA, 94102, US")
    end

    it "handles missing parts" do
      customer = build(:baas_customer, address_line1: "123 Main St", city: nil, state: nil)
      expect(customer.full_address).to eq("123 Main St")
    end
  end

  describe "#summary" do
    let(:customer) { create(:baas_customer, baas_tenant: tenant) }

    it "returns summary hash" do
      summary = customer.summary
      expect(summary).to include(:id, :external_id, :email, :name, :status)
    end
  end

  describe "scopes" do
    let!(:active_customer) { create(:baas_customer, baas_tenant: tenant, status: "active") }
    let!(:archived_customer) { create(:baas_customer, baas_tenant: tenant, status: "archived") }

    it "filters active customers" do
      expect(described_class.active).to include(active_customer)
      expect(described_class.active).not_to include(archived_customer)
    end

    it "filters archived customers" do
      expect(described_class.archived).to include(archived_customer)
      expect(described_class.archived).not_to include(active_customer)
    end
  end

  describe "callbacks" do
    it "increments tenant customer count on create" do
      expect { create(:baas_customer, baas_tenant: tenant) }
        .to change { tenant.reload.total_customers }.by(1)
    end

    it "decrements tenant customer count on destroy" do
      customer = create(:baas_customer, baas_tenant: tenant)
      expect { customer.destroy }
        .to change { tenant.reload.total_customers }.by(-1)
    end
  end
end
