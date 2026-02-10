# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Intelligence::ResellerIntelligenceService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  describe '#performance_scores' do
    context 'with no resellers' do
      it 'returns success with empty scores' do
        result = service.performance_scores
        expect(result[:success]).to be true
        expect(result[:scores]).to be_empty
        expect(result[:total_resellers]).to eq(0)
      end
    end

    context 'when error occurs' do
      before do
        allow(Reseller).to receive(:where).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.performance_scores
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe '#commission_optimization' do
    context 'with no resellers' do
      it 'returns success with empty recommendations' do
        result = service.commission_optimization
        expect(result[:success]).to be true
        expect(result[:recommendations]).to be_empty
      end
    end

    context 'when error occurs' do
      before do
        allow(Reseller).to receive(:where).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.commission_optimization
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe '#referral_churn_risks' do
    context 'with no referrals' do
      it 'returns success with empty risks' do
        result = service.referral_churn_risks
        expect(result[:success]).to be true
        expect(result[:risks]).to be_empty
        expect(result[:total_referrals]).to eq(0)
      end
    end

    context 'when error occurs' do
      before do
        allow(ResellerReferral).to receive(:joins).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.referral_churn_risks
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end
end
