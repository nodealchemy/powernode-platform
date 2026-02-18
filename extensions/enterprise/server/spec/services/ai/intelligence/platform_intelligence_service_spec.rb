# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Intelligence::PlatformIntelligenceService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  let(:tenant) { create(:baas_tenant, account: account) }

  before do
    allow(Ai::ComplianceAuditEntry).to receive(:log!).and_return(true)
  end

  describe "inheritance" do
    it "inherits from BaseIntelligenceService" do
      expect(described_class.superclass).to eq(Ai::Intelligence::BaseIntelligenceService)
    end
  end

  # =========================================================================
  # BaaS Intelligence Methods
  # =========================================================================

  describe "#usage_anomalies" do
    context "with baseline and recent data" do
      before do
        5.times do
          create(:baas_usage_record, baas_tenant: tenant, quantity: 10, created_at: 3.days.ago)
        end
        create(:baas_usage_record, baas_tenant: tenant, quantity: 100, created_at: 1.hour.ago)
      end

      it "returns success" do
        result = service.usage_anomalies
        expect(result[:success]).to be true
        expect(result).to include(:anomalies, :analyzed_at)
      end

      it "filters by tenant_id" do
        result = service.usage_anomalies(tenant_id: tenant.id)
        expect(result[:success]).to be true
      end
    end

    context "with no data" do
      it "returns success with empty anomalies" do
        result = service.usage_anomalies
        expect(result[:success]).to be true
        expect(result[:anomalies]).to be_empty
      end
    end

    context "when error occurs" do
      before do
        allow(BaaS::UsageRecord).to receive(:joins).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.usage_anomalies
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe "#tenant_churn_prediction" do
    context "with active tenants and usage" do
      before do
        create(:baas_usage_record, baas_tenant: tenant, quantity: 50, created_at: 10.days.ago)
        create(:baas_usage_record, baas_tenant: tenant, quantity: 5, created_at: 45.days.ago)
      end

      it "returns predictions" do
        result = service.tenant_churn_prediction
        expect(result[:success]).to be true
        expect(result).to include(:predictions, :high_risk_count, :analyzed_at)
        expect(result[:predictions]).to be_an(Array)
      end
    end

    context "with no tenants" do
      it "returns empty predictions" do
        result = service.tenant_churn_prediction
        expect(result[:success]).to be true
        expect(result[:predictions]).to be_empty
      end
    end

    context "when error occurs" do
      before do
        allow(BaaS::Tenant).to receive(:where).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.tenant_churn_prediction
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe "#pricing_recommendations" do
    context "with active subscriptions" do
      let(:customer) { create(:baas_customer, baas_tenant: tenant) }
      let!(:subscription) { create(:baas_subscription, baas_tenant: tenant, baas_customer: customer) }

      before do
        create(:baas_usage_record, baas_tenant: tenant, quantity: 500, created_at: 10.days.ago)
      end

      it "returns recommendations" do
        result = service.pricing_recommendations
        expect(result[:success]).to be true
        expect(result).to include(:recommendations, :analyzed_at)
      end
    end

    context "when error occurs" do
      before do
        allow(BaaS::Subscription).to receive(:joins).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.pricing_recommendations
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe "#api_fraud_detection" do
    context "with API keys" do
      let!(:api_key) { create(:baas_api_key, baas_tenant: tenant, total_requests: 0) }

      it "returns success" do
        result = service.api_fraud_detection
        expect(result[:success]).to be true
        expect(result).to include(:suspicious_keys, :total_analyzed, :analyzed_at)
      end
    end

    context "with suspicious key" do
      let!(:suspicious_key) do
        create(:baas_api_key, baas_tenant: tenant, total_requests: 50_000, rate_limit_per_day: 10_000)
      end

      it "detects suspicious usage" do
        result = service.api_fraud_detection
        expect(result[:success]).to be true
        expect(result[:suspicious_keys]).not_to be_empty
      end
    end

    context "when error occurs" do
      before do
        allow(BaaS::ApiKey).to receive(:joins).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.api_fraud_detection
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  # =========================================================================
  # Reseller Intelligence Methods
  # =========================================================================

  describe "#performance_scores" do
    context "with no resellers" do
      it "returns success with empty scores" do
        result = service.performance_scores
        expect(result[:success]).to be true
        expect(result[:scores]).to be_empty
        expect(result[:total_resellers]).to eq(0)
      end
    end

    context "when error occurs" do
      before do
        allow(Reseller).to receive(:where).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.performance_scores
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe "#commission_optimization" do
    context "with no resellers" do
      it "returns success with empty recommendations" do
        result = service.commission_optimization
        expect(result[:success]).to be true
        expect(result[:recommendations]).to be_empty
      end
    end

    context "when error occurs" do
      before do
        allow(Reseller).to receive(:where).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.commission_optimization
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe "#referral_churn_risks" do
    context "with no referrals" do
      it "returns success with empty risks" do
        result = service.referral_churn_risks
        expect(result[:success]).to be true
        expect(result[:risks]).to be_empty
        expect(result[:total_referrals]).to eq(0)
      end
    end

    context "when error occurs" do
      before do
        allow(ResellerReferral).to receive(:joins).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.referral_churn_risks
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end
end
