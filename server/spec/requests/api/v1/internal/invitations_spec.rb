# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Invitations', type: :request do
  let(:account) { create(:account) }
  let(:inviter) { create(:user, account: account, first_name: 'John', last_name: 'Doe') }
  let(:invitation) do
    Invitation.create!(
      account: account,
      inviter: inviter,
      email: 'invitee@example.com',
      first_name: 'Jane',
      last_name: 'Smith',
      role_names: ['member'],
      expires_at: 7.days.from_now
    )
  end

  # Worker token authentication (different from service token)
  let(:worker_headers) do
    token = Rails.application.config.worker_token
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/invitations/:id' do
    context 'with worker token authentication' do
      it 'returns invitation details' do
        get "/api/v1/internal/invitations/#{invitation.id}",
            headers: worker_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => invitation.id,
          'email' => 'invitee@example.com',
          'first_name' => 'Jane',
          'last_name' => 'Smith',
          'role_names' => ['member']
        )
      end

      it 'includes account name' do
        get "/api/v1/internal/invitations/#{invitation.id}",
            headers: worker_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'account_name' => account.name
        )
      end

      it 'includes inviter information' do
        get "/api/v1/internal/invitations/#{invitation.id}",
            headers: worker_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'inviter_first_name' => 'John',
          'inviter_last_name' => 'Doe'
        )
      end

      it 'includes expiration timestamp' do
        get "/api/v1/internal/invitations/#{invitation.id}",
            headers: worker_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['expires_at']).to be_present
      end
    end

    context 'when invitation does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/invitations/nonexistent-id',
            headers: worker_headers,
            as: :json

        expect_error_response('Invitation not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/invitations/#{invitation.id}", as: :json

        expect_error_response('Invalid worker authentication', 401)
      end
    end

    context 'with invalid worker token' do
      it 'returns unauthorized error' do
        invalid_headers = { 'Authorization' => 'Bearer invalid-token' }

        get "/api/v1/internal/invitations/#{invitation.id}",
            headers: invalid_headers,
            as: :json

        expect_error_response('Invalid worker authentication', 401)
      end
    end

    context 'with missing worker token' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/invitations/#{invitation.id}",
            headers: {},
            as: :json

        expect_error_response('Invalid worker authentication', 401)
      end
    end
  end
end
