# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Intelligence::OpsIntelligenceService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  describe "inheritance" do
    it "inherits from BaseIntelligenceService" do
      expect(described_class.superclass).to eq(Ai::Intelligence::BaseIntelligenceService)
    end
  end

  # =========================================================================
  # Monitoring Intelligence Methods
  # =========================================================================

  describe "#predictive_failure" do
    context "with no circuit breakers" do
      it "returns success with empty predictions" do
        result = service.predictive_failure
        expect(result[:success]).to be true
        expect(result[:predictions]).to be_empty
        expect(result[:overall_risk]).to eq("low")
        expect(result[:total_breakers]).to eq(0)
      end
    end

    it "accepts service_name filter" do
      result = service.predictive_failure(service_name: "api_gateway")
      expect(result[:success]).to be true
    end

    context "when error occurs" do
      before do
        allow(Monitoring::CircuitBreaker).to receive(:all).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.predictive_failure
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe "#self_healing_recommendations" do
    context "with no unhealthy breakers" do
      it "returns success with empty recommendations" do
        result = service.self_healing_recommendations
        expect(result[:success]).to be true
        expect(result[:recommendations]).to be_empty
        expect(result[:total_unhealthy]).to eq(0)
      end
    end

    context "when error occurs" do
      before do
        allow(Monitoring::CircuitBreaker).to receive(:all).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.self_healing_recommendations
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe "#sla_breach_risk" do
    context "with no breakers" do
      it "returns success with zero at-risk count" do
        result = service.sla_breach_risk
        expect(result[:success]).to be true
        expect(result[:services]).to be_empty
        expect(result[:at_risk_count]).to eq(0)
        expect(result[:period_hours]).to eq(24)
      end
    end

    context "when error occurs" do
      before do
        allow(Monitoring::CircuitBreaker).to receive(:all).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.sla_breach_risk
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  # =========================================================================
  # Notification Intelligence Methods
  # =========================================================================

  describe "#smart_routing" do
    context "with missing notification" do
      it "returns error" do
        result = service.smart_routing(notification_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")
      end
    end

    context "when error occurs" do
      before do
        allow(Notification).to receive(:where).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.smart_routing(notification_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe "#fatigue_analysis" do
    context "with no users" do
      it "returns success with empty analyses" do
        result = service.fatigue_analysis
        expect(result[:success]).to be true
        expect(result[:analyses]).to be_empty
        expect(result[:summary][:total_users]).to eq(0)
      end
    end

    context "when error occurs" do
      before do
        allow(Notification).to receive(:where).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.fatigue_analysis
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe "#digest_recommendations" do
    context "with no users" do
      it "returns success with empty recommendations" do
        result = service.digest_recommendations
        expect(result[:success]).to be true
        expect(result[:recommendations]).to be_empty
        expect(result[:total_candidates]).to eq(0)
      end
    end

    context "when error occurs" do
      before do
        allow(account).to receive(:users).and_raise(StandardError, "DB error")
      end

      it "returns error response" do
        result = service.digest_recommendations
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end
end
