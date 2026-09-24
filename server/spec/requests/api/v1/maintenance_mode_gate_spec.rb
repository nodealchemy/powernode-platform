# frozen_string_literal: true

require 'rails_helper'

# End-to-end coverage of the maintenance-mode gate, which lives INSIDE the two
# places a USER principal is resolved (Authentication#authenticate_request for
# REST, McpTokenAuthentication#authenticate_via_doorkeeper_token for MCP) —
# see Admin::MaintenanceMode.blocked? for the authoritative list of exactly
# which surfaces that is, and which are structurally never reached.
#
# This is a USER-PRINCIPAL gate, not a global before_action: it runs AFTER a
# user authenticates, never before. So login/refresh/2FA verification always
# succeed even during maintenance — a non-admin user's first encounter with
# the maintenance window is a normal-looking sign-in followed by a 503 on
# their next real request, not an opaque failure to sign in at all.
RSpec.describe 'Maintenance mode request gate', type: :request do
  let(:account) { create(:account) }
  let(:plain_user) { create(:user, account: account, permissions: []) }
  let(:admin_access_user) { create(:user, account: account, permissions: [ 'admin.access' ]) }
  let(:system_admin_user) { create(:user, account: account, permissions: [ 'system.admin' ]) }

  def get_me(user)
    get '/api/v1/auth/me', headers: auth_headers_for(user), as: :json
  end

  describe 'when maintenance mode is disabled' do
    it 'serves a normal request unaffected' do
      get_me(plain_user)

      expect(response).not_to have_http_status(:service_unavailable)
    end
  end

  describe 'when maintenance mode is enabled' do
    before do
      Admin::MaintenanceMode.enable!(message: 'Upgrading the database', estimated_completion: '2026-01-01T00:00:00Z')
      # Simulate a fresh process picking up the write: clear the cache without
      # touching the DB row Admin::MaintenanceMode.enable! just wrote.
      Admin::MaintenanceMode.invalidate_cache!
    end

    describe 'REST: login, refresh and 2FA verification are never gated (they skip authenticate_request)' do
      it 'a system.admin user can log in, refresh, and call an admin endpoint' do
        post '/api/v1/auth/login', params: { email: system_admin_user.email, password: TestUsers::PASSWORD }, as: :json
        expect(response).to have_http_status(:ok)
        access_token = json_response_data['access_token']
        expect(access_token).to be_present

        post '/api/v1/auth/refresh', as: :json # refresh token travels via the cookie jar set by login
        expect(response).not_to have_http_status(:service_unavailable)

        get '/api/v1/admin_settings', headers: { 'Authorization' => "Bearer #{access_token}" }, as: :json
        expect(response).not_to have_http_status(:service_unavailable)
      end

      it 'a PLAIN user can still log in and refresh during maintenance' do
        post '/api/v1/auth/login', params: { email: plain_user.email, password: TestUsers::PASSWORD }, as: :json
        expect(response).to have_http_status(:ok)

        post '/api/v1/auth/refresh', as: :json
        expect(response).not_to have_http_status(:service_unavailable)
      end
    end

    # N1: logout runs authenticate_request (unlike login/refresh/2FA above),
    # so without an explicit opt-out a gated user could never sign out —
    # their token would never be blacklisted and the refresh cookie would
    # never be cleared. See Authentication#exempt_from_maintenance_gate and
    # Api::V1::Auth::SessionsController's `exempt_from_maintenance_gate :destroy`.
    it 'lets a non-exempt, gated user log out (POST /auth/logout is exempt from the gate)' do
      post '/api/v1/auth/logout', headers: auth_headers_for(plain_user), as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'returns 503 with the standard error envelope for a non-exempt authenticated request' do
      get_me(plain_user)

      expect(response).to have_http_status(:service_unavailable)
      body = JSON.parse(response.body)
      expect(body['success']).to be false
      expect(body['error']).to eq('Upgrading the database')
      expect(body['code']).to eq('maintenance_mode')
      expect(body['details']['estimated_completion']).to eq('2026-01-01T00:00:00Z')
    end

    it 'still 401s an unauthenticated request rather than exposing the maintenance body to a caller with no token' do
      get '/api/v1/auth/me', as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'exempts a holder of admin.access' do
      get_me(admin_access_user)

      expect(response).not_to have_http_status(:service_unavailable)
    end

    it 'exempts a holder of system.admin' do
      get_me(system_admin_user)

      expect(response).not_to have_http_status(:service_unavailable)
    end

    it 'exempts a holder of admin.maintenance.mode (so it can never lock itself out of disabling maintenance)' do
      maintenance_admin = create(:user, account: account, permissions: [ 'admin.maintenance.mode' ])

      get_me(maintenance_admin)

      expect(response).not_to have_http_status(:service_unavailable)
    end

    it 'blocks an authenticated user who holds none of the exempt permissions' do
      get_me(plain_user)

      expect(response).to have_http_status(:service_unavailable)
    end

    it 'exempts a request from a bypass IP once TRUSTED_PROXY_CIDRS is configured' do
      # Driver decision: EVERY bypass entry, public or private, is refused
      # outright without TRUSTED_PROXY_CIDRS configured — see
      # Admin::MaintenanceMode#validate_bypass_ips!/#bypass_ip? and their spec.
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        Admin::MaintenanceMode.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])
        Admin::MaintenanceMode.invalidate_cache!

        get '/api/v1/auth/me', headers: auth_headers_for(plain_user), as: :json, env: { 'REMOTE_ADDR' => '203.0.113.5' }

        expect(response).not_to have_http_status(:service_unavailable)
      end
    end

    it 'refuses a bypass-IP write when TRUSTED_PROXY_CIDRS is unset, even for a public target' do
      expect {
        Admin::MaintenanceMode.enable!(message: 'Upgrading', bypass_ips: [ '203.0.113.5' ])
      }.to raise_error(Admin::MaintenanceMode::InvalidBypassIp, /TRUSTED_PROXY_CIDRS/)
    end

    describe 'machine principals are never gated — they never resolve a @current_user' do
      it 'the standalone worker API (Api::V1::Worker::*) is not 503d' do
        get '/api/v1/worker/files/00000000-0000-0000-0000-000000000000',
            headers: { 'Authorization' => "Bearer #{service_token}" }, as: :json

        expect(response).not_to have_http_status(:service_unavailable)
      end

      it 'the internal worker API (mTLS) is not 503d' do
        worker_account = create(:account)
        worker = create(:worker, account: worker_account)
        internal_headers = { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")) }

        get "/api/v1/internal/maintenance/backups/#{SecureRandom.uuid}", headers: internal_headers, as: :json

        expect(response).not_to have_http_status(:service_unavailable)
      end
    end

    describe 'MCP (OAuth 2.1 doorkeeper user principal)' do
      let(:oauth_app) { create(:oauth_application, :mcp_client) }

      it 'an admin (system.admin) MCP call is not 503d' do
        token = create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: system_admin_user.id, scopes: 'read write')

        post '/api/v1/mcp/message',
             params: { jsonrpc: '2.0', id: 1, method: 'ping', params: {} }.to_json,
             headers: { 'Authorization' => "Bearer #{token.plaintext_token}", 'Content-Type' => 'application/json' }

        expect(response).not_to have_http_status(:service_unavailable)
      end

      it 'a non-admin MCP call IS gated, with an MCP-shaped body' do
        token = create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: plain_user.id, scopes: 'read write')

        post '/api/v1/mcp/message',
             params: { jsonrpc: '2.0', id: 1, method: 'ping', params: {} }.to_json,
             headers: { 'Authorization' => "Bearer #{token.plaintext_token}", 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['error_code']).to eq('maintenance_mode')
      end
    end

    it 'does NOT gate an inbound webhook receiver — it authenticates as neither a user nor a worker principal' do
      # The git webhook receiver skips :authenticate_request outright (like a
      # real provider callback, unauthenticated by JWT), so it never resolves
      # a @current_user for the gate to fire against — it must NOT 503 during
      # maintenance. (Inverted from this feature's first draft, which routed
      # the gate through a global before_action and 503d it by default.)
      post '/api/v1/webhooks/git/github', as: :json

      expect(response).not_to have_http_status(:service_unavailable)
    end

    it 'exempts the public health check' do
      get '/api/v1/health', as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'exempts the public status page' do
      get '/api/v1/public/status', as: :json

      expect(response).not_to have_http_status(:service_unavailable)
    end

    it 'exempts the public boot endpoints (config, extensions/ui)' do
      get '/api/v1/config', as: :json
      expect(response).not_to have_http_status(:service_unavailable)

      get '/api/v1/extensions/ui', as: :json
      expect(response).not_to have_http_status(:service_unavailable)

      get '/api/v1/settings/public', as: :json
      expect(response).not_to have_http_status(:service_unavailable)
    end

    describe 'impersonation — driver decision: an impersonating admin must not be trapped' do
      def impersonation_headers(impersonator:, impersonated_user:)
        session = ImpersonationSession.create_session!(impersonator: impersonator, impersonated_user: impersonated_user)
        payload = {
          type: 'impersonation', session_id: session.id, sub: impersonated_user.id,
          account_id: impersonated_user.account_id, version: Security::JwtService::CURRENT_TOKEN_VERSION
        }
        { 'Authorization' => "Bearer #{Security::JwtService.encode(payload)}", 'Content-Type' => 'application/json' }
      end

      it 'exempts a session where the IMPERSONATOR (not the impersonated user) holds an exempt permission' do
        admin = create(:user, :admin, account: account)
        headers = impersonation_headers(impersonator: admin, impersonated_user: plain_user)

        get '/api/v1/auth/me', headers: headers, as: :json

        expect(response).not_to have_http_status(:service_unavailable)
      end

      it 'still blocks when NEITHER the impersonator nor the impersonated user is exempt' do
        non_admin_impersonator = create(:user, account: account, permissions: [])
        headers = impersonation_headers(impersonator: non_admin_impersonator, impersonated_user: plain_user)

        get '/api/v1/auth/me', headers: headers, as: :json

        expect(response).to have_http_status(:service_unavailable)
      end
    end

    it 'lets an admin.maintenance.mode holder reach the maintenance controller itself to disable it' do
      maintenance_admin = create(:user, account: account, permissions: [ 'admin.maintenance.mode' ])

      post '/api/v1/admin/maintenance/mode', params: { enabled: false }, headers: auth_headers_for(maintenance_admin), as: :json

      expect(response).not_to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)['data']['enabled']).to be false
    end
  end

  describe 'disabling restores normal responses' do
    it 'serves normally again once the flag is turned off' do
      Admin::MaintenanceMode.enable!(message: 'Upgrading')
      Admin::MaintenanceMode.invalidate_cache!
      get_me(plain_user)
      expect(response).to have_http_status(:service_unavailable)

      Admin::MaintenanceMode.disable!
      Admin::MaintenanceMode.invalidate_cache!
      get_me(plain_user)

      expect(response).not_to have_http_status(:service_unavailable)
    end
  end
end
