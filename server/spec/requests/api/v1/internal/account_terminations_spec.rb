# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::AccountTerminations', type: :request do
  let(:account) { create(:account) }

  # Service token authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/account_terminations' do
    let!(:pending_termination) do
      Account::Termination.create!(
        account: account,
        status: 'pending',
        reason: 'user_requested',
        requested_at: Time.current,
        grace_period_ends_at: 2.days.from_now
      )
    end

    let!(:processing_termination) do
      Account::Termination.create!(
        account: create(:account),
        status: 'processing',
        reason: 'payment_failure',
        grace_period_ends_at: 1.day.ago,
        requested_at: 2.days.ago,
        processing_started_at: 1.hour.ago
      )
    end

    let!(:completed_termination) do
      Account::Termination.create!(
        account: create(:account),
        status: 'completed',
        reason: 'user_requested',
        requested_at: 10.days.ago,
        grace_period_ends_at: 5.days.ago,
        completed_at: 3.days.ago
      )
    end

    context 'with service token authentication' do
      it 'returns active terminations (pending, grace_period, processing)' do
        get '/api/v1/internal/account_terminations', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data'].size).to eq(2)
        termination_ids = response_data['data'].map { |t| t['id'] }
        expect(termination_ids).to include(pending_termination.id, processing_termination.id)
        expect(termination_ids).not_to include(completed_termination.id)
      end

      it 'returns terminations ordered by grace_period_ends_at ascending' do
        get '/api/v1/internal/account_terminations', headers: internal_headers, as: :json

        response_data = json_response
        terminations = response_data['data']

        expect(terminations.first['id']).to eq(processing_termination.id)
        expect(terminations.last['id']).to eq(pending_termination.id)
      end

      it 'includes all termination fields' do
        get '/api/v1/internal/account_terminations', headers: internal_headers, as: :json

        response_data = json_response
        termination = response_data['data'].first

        expect(termination).to include(
          'id',
          'account_id',
          'status',
          'reason',
          'grace_period_ends_at',
          'completed_at',
          'requested_at',
          'created_at',
          'updated_at'
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/internal/account_terminations', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/account_terminations/:id' do
    let(:termination) do
      Account::Termination.create!(
        account: account,
        status: 'pending',
        reason: 'user_requested',
        requested_at: Time.current,
        grace_period_ends_at: 2.days.from_now
      )
    end

    context 'with service token authentication' do
      it 'returns termination details' do
        get "/api/v1/internal/account_terminations/#{termination.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => termination.id,
          'account_id' => account.id,
          'status' => 'pending',
          'reason' => 'user_requested'
        )
      end

      it 'includes grace_period_ends_at timestamp' do
        get "/api/v1/internal/account_terminations/#{termination.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        expect(response_data['data']['grace_period_ends_at']).to be_present
      end
    end

    context 'when termination does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/account_terminations/nonexistent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('Account termination not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/account_terminations/#{termination.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/internal/account_terminations/:id' do
    let(:termination) do
      Account::Termination.create!(
        account: account,
        status: 'pending',
        reason: 'user_requested',
        requested_at: Time.current,
        grace_period_ends_at: 2.days.from_now
      )
    end

    context 'with service token authentication' do
      it 'updates termination status to grace_period' do
        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: { status: 'grace_period' },
              headers: internal_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['status']).to eq('grace_period')

        termination.reload
        expect(termination.status).to eq('grace_period')
      end

      it 'updates termination status to completed with completion timestamp' do
        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: {
                status: 'completed',
                completed_at: Time.current.iso8601
              },
              headers: internal_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['status']).to eq('completed')
        expect(response_data['data']['completed_at']).to be_present

        termination.reload
        expect(termination.status).to eq('completed')
        expect(termination.completed_at).to be_present
      end

      it 'updates termination status to cancelled' do
        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: { status: 'cancelled' },
              headers: internal_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['status']).to eq('cancelled')

        termination.reload
        expect(termination.status).to eq('cancelled')
      end
    end

    context 'when termination does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/account_terminations/nonexistent-id',
              params: { status: 'cancelled' },
              headers: internal_headers,
              as: :json

        expect_error_response('Account termination not found', 404)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error' do
        invalid_token = JWT.encode(
          { service: 'other', type: 'user', exp: 1.hour.from_now.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )

        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: { status: 'cancelled' },
              headers: { 'Authorization' => "Bearer #{invalid_token}" },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
