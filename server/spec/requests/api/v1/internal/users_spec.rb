# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Users', type: :request do
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account, email: 'test@example.com', name: 'Test User') }

  describe 'GET /api/v1/internal/users/:id' do
    context 'with valid service token' do
      it 'returns user details' do
        get "/api/v1/internal/users/#{user.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response['data']

        expect(data['id']).to eq(user.id)
        expect(data['email']).to eq('test@example.com')
        expect(data['name']).to eq('Test User')
        expect(data).to include(
          'email_verified',
          'created_at',
          'last_login_at'
        )
      end

      it 'returns email_verified status' do
        user.update(email_verified_at: Time.current)

        get "/api/v1/internal/users/#{user.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        expect(json_response['data']['email_verified']).to be true
      end
    end

    context 'with non-existent user' do
      it 'returns not found error' do
        get '/api/v1/internal/users/non-existent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('User not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/users/#{user.id}",
            as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/internal/users/:id' do
    context 'with valid service token' do
      it 'deletes the user' do
        expect do
          delete "/api/v1/internal/users/#{user.id}",
                 headers: internal_headers,
                 as: :json
        end.to change(User, :count).by(-1)

        expect_success_response
        expect(json_response['message']).to eq('User deleted successfully')
      end
    end

    context 'with non-existent user' do
      it 'returns not found error' do
        delete '/api/v1/internal/users/non-existent-id',
               headers: internal_headers,
               as: :json

        expect_error_response('User not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        delete "/api/v1/internal/users/#{user.id}",
               as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/users/:user_id/anonymize' do
    context 'with valid service token' do
      it 'anonymizes user data' do
        patch "/api/v1/internal/users/#{user.id}/anonymize",
              headers: internal_headers,
              as: :json

        expect_success_response
        expect(json_response['message']).to eq('User anonymized successfully')

        user.reload
        expect(user.email).to eq("deleted_#{user.id}@anonymized.local")
        expect(user.name).to eq('Deleted User')
        expect(user.phone).to be_nil
      end

      it 'preserves user ID' do
        original_id = user.id

        patch "/api/v1/internal/users/#{user.id}/anonymize",
              headers: internal_headers,
              as: :json

        expect_success_response
        user.reload
        expect(user.id).to eq(original_id)
      end
    end

    context 'with non-existent user' do
      it 'returns not found error' do
        patch '/api/v1/internal/users/non-existent-id/anonymize',
              headers: internal_headers,
              as: :json

        expect_error_response('User not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/users/#{user.id}/anonymize",
              as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/users/:user_id/anonymize_audit_logs' do
    context 'with valid service token' do
      let!(:audit_logs) do
        [
          create(:audit_log, user: user, ip_address: '192.168.1.1', user_agent: 'Mozilla/5.0'),
          create(:audit_log, user: user, ip_address: '10.0.0.1', user_agent: 'Chrome/90.0')
        ]
      end

      it 'anonymizes audit log data' do
        patch "/api/v1/internal/users/#{user.id}/anonymize_audit_logs",
              headers: internal_headers,
              as: :json

        expect_success_response
        expect(json_response['message']).to eq('User audit logs anonymized')

        audit_logs.each do |log|
          log.reload
          expect(log.ip_address).to eq('0.0.0.0')
          expect(log.user_agent).to eq('anonymized')
        end
      end

      it 'does not affect other users audit logs' do
        other_user = create(:user, account: account)
        other_log = create(:audit_log, user: other_user, ip_address: '192.168.2.1')

        patch "/api/v1/internal/users/#{user.id}/anonymize_audit_logs",
              headers: internal_headers,
              as: :json

        expect_success_response
        other_log.reload
        expect(other_log.ip_address).to eq('192.168.2.1')
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/users/#{user.id}/anonymize_audit_logs",
              as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/internal/users/:user_id/consents' do
    context 'with valid service token' do
      let!(:consents) do
        [
          create(:consent, user: user),
          create(:consent, user: user)
        ]
      end

      it 'deletes all user consents' do
        expect do
          delete "/api/v1/internal/users/#{user.id}/consents",
                 headers: internal_headers,
                 as: :json
        end.to change { Consent.where(user_id: user.id).count }.from(2).to(0)

        expect_success_response
        expect(json_response['message']).to eq('Deleted 2 consent records')
      end

      it 'does not affect other users consents' do
        other_user = create(:user, account: account)
        other_consent = create(:consent, user: other_user)

        delete "/api/v1/internal/users/#{user.id}/consents",
               headers: internal_headers,
               as: :json

        expect_success_response
        expect(Consent.exists?(other_consent.id)).to be true
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        delete "/api/v1/internal/users/#{user.id}/consents",
               as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/internal/users/:user_id/terms_acceptances' do
    context 'with valid service token' do
      it 'returns success message with count' do
        delete "/api/v1/internal/users/#{user.id}/terms_acceptances",
               headers: internal_headers,
               as: :json

        expect_success_response
        expect(json_response['message']).to match(/Deleted \d+ terms acceptance records/)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        delete "/api/v1/internal/users/#{user.id}/terms_acceptances",
               as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/internal/users/:user_id/password_histories' do
    context 'with valid service token' do
      it 'returns success message with count' do
        delete "/api/v1/internal/users/#{user.id}/password_histories",
               headers: internal_headers,
               as: :json

        expect_success_response
        expect(json_response['message']).to match(/Deleted \d+ password history records/)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        delete "/api/v1/internal/users/#{user.id}/password_histories",
               as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/internal/users/:user_id/roles' do
    context 'with valid service token' do
      let!(:role) { create(:role, account: account) }
      let!(:user_role) { create(:user_role, user: user, role: role) }

      it 'deletes all user roles' do
        expect do
          delete "/api/v1/internal/users/#{user.id}/roles",
                 headers: internal_headers,
                 as: :json
        end.to change { user.user_roles.count }.from(1).to(0)

        expect_success_response
        expect(json_response['message']).to eq('Deleted 1 user role records')
      end

      it 'does not affect other users roles' do
        other_user = create(:user, account: account)
        other_user_role = create(:user_role, user: other_user, role: role)

        delete "/api/v1/internal/users/#{user.id}/roles",
               headers: internal_headers,
               as: :json

        expect_success_response
        expect(UserRole.exists?(other_user_role.id)).to be true
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        delete "/api/v1/internal/users/#{user.id}/roles",
               as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end
end
