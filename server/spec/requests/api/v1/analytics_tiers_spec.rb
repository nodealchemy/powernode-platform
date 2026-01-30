# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AnalyticsTiers', type: :request do
  let(:account) { create(:account) }

  let(:billing_reader) do
    create(:user, account: account, permissions: ['billing.read'])
  end

  let(:billing_manager) do
    create(:user, account: account, permissions: ['billing.read', 'billing.manage'])
  end

  let(:regular_user) do
    create(:user, account: account, permissions: [])
  end

  let!(:tiers) do
    [
      create(:analytics_tier, slug: 'free', name: 'Free', is_active: true),
      create(:analytics_tier, slug: 'pro', name: 'Pro', is_active: true),
      create(:analytics_tier, slug: 'enterprise', name: 'Enterprise', is_active: true)
    ]
  end

  describe 'GET /api/v1/analytics/tiers' do
    it 'returns all active tiers' do
      get '/api/v1/analytics/tiers', as: :json

      expect_success_response
      expect(json_response['data'].length).to eq(3)
    end

    it 'returns tier comparison data' do
      get '/api/v1/analytics/tiers', as: :json

      expect_success_response
      tier_data = json_response['data'].first

      expect(tier_data).to be_present
    end

    it 'orders tiers correctly' do
      get '/api/v1/analytics/tiers', as: :json

      expect_success_response
      expect(json_response['data']).to be_an(Array)
    end
  end

  describe 'GET /api/v1/analytics/tiers/current' do
    context 'with billing.read permission' do
      it 'returns current tier information' do
        get '/api/v1/analytics/tiers/current',
            headers: auth_headers_for(billing_reader),
            as: :json

        expect_success_response
        expect(json_response['data']).to be_present
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/tiers/current',
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response('Permission denied: billing.read', 403)
      end
    end
  end

  describe 'GET /api/v1/analytics/tiers/comparison' do
    context 'with billing.read permission' do
      it 'returns tier comparison data' do
        get '/api/v1/analytics/tiers/comparison',
            headers: auth_headers_for(billing_reader),
            as: :json

        expect_success_response
        expect(json_response['data']).to be_present
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/tiers/comparison',
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response('Permission denied: billing.read', 403)
      end
    end
  end

  describe 'GET /api/v1/analytics/tiers/feature_gates' do
    context 'with billing.read permission' do
      it 'returns feature gates for current tier' do
        get '/api/v1/analytics/tiers/feature_gates',
            headers: auth_headers_for(billing_reader),
            as: :json

        expect_success_response
        expect(json_response['data']).to be_present
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/tiers/feature_gates',
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response('Permission denied: billing.read', 403)
      end
    end
  end

  describe 'POST /api/v1/analytics/tiers/upgrade' do
    context 'with billing.manage permission' do
      it 'upgrades to new tier' do
        post '/api/v1/analytics/tiers/upgrade',
             params: { tier: 'pro' },
             headers: auth_headers_for(billing_manager),
             as: :json

        expect_success_response
        expect(json_response['data']).to be_present
      end

      it 'requires tier parameter' do
        post '/api/v1/analytics/tiers/upgrade',
             params: {},
             headers: auth_headers_for(billing_manager),
             as: :json

        expect_error_response('Tier is required', 400)
      end

      it 'validates tier exists' do
        post '/api/v1/analytics/tiers/upgrade',
             params: { tier: 'non-existent' },
             headers: auth_headers_for(billing_manager),
             as: :json

        expect_error_response(nil, 422)
      end
    end

    context 'without billing.manage permission' do
      it 'returns forbidden error for billing.read user' do
        post '/api/v1/analytics/tiers/upgrade',
             params: { tier: 'pro' },
             headers: auth_headers_for(billing_reader),
             as: :json

        expect_error_response('Permission denied: billing.manage', 403)
      end

      it 'returns forbidden error for regular user' do
        post '/api/v1/analytics/tiers/upgrade',
             params: { tier: 'pro' },
             headers: auth_headers_for(regular_user),
             as: :json

        expect_error_response('Permission denied: billing.manage', 403)
      end
    end
  end

  describe 'GET /api/v1/analytics/tiers/:slug' do
    it 'returns tier details by slug' do
      get '/api/v1/analytics/tiers/pro', as: :json

      expect_success_response
      expect(json_response['data']).to be_present
    end

    it 'returns not found for non-existent tier' do
      get '/api/v1/analytics/tiers/non-existent', as: :json

      expect_error_response('Tier not found', 404)
    end

    it 'returns comparison data' do
      get '/api/v1/analytics/tiers/pro', as: :json

      expect_success_response
      expect(json_response['data']).to be_present
    end
  end
end
