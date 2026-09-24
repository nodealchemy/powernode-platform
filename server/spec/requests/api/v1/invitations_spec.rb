# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API::V1::Invitations', type: :request do
  # Stub WorkerJobService to prevent HTTP calls in tests
  before do
    allow(WorkerJobService).to receive(:enqueue_job).and_return({ 'status' => 'queued' })
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
          role_names: [ 'member' ]
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

    # Possession of invitations.token is an unauthenticated account join (see
    # InvitationsController#accept, which skips authentication). Worker job args
    # are logged by Sidekiq and persisted verbatim in the Redis payload, which
    # Sidekiq::Web renders — so the token must NOT be enqueued. The worker reads
    # it from the mTLS-gated internal endpoint instead.
    it 'enqueues the invitation email with the id only — never the token' do
      captured = nil
      allow(WorkerJobService).to receive(:enqueue_notification_email) do |type, opts|
        captured = [ type, opts ]
        nil
      end

      post '/api/v1/invitations', params: invitation_params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      type, opts = captured
      expect(type).to eq('invitation')
      expect(opts.keys).to eq([ :invitation_id ])
      expect(opts.values.map(&:to_s)).not_to include(Invitation.last.token)
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
      other_user = create(:user, account: account, permissions: [])
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
      other_user = create(:user, account: account, permissions: [])
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
        password: TestUsers::PASSWORD,
        password_confirmation: TestUsers::PASSWORD
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
      invitation.update(role_names: [ 'member' ])

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

  # fc-01: the invitee has no account yet when they land on the
  # accept-invitation page, so the page cannot use any of the authenticated
  # `show`/`index` routes to display the invite before the user submits the
  # accept form. This is the public, token-only lookup that page calls.
  describe 'GET /api/v1/invitations/lookup' do
    let(:invitation) { create(:invitation, account: account, inviter: manager_user, role_names: [ 'member' ]) }

    it 'does not require authentication' do
      get '/api/v1/invitations/lookup', params: { token: invitation.token }
      expect(response).not_to have_http_status(:unauthorized)
    end

    it 'returns the minimal fields the accept page needs' do
      get '/api/v1/invitations/lookup', params: { token: invitation.token }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']).to eq(
        'email' => invitation.email,
        'role_names' => [ 'member' ],
        'expires_at' => invitation.expires_at.as_json,
        'account' => { 'name' => account.name },
        'inviter' => { 'name' => manager_user.name }
      )
    end

    it 'never returns the token or token_digest' do
      get '/api/v1/invitations/lookup', params: { token: invitation.token }

      body = response.body
      expect(body).not_to include(invitation.token)
      expect(JSON.parse(body)['data']).not_to have_key('token')
      expect(JSON.parse(body)['data']).not_to have_key('token_digest')
      expect(JSON.parse(body)['data']).not_to have_key('id')
    end

    it 'requires a token param' do
      get '/api/v1/invitations/lookup'
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 404 for a token that matches no invitation — no :id enumeration surface' do
      get '/api/v1/invitations/lookup', params: { token: 'not-a-real-token' }
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 410 Gone for an expired invitation, with an "expired" message' do
      expired = create(:invitation, :expired, account: account, inviter: manager_user)
      get '/api/v1/invitations/lookup', params: { token: expired.token }

      expect(response).to have_http_status(:gone)
      expect(JSON.parse(response.body)['error']).to include('expired')
    end

    it 'returns 404 (not a distinguishable state) for an already-accepted invitation' do
      accepted = create(:invitation, :accepted, account: account, inviter: manager_user)
      get '/api/v1/invitations/lookup', params: { token: accepted.token }
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 (not a distinguishable state) for a cancelled invitation' do
      cancelled = create(:invitation, :cancelled, account: account, inviter: manager_user)
      get '/api/v1/invitations/lookup', params: { token: cancelled.token }
      expect(response).to have_http_status(:not_found)
    end

    # pending? is checked BEFORE expired? in the controller specifically so
    # this case (accepted a while after being sent, well past its original
    # 7-day expires_at) still gets the uniform 404 an accepted invitation is
    # supposed to get, not a 410 that would leak "this token used to be
    # valid" beyond what the plain 404 already could mean.
    it 'returns 404, not 410, for an accepted invitation that is also past its expires_at' do
      accepted_and_expired = create(:invitation, :accepted, account: account, inviter: manager_user, expires_at: 1.day.ago)
      get '/api/v1/invitations/lookup', params: { token: accepted_and_expired.token }
      expect(response).to have_http_status(:not_found)
    end

    context 'rate limiting' do
      before do
        # Same regression class as rack_attack_enabled_spec.rb's "stays
        # disabled..." example: RateLimiting#check_and_increment_rate_limit
        # reads ENV["DISABLE_RATE_LIMITING"] directly, so a developer box
        # with a gitignored .env setting it true would silently never see
        # these specs throttle, while a machine with no .env would. Pin it
        # explicitly rather than depend on what's on disk.
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DISABLE_RATE_LIMITING').and_return(nil)
      end

      it 'rate-limits repeated failed lookups by IP' do
        10.times do
          get '/api/v1/invitations/lookup', params: { token: 'never-matches' }
          expect(response).to have_http_status(:not_found)
        end

        get '/api/v1/invitations/lookup', params: { token: 'never-matches' }
        expect(response).to have_http_status(:too_many_requests)
      end

      it 'does not count a successful lookup toward the rate limit' do
        10.times do
          get '/api/v1/invitations/lookup', params: { token: invitation.token }
          expect(response).to have_http_status(:success)
        end

        # If the 10 successes above had counted toward the same 10/hour
        # budget, this 11th request -- a genuine failure, on a bad token --
        # would already be AT the limit and come back 429 instead of the 404
        # its own bad token deserves. Only a 404 here proves the successes
        # didn't spend any of the budget.
        get '/api/v1/invitations/lookup', params: { token: 'never-matches' }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # fc-01: accept's own rate limit, same mechanism as lookup above.
  describe 'POST /api/v1/invitations/accept rate limiting' do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DISABLE_RATE_LIMITING').and_return(nil)
    end

    it 'rate-limits repeated failed accept attempts by IP' do
      10.times do
        post '/api/v1/invitations/accept', params: { token: 'never-matches' }, as: :json
        expect(response).to have_http_status(:not_found)
      end

      post '/api/v1/invitations/accept', params: { token: 'never-matches' }, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
