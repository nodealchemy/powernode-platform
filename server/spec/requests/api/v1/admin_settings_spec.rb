# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AdminSettings', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_settings_view) { create(:user, account: account, permissions: [ 'admin.settings.read' ]) }
  let(:user_with_settings_update) { create(:user, account: account, permissions: [ 'admin.settings.read', 'admin.settings.update' ]) }
  let(:user_with_account_suspend) { create(:user, account: account, permissions: [ 'admin.settings.read', 'admin.account.suspend' ]) }
  let(:user_with_security_permission) { create(:user, account: account, permissions: [ 'admin.settings.read', 'admin.settings.security' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/admin_settings' do
    context 'with admin.settings.read permission' do
      let(:headers) { auth_headers_for(user_with_settings_view) }

      it 'returns admin overview' do
        get '/api/v1/admin_settings', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without required permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/admin_settings', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin_settings', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PUT /api/v1/admin_settings' do
    let(:valid_params) do
      {
        admin_settings: {
          maintenance_mode: false,
          registration_enabled: true,
          session_timeout_minutes: 60
        }
      }
    end

    context 'with admin.settings.update permission' do
      let(:headers) { auth_headers_for(user_with_settings_update) }

      before do
        allow(Audit::LoggingService.instance).to receive(:log).and_return(nil)
      end

      it 'updates admin settings' do
        put '/api/v1/admin_settings',
            params: valid_params,
            headers: headers,
            as: :json

        expect_success_response
      end
    end

    context 'with only admin.settings.read permission' do
      let(:headers) { auth_headers_for(user_with_settings_view) }

      it 'returns forbidden error (read tier must not write)' do
        put '/api/v1/admin_settings',
            params: valid_params,
            headers: headers,
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/admin_settings/users' do
    let(:headers) { auth_headers_for(user_with_settings_view) }

    before do
      create_list(:user, 3, account: account)
    end

    it 'returns users data' do
      get '/api/v1/admin_settings/users', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('users')
      expect(response_data['data']).to have_key('total_count')
      expect(response_data['data']).to have_key('active_count')
    end

    it 'includes user status counts' do
      get '/api/v1/admin_settings/users', headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']).to include('active_count', 'inactive_count', 'suspended_count')
    end
  end

  describe 'GET /api/v1/admin_settings/accounts' do
    let(:headers) { auth_headers_for(user_with_settings_view) }

    it 'returns accounts data' do
      get '/api/v1/admin_settings/accounts', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('accounts')
      expect(response_data['data']).to have_key('total_count')
    end

    it 'includes account status counts' do
      get '/api/v1/admin_settings/accounts', headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']).to include('active_count', 'suspended_count', 'cancelled_count')
    end
  end

  describe 'GET /api/v1/admin_settings/system_logs' do
    let(:headers) { auth_headers_for(user_with_settings_view) }

    before do
      create_list(:audit_log, 5, account: account, user: admin_user, action: 'admin_settings_update')
    end

    it 'returns system logs' do
      get '/api/v1/admin_settings/system_logs', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('logs')
      expect(response_data['data']).to have_key('total_count')
    end
  end

  describe 'POST /api/v1/admin_settings/suspend_account' do
    let(:headers) { auth_headers_for(user_with_account_suspend) }
    let(:target_account) { create(:account) }

    it 'suspends an account' do
      post '/api/v1/admin_settings/suspend_account',
           params: { account_id: target_account.id, reason: 'Violation of terms' },
           headers: headers,
           as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/admin_settings/activate_account' do
    let(:headers) { auth_headers_for(user_with_account_suspend) }
    let(:target_account) { create(:account, status: 'suspended') }

    it 'activates a suspended account' do
      post '/api/v1/admin_settings/activate_account',
           params: { account_id: target_account.id, reason: 'Issue resolved' },
           headers: headers,
           as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin_settings/security' do
    context 'with admin.settings.security permission' do
      let(:headers) { auth_headers_for(user_with_security_permission) }

      it 'returns security configuration' do
        get '/api/v1/admin_settings/security', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without security permission' do
      let(:headers) { auth_headers_for(user_with_settings_view) }

      it 'returns forbidden error' do
        get '/api/v1/admin_settings/security', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/admin_settings/security' do
    let(:headers) { auth_headers_for(user_with_security_permission) }

    context 'with admin.settings.security permission' do
      let(:security_params) do
        {
          security_config: {
            authentication: {
              max_failed_attempts: 5,
              lockout_duration: 30
            }
          }
        }
      end

      before do
        allow_any_instance_of(Admin::SecurityConfigService).to receive(:update_config).and_return({
          success: true,
          config: { authentication: { max_failed_attempts: 5 } },
          message: 'Security configuration updated successfully'
        })
      end

      it 'updates security configuration' do
        put '/api/v1/admin_settings/security',
            params: security_params,
            headers: headers,
            as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/admin_settings/security/test' do
    let(:headers) { auth_headers_for(user_with_security_permission) }

    it 'tests security configuration' do
      post '/api/v1/admin_settings/security/test', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin_settings/security/blacklist_stats' do
    let(:headers) { auth_headers_for(user_with_security_permission) }

    it 'returns blacklist statistics' do
      get '/api/v1/admin_settings/security/blacklist_stats', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin_settings/security/audit_summary' do
    let(:headers) { auth_headers_for(user_with_security_permission) }

    before do
      allow_any_instance_of(Admin::SecurityConfigService).to receive(:security_audit_summary).and_return({
        period_days: 30,
        events_by_type: {},
        failed_logins_by_day: {},
        locked_accounts: 0,
        users_with_2fa: 0,
        recent_password_changes: 0
      })
    end

    it 'returns security audit summary' do
      get '/api/v1/admin_settings/security/audit_summary', headers: headers, as: :json

      expect_success_response
    end

    it 'accepts days parameter' do
      get '/api/v1/admin_settings/security/audit_summary?days=7',
          headers: headers,
          as: :json

      expect_success_response
    end
  end

  describe 'PUT /api/v1/admin_settings/extensions/:slug/toggle' do
    let(:headers) { auth_headers_for(user_with_settings_update) }
    # Needs a slug meeting BOTH of the endpoint's requirements: a manifest on
    # disk, and a `feature_flag` in that manifest (without one the controller
    # returns "does not support toggling" and never reaches the state store).
    # 'system' is the only PUBLIC extension satisfying both — marketing and
    # supply-chain declare no feature_flag.
    #
    # Public matters: they are submodules present in every full checkout,
    # whereas extensions/private is legitimately empty on a freshly-provisioned
    # node. Naming a private slug made these three pass on a developer box and
    # fail on the sandbox (two-machine parity run) — an environment difference
    # reported as a test failure. Which extension is toggled is irrelevant to
    # what these assert, and the state store is stubbed regardless.
    let(:slug) { 'system' }

    before do
      allow(Audit::LoggingService.instance).to receive(:log).and_return(nil)
      allow(Shared::ExtensionStateStore).to receive(:set_disabled!).and_return('disabled' => [])
    end

    context 'when disabling an extension' do
      it 'persists the disable to the state store' do
        put "/api/v1/admin_settings/extensions/#{slug}/toggle",
            params: { enabled: false }.to_json,
            headers: headers.merge('Content-Type' => 'application/json')

        expect(Shared::ExtensionStateStore).to have_received(:set_disabled!)
          .with(slug, disabled: true)
      end

      it 'returns requires_restart and requires_frontend_rebuild flags' do
        put "/api/v1/admin_settings/extensions/#{slug}/toggle",
            params: { enabled: false }.to_json,
            headers: headers.merge('Content-Type' => 'application/json')

        body = JSON.parse(response.body)
        expect(body.dig('data', 'requires_restart')).to be true
        expect(body.dig('data', 'requires_frontend_rebuild')).to be true
        expect(body.dig('data', 'slug')).to eq(slug)
      end
    end

    context 'when re-enabling an extension whose engine is not currently loaded' do
      # Regression: the previous implementation rejected toggling whenever the
      # engine wasn't in the registry, which made re-enabling impossible after
      # a load-time disable. With the state-file-based gate, this must succeed.
      it 'allows the toggle when the manifest exists on disk' do
        allow(Powernode::ExtensionRegistry).to receive(:loaded?).with(slug).and_return(false)

        put "/api/v1/admin_settings/extensions/#{slug}/toggle",
            params: { enabled: true }.to_json,
            headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        expect(Shared::ExtensionStateStore).to have_received(:set_disabled!)
          .with(slug, disabled: false)
      end
    end

    context 'when the extension manifest does not exist' do
      it 'returns not_found' do
        put '/api/v1/admin_settings/extensions/does-not-exist/toggle',
            params: { enabled: false }.to_json,
            headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:not_found)
        expect(Shared::ExtensionStateStore).not_to have_received(:set_disabled!)
      end
    end
  end

  # ===========================================================================
  # WRITE-ACTION AUTHORIZATION
  #
  # The class-wide `admin.settings.read` gate authorizes READS. Each WRITE
  # action must additionally require a write-tier permission. Without these
  # guards, a read-only admin can suspend accounts, rewrite Vault credentials,
  # toggle extensions, and mutate system settings — the vulnerability under fix.
  #
  # For each write action: a holder of ONLY 'admin.settings.read' must get 403;
  # a holder of the REQUIRED write permission must NOT get 403 (the request may
  # still 200/422/4xx for unrelated reasons, but it must pass the authz gate).
  # ===========================================================================
  describe 'write-action authorization' do
    before do
      allow(Audit::LoggingService.instance).to receive(:log).and_return(nil)
    end

    let(:read_only_headers) { auth_headers_for(user_with_settings_view) }

    describe 'PUT /api/v1/admin_settings (update) requires admin.settings.update' do
      let(:params) { { admin_settings: { maintenance_mode: false } } }

      it 'forbids a read-only admin' do
        put '/api/v1/admin_settings', params: params, headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.settings.update' do
        put '/api/v1/admin_settings', params: params,
            headers: auth_headers_for(user_with_settings_update), as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end

    describe 'PUT /api/v1/admin_settings/extensions/:slug/toggle requires admin.settings.update' do
      let(:slug) { 'business' }

      before do
        allow(Shared::ExtensionStateStore).to receive(:set_disabled!).and_return('disabled' => [])
      end

      it 'forbids a read-only admin' do
        put "/api/v1/admin_settings/extensions/#{slug}/toggle",
            params: { enabled: false }.to_json,
            headers: read_only_headers.merge('Content-Type' => 'application/json')
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.settings.update' do
        put "/api/v1/admin_settings/extensions/#{slug}/toggle",
            params: { enabled: false }.to_json,
            headers: auth_headers_for(user_with_settings_update).merge('Content-Type' => 'application/json')
        expect(response).not_to have_http_status(:forbidden)
      end
    end

    describe 'PUT /api/v1/admin_settings/development (update_development) requires admin.settings.update' do
      let(:params) { { slug: 'business', enabled: false } }

      it 'forbids a read-only admin' do
        put '/api/v1/admin_settings/development', params: params, headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.settings.update' do
        put '/api/v1/admin_settings/development', params: params,
            headers: auth_headers_for(user_with_settings_update), as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end

    describe 'POST /api/v1/admin_settings/suspend_account requires admin.account.suspend' do
      let(:target_account) { create(:account) }
      let(:params) { { account_id: target_account.id, reason: 'Violation of terms' } }

      it 'forbids a read-only admin' do
        post '/api/v1/admin_settings/suspend_account', params: params, headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.account.suspend' do
        post '/api/v1/admin_settings/suspend_account', params: params,
             headers: auth_headers_for(user_with_account_suspend), as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end

    describe 'POST /api/v1/admin_settings/activate_account requires admin.account.suspend' do
      let(:target_account) { create(:account, status: 'suspended') }
      let(:params) { { account_id: target_account.id, reason: 'Issue resolved' } }

      it 'forbids a read-only admin' do
        post '/api/v1/admin_settings/activate_account', params: params, headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.account.suspend' do
        post '/api/v1/admin_settings/activate_account', params: params,
             headers: auth_headers_for(user_with_account_suspend), as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end

    describe 'PUT /api/v1/admin_settings/infrastructure (update_infrastructure_config) requires admin.settings.security' do
      let(:params) { { redis: { host: '127.0.0.1', port: 6379 } } }

      it 'forbids a read-only admin' do
        put '/api/v1/admin_settings/infrastructure', params: params, headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.settings.security' do
        put '/api/v1/admin_settings/infrastructure', params: params,
            headers: auth_headers_for(user_with_security_permission), as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end

    describe 'PUT /api/v1/admin_settings/vault (update_vault_config) requires admin.settings.security' do
      let(:params) { { vault: { vault_addr: 'http://vault.example.internal:8200' } } }

      it 'forbids a read-only admin' do
        put '/api/v1/admin_settings/vault', params: params, headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.settings.security' do
        put '/api/v1/admin_settings/vault', params: params,
            headers: auth_headers_for(user_with_security_permission), as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end

  # Envelope characterization for the vault admin-settings actions: these must
  # return the standard { success:, data: } envelope (render_success) even on
  # infrastructure-failure paths (webhook-style soft errors inside a 200).
  describe 'GET /api/v1/admin_settings/vault (vault_config)' do
    let(:headers) { auth_headers_for(user_with_settings_view) }

    it 'returns the standard success envelope with status/config/keys even when Vault is unavailable' do
      allow(Security::VaultClient).to receive(:instance).and_raise(StandardError, 'vault down')

      get '/api/v1/admin_settings/vault', headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be(true)
      expect(body['data'].keys).to include('status', 'config', 'keys')
      expect(body['data']['status']['connected']).to be(false)
    end
  end

  describe 'POST /api/v1/admin_settings/vault/test (test_vault_connection)' do
    let(:headers) { auth_headers_for(user_with_settings_view) }

    it 'returns a success envelope with connected:false and an error when config is missing' do
      allow(Security::VaultClient).to receive(:admin_setting_config).and_return({})
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('VAULT_ADDR').and_return(nil)
      allow(ENV).to receive(:[]).with('VAULT_ROLE_ID').and_return(nil)
      allow(ENV).to receive(:[]).with('VAULT_SECRET_ID').and_return(nil)

      post '/api/v1/admin_settings/vault/test', headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be(true)
      expect(body['data']['connected']).to be(false)
      expect(body['data']['error']).to include('Missing:')
    end

    it 'returns a success envelope with connected:false and latency when Vault is unreachable' do
      allow(Security::VaultClient).to receive(:admin_setting_config).and_return(
        'vault_addr' => 'http://vault.example.internal:8200',
        'vault_role_id' => 'test-role',
        'vault_secret_id' => 'test-secret'
      )
      failing_client = instance_double(Vault::Client)
      allow(failing_client).to receive(:auth).and_raise(Vault::HTTPConnectionError.new('http://vault.example.internal:8200', StandardError.new('refused')))
      allow(Vault::Client).to receive(:new).and_return(failing_client)

      post '/api/v1/admin_settings/vault/test', headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be(true)
      expect(body['data']['connected']).to be(false)
      expect(body['data']['error']).to include('Cannot reach Vault')
      expect(body['data']).to have_key('latency_ms')
    end

    # IMP-0f914db2c7cf — the connectivity half of "is this credential usable"
    # was already here (config-missing / unreachable / sealed, above). The two
    # cases it could NOT answer were PATH-ABSENT and PATH-PRESENT-BUT-WRONG-
    # SHAPE, which is exactly the pair a GitOps operator hits: the sync path
    # reads {password} for an https remote and {ssh_key} for ssh, and a payload
    # missing that key produced a git-flavoured error with no Vault in it.
    #
    # The probe is additive — omitting `path` leaves every example above
    # unchanged — and reports PRESENCE, SHAPE and KEY NAMES only. Never a value.
    describe 'credential-path probe (params[:path])' do
      let(:headers) { auth_headers_for(user_with_security_permission) }
      let(:path) { 'secret/data/powernode/gitops/deploy' }

      def stub_reachable_vault(sealed: false)
        allow(Security::VaultClient).to receive(:admin_setting_config).and_return(
          'vault_addr' => 'http://vault.example.internal:8200',
          'vault_role_id' => 'test-role',
          'vault_secret_id' => 'test-secret'
        )
        health = Object.new
        health.instance_variable_set(:@sealed, sealed)
        health.instance_variable_set(:@initialized, true)
        health.instance_variable_set(:@version, '1.15.0')
        client = instance_double(Vault::Client)
        allow(client).to receive(:auth).and_return(double(approle: true))
        allow(client).to receive(:sys).and_return(double(health_status: health))
        allow(Vault::Client).to receive(:new).and_return(client)
        allow(Security::VaultClient).to receive(:reconfigure!)
      end

      def probe(required_keys: nil, as: headers)
        body = { path: path }
        body[:required_keys] = required_keys unless required_keys.nil?
        post '/api/v1/admin_settings/vault/test', params: body, headers: as, as: :json
        response.parsed_body['data']
      end

      # Found by review, and it would have been a platform outage: a denied
      # policy on the probed path is a Vault::HTTPError, which read_secret
      # counts via record_failure against the SHARED `vault` circuit breaker
      # (failure_threshold 3, reset_timeout 5min, state in Rails.cache). Three
      # probes of an unreadable path would have taken Vault offline for every
      # consumer in the platform — and the doc tells the operator to re-probe
      # after fixing the policy. A diagnostic must not be able to break the
      # thing it diagnoses, so the probe reads through probe_secret, which
      # neither checks nor records breaker state.
      it 'does not touch the shared Vault circuit breaker' do
        stub_reachable_vault
        expect(Security::VaultClient).not_to receive(:read_secret)
        expect(Security::VaultClient).to receive(:probe_secret).with(path).and_return({})

        probe(required_keys: %w[password])

        expect(response).to have_http_status(:ok)
      end

      it 'reports path_present:false when the KV path does not exist' do
        stub_reachable_vault
        allow(Security::VaultClient).to receive(:probe_secret)
          .and_raise(Security::VaultClient::SecretNotFoundError, "Secret not found: #{path}")

        data = probe(required_keys: %w[password])

        expect(response).to have_http_status(:ok)
        expect(data['connected']).to be(true)
        expect(data['credential_path']).to eq(path)
        expect(data['path_present']).to be(false)
        expect(data['shape_ok']).to be(false)
      end

      it 'reports the key NAMES and shape_ok:true when the payload satisfies the requirement' do
        stub_reachable_vault
        allow(Security::VaultClient).to receive(:probe_secret)
          .and_return({ 'username' => 'deploy-bot', 'password' => 'hunter2' })

        data = probe(required_keys: %w[password])

        expect(data['path_present']).to be(true)
        expect(data['credential_keys']).to eq(%w[password username])
        expect(data['missing_keys']).to eq([])
        expect(data['shape_ok']).to be(true)
        # The leak oracle belongs on THIS arm too — it is the arm where the
        # payload actually contains the value a leak would carry.
        expect(response.body).not_to include('hunter2')
      end

      # Without a requirement there is nothing to compare, so `shape_ok: true`
      # would be a pass mark awarded for no test — the one state the method's
      # fail-closed contract says cannot happen, and it would also turn the
      # endpoint into an unqualified key-name enumerator for any KV path.
      it 'declines to judge the shape when no required_keys are supplied' do
        stub_reachable_vault
        allow(Security::VaultClient).to receive(:probe_secret)
          .and_return({ 'username' => 'deploy-bot' })

        data = probe

        expect(data['path_present']).to be(true)
        expect(data['credential_keys']).to eq(%w[username])
        expect(data['shape_ok']).to be_nil
        expect(data['path_error']).to include('required_keys')
      end

      it 'declines to judge the shape for an explicitly empty requirement' do
        stub_reachable_vault
        allow(Security::VaultClient).to receive(:probe_secret).and_return({ 'username' => 'x' })

        expect(probe(required_keys: [])['shape_ok']).to be_nil
      end

      # THE ORACLE. A probe hardcoded to return ok passes every example above.
      # This is the arm the whole task exists for: the path resolves, but not
      # to the key the repository's auth mode needs.
      it 'reports shape_ok:false naming the MISSING key when the payload is wrong-shaped' do
        stub_reachable_vault
        allow(Security::VaultClient).to receive(:probe_secret)
          .and_return({ 'username' => 'deploy-bot', 'token' => 'ghp_leakme' })

        data = probe(required_keys: %w[password])

        expect(data['path_present']).to be(true)
        expect(data['shape_ok']).to be(false)
        expect(data['missing_keys']).to eq(%w[password])
        expect(data['credential_keys']).to eq(%w[token username])
      end

      it 'never transmits a credential VALUE, on any arm' do
        stub_reachable_vault
        allow(Security::VaultClient).to receive(:probe_secret)
          .and_return({ 'username' => 'deploy-bot', 'token' => 'ghp_leakme' })

        probe(required_keys: %w[password])

        expect(response.body).not_to include('ghp_leakme')
        expect(response.body).not_to include('deploy-bot')
      end

      # Mirrors RepoSyncService#require_creds!, which rejects a blank value:
      # `password.to_s` is already "" for nil, so a present-but-empty key
      # reproduces the blank-password auth attempt exactly. Presence of the KEY
      # is not the property; a usable VALUE is.
      it 'treats a present-but-blank value as missing' do
        stub_reachable_vault
        allow(Security::VaultClient).to receive(:probe_secret)
          .and_return({ 'username' => 'deploy-bot', 'password' => '' })

        data = probe(required_keys: %w[password])

        expect(data['shape_ok']).to be(false)
        expect(data['missing_keys']).to eq(%w[password])
      end

      it 'fails closed when the payload is not a Hash' do
        stub_reachable_vault
        allow(Security::VaultClient).to receive(:probe_secret).and_return('a-bare-string')

        data = probe(required_keys: %w[password])

        expect(data['path_present']).to be(true)
        expect(data['shape_ok']).to be(false)
        expect(data['path_error']).to include('String')
      end

      # The message is the REAL vault-ruby shape, not a hand-written short one:
      # Vault::HTTPError leads with ~140 chars of boilerplate before the errors
      # list, and VaultClient prepends another 24. A leading truncate(200)
      # keeps only the boilerplate and discards the one line the operator
      # needs, while a stubbed 45-char message hides that entirely.
      it 'fails closed on a read error, keeping the REASON rather than the boilerplate' do
        stub_reachable_vault
        realistic = "Vault connection error: The Vault server at `https://vault.example.internal:8200' " \
                    "responded with a 403.\nAny additional information the server supplied is shown " \
                    "below:\n\n  * 1 error occurred:\n\t* permission denied\n\n"
        allow(Security::VaultClient).to receive(:probe_secret)
          .and_raise(Security::VaultClient::ConnectionError, realistic)

        data = probe(required_keys: %w[password])

        # path_present must be REPORTED as null, not merely absent: it is what
        # distinguishes "the read failed" from "the path is not there".
        expect(data).to have_key('path_present')
        expect(data['path_present']).to be_nil
        expect(data['shape_ok']).to be(false)
        expect(data['path_error']).to include('permission denied')
      end

      # The four cases stay DISTINCT. A sealed or unreachable Vault must not be
      # answered as "the path is missing" — collapsing them reproduces the dead
      # end this thread started from.
      it 'does not probe the path at all when Vault is sealed' do
        stub_reachable_vault(sealed: true)
        expect(Security::VaultClient).not_to receive(:probe_secret)

        data = probe(required_keys: %w[password])

        expect(data['connected']).to be(false)
        expect(data['sealed']).to be(true)
        expect(data).not_to have_key('path_present')
      end

      it 'does not probe the path at all when Vault is unreachable' do
        allow(Security::VaultClient).to receive(:admin_setting_config).and_return(
          'vault_addr' => 'http://vault.example.internal:8200',
          'vault_role_id' => 'test-role', 'vault_secret_id' => 'test-secret'
        )
        failing = instance_double(Vault::Client)
        allow(failing).to receive(:auth).and_raise(
          Vault::HTTPConnectionError.new('http://vault.example.internal:8200', StandardError.new('refused'))
        )
        allow(Vault::Client).to receive(:new).and_return(failing)
        expect(Security::VaultClient).not_to receive(:probe_secret)

        data = probe(required_keys: %w[password])

        expect(data['connected']).to be(false)
        expect(data['error']).to include('Cannot reach Vault')
        expect(data).not_to have_key('path_present')
      end

      # Reading which key names live at an arbitrary KV path is a disclosure,
      # small but real. The class-level gate on this controller is only
      # `admin.settings.read`; probing a path requires the same
      # `admin.settings.security` the other Vault actions require.
      it 'refuses a path probe from a holder of only admin.settings.read' do
        expect(Security::VaultClient).not_to receive(:probe_secret)

        probe(required_keys: %w[password], as: auth_headers_for(user_with_settings_view))

        expect(response).to have_http_status(:forbidden)
      end

      it 'still answers plain connectivity for a read-only holder (no path given)' do
        stub_reachable_vault

        post '/api/v1/admin_settings/vault/test',
             headers: auth_headers_for(user_with_settings_view), as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('data', 'connected')).to be(true)
      end
    end
  end

  # ===========================================================================
  # SECURITY-CONFIG ACTION AUTHORIZATION
  #
  # The class-wide `admin.settings.read` gate authorizes READS. Each
  # security-config action must additionally require `admin.settings.security`.
  #
  # The bug under fix: the security actions enforced this with an INLINE
  # `require_permission("admin.settings.security")` as the first line of the
  # action body. render_forbidden only RENDERS — it does NOT halt — so for a
  # holder of only `admin.settings.read` the class-level before_action passes,
  # the inline check renders a 403 but the body keeps running, the privileged
  # mutation executes, and the trailing render then double-renders. The
  # `jwt_secret_rotation` cache assertion proves the mutator ran despite the 403.
  # ===========================================================================
  describe 'security-config action authorization' do
    before do
      allow(Audit::LoggingService.instance).to receive(:log).and_return(nil)
      # Clear the rotation cache so we can assert the mutator did NOT write it.
      Rails.cache.delete('jwt_secret_rotation')
    end

    let(:read_only_headers) { auth_headers_for(user_with_settings_view) }
    let(:security_headers) { auth_headers_for(user_with_security_permission) }

    describe 'POST /api/v1/admin_settings/security/regenerate_jwt_secret' do
      it 'forbids a read-only admin' do
        post '/api/v1/admin_settings/security/regenerate_jwt_secret',
             headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'does not regenerate the JWT secret for a read-only admin (no side-effect)' do
        post '/api/v1/admin_settings/security/regenerate_jwt_secret',
             headers: read_only_headers, as: :json
        # Under the bug the mutator runs despite the 403 and writes this key.
        expect(Rails.cache.read('jwt_secret_rotation')).to be_nil
      end

      it 'allows a holder of admin.settings.security' do
        post '/api/v1/admin_settings/security/regenerate_jwt_secret',
             headers: security_headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end

    describe 'PUT /api/v1/admin_settings/security (update_security_config)' do
      let(:params) { { security_config: { jwt: { access_token_ttl: 999 } } } }

      it 'forbids a read-only admin' do
        put '/api/v1/admin_settings/security', params: params,
            headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.settings.security' do
        put '/api/v1/admin_settings/security', params: params,
            headers: security_headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end

    describe 'DELETE /api/v1/admin_settings/security/blacklisted_tokens (clear_blacklisted_tokens)' do
      it 'forbids a read-only admin' do
        delete '/api/v1/admin_settings/security/blacklisted_tokens',
               headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.settings.security' do
        delete '/api/v1/admin_settings/security/blacklisted_tokens',
               headers: security_headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end

    describe 'GET /api/v1/admin_settings/security (security_config, read)' do
      it 'forbids a read-only admin' do
        get '/api/v1/admin_settings/security', headers: read_only_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows a holder of admin.settings.security' do
        get '/api/v1/admin_settings/security', headers: security_headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end
end
