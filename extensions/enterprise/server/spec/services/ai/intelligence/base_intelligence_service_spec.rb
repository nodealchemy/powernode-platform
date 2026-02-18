# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Intelligence::BaseIntelligenceService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  describe "#initialize" do
    it "sets the account" do
      expect(service.account).to eq(account)
    end
  end

  describe "protected helpers" do
    # Expose protected methods for testing
    let(:test_service) do
      Class.new(described_class) do
        public :calculate_trend, :calculate_percentile, :risk_score,
               :success_response, :error_response, :error_hash, :audit_action
      end.new(account: account)
    end

    describe "#calculate_trend" do
      it "returns percentage change" do
        expect(test_service.calculate_trend(150, 100)).to eq(50.0)
      end

      it "returns 0.0 when previous is zero" do
        expect(test_service.calculate_trend(100, 0)).to eq(0.0)
      end

      it "handles negative trends" do
        expect(test_service.calculate_trend(50, 100)).to eq(-50.0)
      end
    end

    describe "#calculate_percentile" do
      it "returns nil for empty values" do
        expect(test_service.calculate_percentile([], 50)).to be_nil
      end

      it "returns the median for 50th percentile" do
        expect(test_service.calculate_percentile([1, 2, 3, 4, 5], 50)).to eq(3)
      end

      it "returns the max for 100th percentile" do
        expect(test_service.calculate_percentile([1, 2, 3, 4, 5], 100)).to eq(5)
      end

      it "returns the min for 0th percentile" do
        expect(test_service.calculate_percentile([1, 2, 3, 4, 5], 0)).to eq(1)
      end
    end

    describe "#risk_score" do
      it "returns 0.0 for empty factors" do
        expect(test_service.risk_score([])).to eq(0.0)
      end

      it "calculates weighted average" do
        factors = [
          { weight: 0.6, score: 80 },
          { weight: 0.4, score: 60 }
        ]
        expected = ((0.6 * 80 + 0.4 * 60) / (0.6 + 0.4)).round(2)
        expect(test_service.risk_score(factors)).to eq(expected)
      end

      it "handles single factor" do
        factors = [{ weight: 1.0, score: 75 }]
        expect(test_service.risk_score(factors)).to eq(75.0)
      end
    end

    describe "#success_response" do
      it "returns hash with success: true" do
        result = test_service.success_response(data: "test")
        expect(result).to eq({ success: true, data: "test" })
      end

      it "returns just success: true with no data" do
        result = test_service.success_response
        expect(result).to eq({ success: true })
      end
    end

    describe "#error_response" do
      it "returns hash with success: false and error message" do
        exception = StandardError.new("something went wrong")
        allow(exception).to receive(:backtrace).and_return(["line1", "line2"])

        result = test_service.error_response("test_method", exception)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("something went wrong")
      end
    end

    describe "#error_hash" do
      it "returns hash with success: false and message" do
        result = test_service.error_hash("not found")
        expect(result).to eq({ success: false, error: "not found" })
      end
    end

    describe "#audit_action" do
      before do
        allow(Ai::ComplianceAuditEntry).to receive(:log!).and_return(true)
      end

      it "logs an audit entry" do
        expect(Ai::ComplianceAuditEntry).to receive(:log!).with(
          hash_including(
            account: account,
            action_type: "ai_intelligence_test_action",
            resource_type: "TestResource",
            outcome: "success"
          )
        )
        test_service.audit_action("test_action", "TestResource")
      end

      it "does not raise when audit logging fails" do
        allow(Ai::ComplianceAuditEntry).to receive(:log!).and_raise(StandardError, "audit failed")
        expect { test_service.audit_action("test_action", "TestResource") }.not_to raise_error
      end
    end
  end

  describe "inheritance" do
    it "is inherited by PlatformIntelligenceService" do
      expect(Ai::Intelligence::PlatformIntelligenceService.superclass).to eq(described_class)
    end

    it "is inherited by OpsIntelligenceService" do
      expect(Ai::Intelligence::OpsIntelligenceService.superclass).to eq(described_class)
    end

    it "is inherited by PipelineIntelligenceService" do
      expect(Ai::Intelligence::PipelineIntelligenceService.superclass).to eq(described_class)
    end

    it "is inherited by RevenueIntelligenceService" do
      expect(Ai::Intelligence::RevenueIntelligenceService.superclass).to eq(described_class)
    end

    it "is inherited by ReviewIntelligenceService" do
      expect(Ai::Intelligence::ReviewIntelligenceService.superclass).to eq(described_class)
    end

    it "is inherited by SupplyChainAnalysisService" do
      expect(Ai::Intelligence::SupplyChainAnalysisService.superclass).to eq(described_class)
    end
  end
end
