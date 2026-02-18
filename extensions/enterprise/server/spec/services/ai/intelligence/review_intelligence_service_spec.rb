# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Intelligence::ReviewIntelligenceService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  describe '#sentiment_analysis' do
    context 'with missing review' do
      it 'returns error' do
        result = service.sentiment_analysis(review_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")
      end
    end

    context 'when error occurs' do
      before do
        allow(MarketplaceReview).to receive(:where).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.sentiment_analysis(review_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe '#spam_detection' do
    context 'with no reviews' do
      it 'returns success with empty results' do
        result = service.spam_detection
        expect(result[:success]).to be true
        expect(result[:flagged_reviews]).to be_empty
        expect(result[:total_scanned]).to eq(0)
        expect(result[:spam_rate]).to eq(0)
      end
    end

    context 'when error occurs' do
      before do
        allow(MarketplaceReview).to receive(:where).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.spam_detection
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe '#generate_response' do
    context 'with missing review' do
      it 'returns error' do
        result = service.generate_response(review_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")
      end
    end

    context 'when error occurs' do
      before do
        allow(MarketplaceReview).to receive(:where).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.generate_response(review_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe '#agent_quality_assessment' do
    context 'with no ratings' do
      it 'returns success with empty assessments' do
        result = service.agent_quality_assessment
        expect(result[:success]).to be true
        expect(result[:assessments]).to be_empty
        expect(result[:total_agents]).to eq(0)
      end
    end

    context 'when error occurs' do
      before do
        allow(CommunityAgentRating).to receive(:joins).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.agent_quality_assessment
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end
end
