# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaaS::TenantService, type: :service do
  let(:account) { create(:account) }

  describe "#create_tenant" do
    let(:service) { described_class.new(account: account) }
    let(:params) { { name: "Test Tenant", tier: "starter" } }

    it "creates a new tenant" do
      result = service.create_tenant(params)

      expect(result[:success]).to be true
      expect(result[:tenant]).to be_a(BaaS::Tenant)
      expect(result[:tenant].name).to eq("Test Tenant")
      expect(result[:tenant].tier).to eq("starter")
      expect(result[:tenant].status).to eq("active")
    end

    it "requires an account" do
      service = described_class.new(account: nil)
      result = service.create_tenant(params)

      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    end

    it "prevents duplicate active tenants for same account" do
      service.create_tenant(params)
      result = service.create_tenant(params.merge(name: "Another Tenant"))

      expect(result[:success]).to be false
      expect(result[:error]).to include("already has an active tenant")
    end
  end

  describe "#update_tenant" do
    let(:tenant) { create(:baas_tenant, account: account, name: "Original Name") }
    let(:service) { described_class.new(tenant: tenant) }

    it "updates tenant attributes" do
      result = service.update_tenant(name: "Updated Name")

      expect(result[:success]).to be true
      expect(result[:tenant].name).to eq("Updated Name")
    end

    it "returns error when tenant not found" do
      service = described_class.new(tenant: nil)
      result = service.update_tenant(name: "New Name")

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Tenant not found")
    end
  end

  describe "#change_tier" do
    let(:tenant) { create(:baas_tenant, account: account, tier: "starter") }
    let(:service) { described_class.new(tenant: tenant) }

    it "changes to a valid tier" do
      result = service.change_tier("pro")

      expect(result[:success]).to be true
      expect(result[:tenant].tier).to eq("pro")
      expect(result[:old_tier]).to eq("starter")
      expect(result[:new_tier]).to eq("pro")
    end

    it "rejects invalid tier" do
      result = service.change_tier("invalid")

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Invalid tier")
    end
  end

  describe "#suspend_tenant" do
    let(:tenant) { create(:baas_tenant, account: account, status: "active") }
    let(:service) { described_class.new(tenant: tenant) }

    it "suspends the tenant" do
      result = service.suspend_tenant(reason: "Non-payment")

      expect(result[:success]).to be true
      expect(result[:tenant].status).to eq("suspended")
    end

    it "returns error when already suspended" do
      tenant.update!(status: "suspended")
      result = service.suspend_tenant

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Tenant already suspended")
    end
  end

  describe "#reactivate_tenant" do
    let(:tenant) { create(:baas_tenant, account: account, status: "suspended") }
    let(:service) { described_class.new(tenant: tenant) }

    it "reactivates the tenant" do
      result = service.reactivate_tenant

      expect(result[:success]).to be true
      expect(result[:tenant].status).to eq("active")
    end

    it "returns error when not suspended" do
      tenant.update!(status: "active")
      result = service.reactivate_tenant

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Tenant not suspended")
    end
  end

  describe "#terminate_tenant" do
    let(:tenant) { create(:baas_tenant, account: account, status: "active") }
    let(:service) { described_class.new(tenant: tenant) }

    before do
      create(:baas_api_key, baas_tenant: tenant, status: "active")
    end

    it "terminates the tenant" do
      result = service.terminate_tenant

      expect(result[:success]).to be true
      expect(result[:tenant].status).to eq("terminated")
    end

    it "revokes all API keys" do
      service.terminate_tenant
      tenant.reload

      expect(tenant.api_keys.pluck(:status).uniq).to eq([ "revoked" ])
    end
  end

  describe "#dashboard_stats" do
    let(:tenant) { create(:baas_tenant, account: account) }
    let(:service) { described_class.new(tenant: tenant) }

    before do
      customer = create(:baas_customer, baas_tenant: tenant)
      create(:baas_subscription, baas_tenant: tenant, baas_customer: customer, status: "active")
      invoice = create(:baas_invoice, baas_tenant: tenant, baas_customer: customer, total_cents: 10000)
      invoice.update!(status: "open")
      invoice.mark_paid!
    end

    it "returns dashboard statistics" do
      result = service.dashboard_stats

      expect(result[:success]).to be true
      expect(result[:stats][:overview]).to be_present
      expect(result[:stats][:limits]).to be_present
      expect(result[:stats][:recent_activity]).to be_present
    end

    it "includes tier information" do
      result = service.dashboard_stats

      expect(result[:stats][:limits][:tier]).to eq(tenant.tier)
    end
  end

  describe "#check_rate_limits" do
    let(:tenant) { create(:baas_tenant, account: account, tier: "starter") }
    let(:service) { described_class.new(tenant: tenant) }

    it "returns rate limit status" do
      result = service.check_rate_limits

      expect(result).to have_key(:can_create_customer)
      expect(result).to have_key(:can_create_subscription)
      expect(result).to have_key(:can_make_api_request)
    end
  end
end
