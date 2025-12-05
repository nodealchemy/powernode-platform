# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API::V1::Invitations', type: :request do
  # Stub WorkerJobService to prevent HTTP calls in tests
  before do
    allow(WorkerJobService).to receive(:enqueue_notification_email).and_return({ 'status' => 'queued' })
  end

  let(:account) { create(:account) }
  let(:manager_user) { create(:user, :manager, account: account) }
  let(:regular_user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(manager_user) }

  describe 'GET /api/v1/invitations' do
    let!(:invitations) { create_list(:invitation, 3, account: account, inviter: manager_user) }
    let!(:expired_invitation) { create(:invitation, :expired, account: account, inviter: manager_user) }
    let!(:other_account_invitation) { create(:invitation) }

    it 'returns all invitations for the current account' do
      get '/api/v1/invitations', headers: headers, as: :json

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data'].length).to eq(4) # 3 active + 1 expired
    end

    it 'filters invitations by status' do
      get '/api/v1/invitations', params: { status: 'pending' }, headers: headers

      json = JSON.parse(response.body)
      expect(json['data'].all? { |inv| inv['status'] == 'pending' }).to be true
    end

    it 'excludes expired invitations when include_expired is false' do
      get '/api/v1/invitations', params: { include_expired: false }, headers: headers

      json = JSON.parse(response.body)
      expect(json['data'].length).to eq(3) # Only active invitations
    end

    it 'requires authentication' do
      get '/api/v1/invitations', as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires team.invite or users.create permission' do
      regular_user.roles.clear
      get '/api/v1/invitations', headers: auth_headers_for(regular_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/invitations/:id' do
    let(:invitation) { create(:invitation, account: account, inviter: manager_user) }

    it 'returns invitation details' do
      get "/api/v1/invitations/#{invitation.id}", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['id']).to eq(invitation.id)
      expect(json['data']['email']).to eq(invitation.email)
    end

    it 'does not include token in response' do
      get "/api/v1/invitations/#{invitation.id}", headers: headers, as: :json

      json = JSON.parse(response.body)
      expect(json['data']['token']).to be_nil
    end

    it 'returns 404 for invitation from different account' do
      other_invitation = create(:invitation)
      get "/api/v1/invitations/#{other_invitation.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/invitations' do
    let(:invitation_params) do
      {
        invitation: {
          email: 'newuser@example.com',
          first_name: 'John',
          last_name: 'Doe',
          role_names: ['member']
        }
      }
    end

    it 'creates a new invitation' do
      expect {
        post '/api/v1/invitations', params: invitation_params, headers: headers, as: :json
      }.to change(Invitation, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['email']).to eq('newuser@example.com')
      expect(json['data']['token']).to be_present # Token included on creation
    end

    it 'associates invitation with current account' do
      post '/api/v1/invitations', params: invitation_params, headers: headers, as: :json

      invitation = Invitation.last
      expect(invitation.account_id).to eq(account.id)
      expect(invitation.inviter_id).to eq(manager_user.id)
    end

    it 'validates required fields' do
      post '/api/v1/invitations', params: { invitation: { email: '' } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
    end

    it 'prevents duplicate invitations for same email in account' do
      create(:invitation, account: account, inviter: manager_user, email: 'newuser@example.com')

      post '/api/v1/invitations', params: invitation_params, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['details']['errors']).to include(/already been invited/)
    end
  end

  describe 'PATCH /api/v1/invitations/:id' do
    let(:invitation) { create(:invitation, account: account, inviter: manager_user) }

    it 'updates invitation details' do
      patch "/api/v1/invitations/#{invitation.id}",
            params: { invitation: { first_name: 'Jane' } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:success)
      expect(invitation.reload.first_name).to eq('Jane')
    end

    it 'allows inviter to update their own invitation' do
      patch "/api/v1/invitations/#{invitation.id}",
            params: { invitation: { first_name: 'Updated' } },
            headers: auth_headers_for(manager_user),
            as: :json

      expect(response).to have_http_status(:success)
    end

    it 'forbids non-inviter without admin permissions' do
      other_user = create(:user, :manager, account: account)
      patch "/api/v1/invitations/#{invitation.id}",
            params: { invitation: { first_name: 'Jane' } },
            headers: auth_headers_for(other_user),
            as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE /api/v1/invitations/:id' do
    let!(:invitation) { create(:invitation, account: account, inviter: manager_user) }

    it 'deletes the invitation' do
      expect {
        delete "/api/v1/invitations/#{invitation.id}", headers: headers, as: :json
      }.to change(Invitation, :count).by(-1)

      expect(response).to have_http_status(:success)
    end

    it 'forbids deletion by non-inviter' do
      other_user = create(:user, :manager, account: account)
      delete "/api/v1/invitations/#{invitation.id}",
             headers: auth_headers_for(other_user),
             as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /api/v1/invitations/:id/resend' do
    let(:invitation) { create(:invitation, account: account, inviter: manager_user) }

    it 'resends a pending invitation and extends expiration' do
      old_expiration = invitation.expires_at

      post "/api/v1/invitations/#{invitation.id}/resend", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(invitation.reload.expires_at).to be > old_expiration
    end

    it 'does not resend expired invitations' do
      expired = create(:invitation, :expired, account: account, inviter: manager_user)

      post "/api/v1/invitations/#{expired.id}/resend", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['error']).to include('pending, non-expired')
    end

    it 'does not resend accepted invitations' do
      accepted = create(:invitation, :accepted, account: account, inviter: manager_user)

      post "/api/v1/invitations/#{accepted.id}/resend", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'POST /api/v1/invitations/:id/cancel' do
    let(:invitation) { create(:invitation, account: account, inviter: manager_user) }

    it 'cancels a pending invitation' do
      post "/api/v1/invitations/#{invitation.id}/cancel", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(invitation.reload.status).to eq('cancelled')
    end

    it 'does not cancel already accepted invitations' do
      accepted = create(:invitation, :accepted, account: account, inviter: manager_user)

      post "/api/v1/invitations/#{accepted.id}/cancel", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'POST /api/v1/invitations/accept' do
    let(:invitation) { create(:invitation, account: account, inviter: manager_user) }
    let(:accept_params) do
      {
        token: invitation.token,
        password: 'NewSecureP@ssw0rd!',
        password_confirmation: 'NewSecureP@ssw0rd!'
      }
    end

    it 'accepts invitation and creates user account' do
      # Force invitation creation before expect block to avoid lazy loading issue
      invitation

      expect {
        post '/api/v1/invitations/accept', params: accept_params, as: :json
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['user']['email']).to eq(invitation.email)
    end

    it 'marks invitation as accepted' do
      post '/api/v1/invitations/accept', params: accept_params, as: :json

      expect(invitation.reload.status).to eq('accepted')
      expect(invitation.accepted_at).to be_present
    end

    it 'assigns roles from invitation to new user' do
      invitation.update(role_names: ['member'])

      post '/api/v1/invitations/accept', params: accept_params, as: :json

      user = User.last
      expect(user.roles.pluck(:name)).to include('member')
    end

    it 'auto-verifies email for invited users' do
      post '/api/v1/invitations/accept', params: accept_params, as: :json

      user = User.last
      expect(user.email_verified_at).to be_present
    end

    it 'rejects invalid token' do
      post '/api/v1/invitations/accept',
           params: accept_params.merge(token: 'invalid-token'),
           as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects expired invitations' do
      expired = create(:invitation, :expired, account: account, inviter: manager_user)

      post '/api/v1/invitations/accept',
           params: accept_params.merge(token: expired.token),
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['error']).to include('expired')
    end

    it 'rejects already accepted invitations' do
      invitation.accept!

      post '/api/v1/invitations/accept', params: accept_params, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['error']).to include('already been accepted')
    end

    it 'requires matching password confirmation' do
      post '/api/v1/invitations/accept',
           params: accept_params.merge(password_confirmation: 'DifferentPassword'),
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
