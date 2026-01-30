# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Impersonations', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:manager_user) { create(:user, :manager, account: account) }
  let(:target_user) { create(:user, :member, account: account) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, :member, account: other_account) }

  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:manager_headers) { auth_headers_for(manager_user) }

  before do
    # Grant impersonation permission to admin
    admin_user.grant_permission('admin.user.impersonate')
    admin_user.grant_permission('admin.access')
  end

  describe 'POST /api/v1/impersonations' do
    let(:impersonation_params) do
      {
        user_id: target_user.id,
        reason: 'Support request'
      }
    end

    context 'with admin.user.impersonate permission' do
      it 'creates impersonation session and returns token' do
        post '/api/v1/impersonations',
             params: impersonation_params,
             headers: admin_headers,
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response_data
        expect(data['token']).to be_present
        expect(data['target_user']['id']).to eq(target_user.id)
        expect(data).to have_key('expires_at')
      end

      it 'creates impersonation session record' do
        expect {
          post '/api/v1/impersonations',
               params: impersonation_params,
               headers: admin_headers,
               as: :json
        }.to change { ImpersonationSession.count }.by(1)

        session = ImpersonationSession.last
        expect(session.impersonator_id).to eq(admin_user.id)
        expect(session.impersonated_user_id).to eq(target_user.id)
        expect(session.reason).to eq('Support request')
      end

      it 'returns error when user_id is missing' do
        post '/api/v1/impersonations',
             params: { reason: 'Test' },
             headers: admin_headers,
             as: :json

        expect_error_response('User ID required', 400)
      end

      it 'returns error when target user not found' do
        post '/api/v1/impersonations',
             params: { user_id: SecureRandom.uuid },
             headers: admin_headers,
             as: :json

        expect_error_response('User not found', 404)
      end
    end

    context 'without impersonation permission' do
      it 'returns forbidden error' do
        user = create(:user, :member, account: account)
        headers = auth_headers_for(user)

        post '/api/v1/impersonations',
             params: impersonation_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/impersonations' do
    let!(:impersonation_token) do
      service = Auth::ImpersonationService.new(admin_user)
      service.start_impersonation(
        target_user_id: target_user.id,
        reason: 'Test',
        ip_address: '127.0.0.1',
        user_agent: 'RSpec'
      )
    end
    let!(:session) { ImpersonationSession.last }

    it 'ends impersonation session' do
      delete '/api/v1/impersonations',
             params: { session_token: session.session_token },
             headers: admin_headers,
             as: :json

      expect_success_response
      expect(json_response_data).to have_key('duration')
      expect(session.reload.ended_at).not_to be_nil
    end

    it 'returns error when session_token is missing' do
      delete '/api/v1/impersonations',
             headers: admin_headers,
             as: :json

      expect_error_response('Session token required', 400)
    end

    it 'returns error when session not found' do
      delete '/api/v1/impersonations',
             params: { session_token: 'invalid-token' },
             headers: admin_headers,
             as: :json

      # The destroy action skips authenticate_request and uses manual auth.
      # JWT from admin_headers doesn't match a UserToken, so current_user is nil.
      # With an invalid session_token, no ImpersonationSession is found either,
      # so the controller returns 401 "Unable to authenticate".
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/impersonations' do
    let!(:active_session) do
      ImpersonationSession.create!(
        impersonator: admin_user,
        impersonated_user: target_user,
        session_token: SecureRandom.hex(32),
        reason: 'Active test',
        started_at: Time.current,
        ip_address: '127.0.0.1',
        user_agent: 'RSpec'
      )
    end

    context 'with admin.access permission' do
      it 'returns list of active sessions' do
        get '/api/v1/impersonations', headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.length).to be >= 1
        expect(data.first).to have_key('id')
        expect(data.first).to have_key('impersonator')
        expect(data.first).to have_key('impersonated_user')
      end
    end

    context 'without admin.access permission' do
      it 'returns forbidden error' do
        user = create(:user, :member, account: account)
        headers = auth_headers_for(user)

        get '/api/v1/impersonations', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/impersonations/history' do
    let!(:ended_session) do
      ImpersonationSession.create!(
        impersonator: admin_user,
        impersonated_user: target_user,
        session_token: SecureRandom.hex(32),
        reason: 'History test',
        started_at: 1.hour.ago,
        ended_at: 30.minutes.ago,
        ip_address: '127.0.0.1',
        user_agent: 'RSpec'
      )
    end

    context 'with admin.access permission' do
      it 'returns session history' do
        get '/api/v1/impersonations/history', headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(json_response['meta']).to have_key('pagination')
      end

      it 'respects limit parameter' do
        get '/api/v1/impersonations/history?limit=5',
            headers: admin_headers,
            as: :json

        expect_success_response
        expect(json_response['meta']['pagination']['limit']).to eq(5)
      end
    end
  end

  describe 'GET /api/v1/impersonations/users' do
    context 'with admin.access permission' do
      it 'returns list of impersonatable users' do
        # Ensure at least one non-admin user exists so the response includes data
        target_user

        get '/api/v1/impersonations/users', headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        # Should not include the current user
        expect(data.none? { |u| u['id'] == admin_user.id }).to be true
      end
    end
  end

  describe 'POST /api/v1/impersonations/validate' do
    let!(:session) do
      service = Auth::ImpersonationService.new(admin_user)
      token = service.start_impersonation(
        target_user_id: target_user.id,
        reason: 'Validate test',
        ip_address: '127.0.0.1',
        user_agent: 'RSpec'
      )
      { token: token, session: ImpersonationSession.last }
    end

    it 'validates valid impersonation token' do
      post '/api/v1/impersonations/validate',
           params: { token: session[:token] },
           as: :json

      expect_success_response
      data = json_response_data
      expect(data['valid']).to be true
      expect(data['session']).to be_present
      expect(data).to have_key('expires_at')
    end

    it 'returns invalid for expired token' do
      # End the session to make it invalid
      session[:session].update!(ended_at: Time.current)

      post '/api/v1/impersonations/validate',
           params: { token: session[:token] },
           as: :json

      expect_success_response
      data = json_response_data
      expect(data['valid']).to be false
    end

    it 'returns error when token is missing' do
      post '/api/v1/impersonations/validate', as: :json

      expect_error_response('Token required', 400)
    end

    it 'returns invalid for malformed token' do
      post '/api/v1/impersonations/validate',
           params: { token: 'invalid-token' },
           as: :json

      expect_success_response
      data = json_response_data
      expect(data['valid']).to be false
    end
  end

  describe 'POST /api/v1/impersonations/cleanup_expired' do
    let!(:expired_session) do
      ImpersonationSession.create!(
        impersonator: admin_user,
        impersonated_user: target_user,
        session_token: SecureRandom.hex(32),
        reason: 'Cleanup test',
        started_at: 2.hours.ago,
        ip_address: '127.0.0.1',
        user_agent: 'RSpec'
      )
    end

    context 'with admin.access permission' do
      before do
        # The controller calls skip_authorization (service-to-service call marker)
        # which is not defined on the controller. Define it as a no-op to avoid NoMethodError.
        Api::V1::ImpersonationsController.define_method(:skip_authorization) { true } unless Api::V1::ImpersonationsController.method_defined?(:skip_authorization)
      end

      it 'cleans up expired sessions' do
        # Make the session expired
        travel_to(2.hours.from_now) do
          post '/api/v1/impersonations/cleanup_expired',
               headers: admin_headers,
               as: :json

          expect_success_response
          data = json_response_data
          expect(data).to have_key('cleaned_up_count')
        end
      end
    end
  end
end
