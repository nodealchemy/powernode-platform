# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Intelligence::NotificationIntelligenceService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  describe '#smart_routing' do
    context 'with missing notification' do
      it 'returns error' do
        result = service.smart_routing(notification_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")
      end
    end

    context 'when error occurs' do
      before do
        allow(Notification).to receive(:where).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.smart_routing(notification_id: SecureRandom.uuid)
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe '#fatigue_analysis' do
    context 'with no users' do
      it 'returns success with empty analyses' do
        result = service.fatigue_analysis
        expect(result[:success]).to be true
        expect(result[:analyses]).to be_empty
        expect(result[:summary][:total_users]).to eq(0)
      end
    end

    context 'when error occurs' do
      before do
        allow(Notification).to receive(:where).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.fatigue_analysis
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end

  describe '#digest_recommendations' do
    context 'with no users' do
      it 'returns success with empty recommendations' do
        result = service.digest_recommendations
        expect(result[:success]).to be true
        expect(result[:recommendations]).to be_empty
        expect(result[:total_candidates]).to eq(0)
      end
    end

    context 'when error occurs' do
      before do
        allow(account).to receive(:users).and_raise(StandardError, "DB error")
      end

      it 'returns error response' do
        result = service.digest_recommendations
        expect(result[:success]).to be false
        expect(result[:error]).to include("DB error")
      end
    end
  end
end
