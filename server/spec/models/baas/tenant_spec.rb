# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaaS::Tenant, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_one(:billing_configuration).class_name("BaaS::BillingConfiguration").with_foreign_key(:baas_tenant_id).dependent(:destroy) }
    it { is_expected.to have_many(:api_keys).class_name("BaaS::ApiKey").with_foreign_key(:baas_tenant_id).dependent(:destroy) }
    it { is_expected.to have_many(:usage_records).class_name("BaaS::UsageRecord").with_foreign_key(:baas_tenant_id).dependent(:destroy) }
    it { is_expected.to have_many(:customers).class_name("BaaS::Customer").with_foreign_key(:baas_tenant_id).dependent(:destroy) }
    it { is_expected.to have_many(:subscriptions).class_name("BaaS::Subscription").with_foreign_key(:baas_tenant_id).dependent(:destroy) }
    it { is_expected.to have_many(:invoices).class_name("BaaS::Invoice").with_foreign_key(:baas_tenant_id).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:baas_tenant, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:tier) }
    it { is_expected.to validate_presence_of(:environment) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending active suspended terminated]) }
    it { is_expected.to validate_inclusion_of(:tier).in_array(%w[free starter pro business]) }
    it { is_expected.to validate_inclusion_of(:environment).in_array(%w[development staging production]) }
  end

  describe "callbacks" do
    it "generates slug from name" do
      tenant = create(:baas_tenant, account: account, name: "My Test Tenant")
      expect(tenant.slug).to eq("my-test-tenant")
    end

    it "creates billing configuration after create" do
      tenant = create(:baas_tenant, account: account)
      expect(tenant.billing_configuration).to be_present
    end
  end

  describe "#active?" do
    it "returns true when status is active" do
      tenant = build(:baas_tenant, status: "active")
      expect(tenant.active?).to be true
    end

    it "returns false when status is not active" do
      tenant = build(:baas_tenant, status: "suspended")
      expect(tenant.active?).to be false
    end
  end

  describe "#suspended?" do
    it "returns true when status is suspended" do
      tenant = build(:baas_tenant, status: "suspended")
      expect(tenant.suspended?).to be true
    end
  end

  describe "tier limits" do
    describe "#can_create_customer?" do
      it "returns true for business tier" do
        tenant = build(:baas_tenant, tier: "business")
        expect(tenant.can_create_customer?).to be true
      end

      it "returns true when under limit" do
        tenant = build(:baas_tenant, tier: "starter", total_customers: 50, max_customers: 100)
        expect(tenant.can_create_customer?).to be true
      end

      it "returns false when at limit" do
        tenant = build(:baas_tenant, tier: "starter", total_customers: 100, max_customers: 100)
        expect(tenant.can_create_customer?).to be false
      end
    end

    describe "#can_create_subscription?" do
      it "returns true for business tier" do
        tenant = build(:baas_tenant, tier: "business")
        expect(tenant.can_create_subscription?).to be true
      end

      it "returns true when under limit" do
        tenant = build(:baas_tenant, tier: "starter", total_subscriptions: 250, max_subscriptions: 500)
        expect(tenant.can_create_subscription?).to be true
      end

      it "returns false when at limit" do
        tenant = build(:baas_tenant, tier: "starter", total_subscriptions: 500, max_subscriptions: 500)
        expect(tenant.can_create_subscription?).to be false
      end
    end
  end

  describe "#apply_tier_limits!" do
    it "applies tier limits for starter tier" do
      tenant = create(:baas_tenant, account: account, tier: "starter")
      tenant.apply_tier_limits!

      expect(tenant.max_customers).to eq(100)
      expect(tenant.max_subscriptions).to eq(500)
      expect(tenant.max_api_requests_per_day).to eq(10_000)
    end

    it "applies nil limits for business tier" do
      tenant = create(:baas_tenant, account: account, tier: "business")
      tenant.apply_tier_limits!

      expect(tenant.max_customers).to be_nil
      expect(tenant.max_subscriptions).to be_nil
    end
  end

  describe "#record_api_request!" do
    let(:tenant) { create(:baas_tenant, account: account) }

    it "increments api_requests_today counter" do
      expect { tenant.record_api_request! }
        .to change { tenant.reload.api_requests_today }.by(1)
    end
  end

  describe "#increment_customer_count!" do
    let(:tenant) { create(:baas_tenant, account: account) }

    it "increments total_customers counter" do
      expect { tenant.increment_customer_count! }
        .to change { tenant.reload.total_customers }.by(1)
    end
  end

  describe "#increment_subscription_count!" do
    let(:tenant) { create(:baas_tenant, account: account) }

    it "increments total_subscriptions counter" do
      expect { tenant.increment_subscription_count! }
        .to change { tenant.reload.total_subscriptions }.by(1)
    end
  end

  describe "#record_revenue" do
    let(:tenant) { create(:baas_tenant, account: account) }

    it "adds to total_revenue_processed" do
      expect { tenant.record_revenue(100.00) }
        .to change { tenant.reload.total_revenue_processed }.by(100.00)
    end
  end

  describe "#summary" do
    let(:tenant) { create(:baas_tenant, account: account) }

    it "returns tenant summary hash" do
      summary = tenant.summary

      expect(summary).to include(:id, :name, :slug, :status, :tier, :environment)
      expect(summary[:name]).to eq(tenant.name)
    end
  end

  describe "scopes" do
    let!(:active_tenant) { create(:baas_tenant, account: account, status: "active") }
    let!(:suspended_tenant) { create(:baas_tenant, account: create(:account), status: "suspended") }

    it "filters by active status" do
      expect(described_class.active).to include(active_tenant)
      expect(described_class.active).not_to include(suspended_tenant)
    end

    it "filters by tier" do
      expect(described_class.by_tier("starter")).to include(active_tenant)
    end
  end
end
