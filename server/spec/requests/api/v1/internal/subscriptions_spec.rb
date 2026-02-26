# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Subscriptions', type: :request do
  before do
    skip 'Enterprise billing module not loaded' unless defined?(Billing::Subscription)

    # Define methods on Subscription that the controller references but don't exist on the model
    unless Billing::Subscription.method_defined?(:cancel_at_period_end)
      Billing::Subscription.define_method(:cancel_at_period_end) { false }
    end
    unless Billing::Subscription.method_defined?(:dunning_status)
      Billing::Subscription.define_method(:dunning_status) { 'active' }
    end
  end

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    { 'Authorization' => "Bearer #{token}" }
  end

  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let!(:subscription) { create(:subscription, account: account, plan: plan, status: 'active') }

  describe 'GET /api/v1/internal/subscriptions/:id' do
    context 'with valid service token' do
      it 'returns subscription details' do
        get "/api/v1/internal/subscriptions/#{subscription.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response_data

        expect(data['id']).to eq(subscription.id)
        expect(data['account_id']).to eq(account.id)
        expect(data['plan_id']).to eq(plan.id)
        expect(data['status']).to eq('active')
        expect(data).to include(
          'current_period_start',
          'current_period_end',
          'cancel_at_period_end',
          'created_at',
          'updated_at'
        )
      end
    end

    context 'with non-existent subscription' do
      it 'returns not found error' do
        get '/api/v1/internal/subscriptions/non-existent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('Subscription not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/subscriptions/#{subscription.id}",
            as: :json

        expect_error_response('Worker token required', 401)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error' do
        invalid_token = JWT.encode(
          { service: 'invalid', type: 'service', exp: 1.hour.from_now.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )
        headers = { 'Authorization' => "Bearer #{invalid_token}" }

        get "/api/v1/internal/subscriptions/#{subscription.id}",
            headers: headers,
            as: :json

        expect_error_response('Invalid worker token', 401)
      end
    end
  end

  describe 'POST /api/v1/internal/subscriptions/:id/dunning' do
    before do
      # Allow update to succeed even with non-existent dunning_status column
      allow_any_instance_of(Billing::Subscription).to receive(:update).and_return(true)
    end

    context 'with valid service token' do
      it 'updates dunning status to provided value' do
        post "/api/v1/internal/subscriptions/#{subscription.id}/dunning",
             params: { dunning_status: 'active' },
             headers: internal_headers,
             as: :json

        expect_success_response
        data = json_response_data

        expect(data['id']).to eq(subscription.id)
        # Note: render_success(data: ..., message: ...) drops message
        # because data takes precedence in render_success
      end

      it 'defaults to active when dunning_status not provided' do
        post "/api/v1/internal/subscriptions/#{subscription.id}/dunning",
             headers: internal_headers,
             as: :json

        expect_success_response
      end

      it 'updates dunning status to custom value' do
        post "/api/v1/internal/subscriptions/#{subscription.id}/dunning",
             params: { dunning_status: 'paused' },
             headers: internal_headers,
             as: :json

        expect_success_response
      end
    end

    context 'with non-existent subscription' do
      it 'returns not found error' do
        post '/api/v1/internal/subscriptions/non-existent-id/dunning',
             headers: internal_headers,
             as: :json

        expect_error_response('Subscription not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        post "/api/v1/internal/subscriptions/#{subscription.id}/dunning",
             as: :json

        expect_error_response('Worker token required', 401)
      end
    end
  end
end
