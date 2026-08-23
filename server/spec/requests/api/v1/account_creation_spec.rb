# frozen_string_literal: true

require 'rails_helper'

# POST /api/v1/accounts — provisioning an additional TENANT account in core mode.
#
# The load-bearing oracle here is the AUTHORIZATION, not the creation. Every
# denial example asserts an ABSENCE OF EFFECT (`not_to change(Account, :count)`)
# rather than a status code: a controller that creates the row and *then*
# renders 403 passes a status assertion cleanly, and that exact shape has been
# found in this repository before. The status assertions that do appear are
# secondary and are never the only thing an example checks.
RSpec.describe 'Api::V1::Accounts create', type: :request do
  let(:account) { create(:account) }

  let(:valid_payload) do
    {
      account: {
        name: 'Federation Hub B',
        admin_email: 'hub-b-admin@example.com',
        admin_password: 'S3cure-Hub-B-Passw0rd!'
      }
    }
  end

  before(:each) do
    Rails.cache.clear
    # The code-defined role catalog is what decides who may create an account,
    # so every example resolves it from the real config rather than a fixture.
    Role.sync_from_config!
  end

  # ---------------------------------------------------------------------------
  # Who holds admin.account.create on a fresh install — verified by EXECUTING
  # the permission resolver against the real code-defined catalog, not assumed.
  # ---------------------------------------------------------------------------
  describe 'the admin.account.create grant' do
    it 'is a defined catalog permission (an undefined one would silently degrade to admin-only)' do
      expect(Permissions.all_permissions).to include('admin.account.create')
    end

    it 'is held by super_admin — the role a fresh core-mode install grants its first operator' do
      operator = create(:user, account: account, permissions: [])
      operator.roles << Role.find_by!(name: 'super_admin', account_id: nil)

      expect(operator.has_permission?('admin.account.create')).to be true
    end

    it 'is held by the platform admin role' do
      admin = create(:user, account: account, permissions: [])
      admin.roles << Role.find_by!(name: 'admin', account_id: nil)

      expect(admin.has_permission?('admin.account.create')).to be true
    end

    it 'is NOT held by a tenant owner — a tenant may not mint sibling tenancy boundaries' do
      owner = create(:user, account: account, permissions: [])
      owner.roles << Role.find_by!(name: 'owner', account_id: nil)

      expect(owner.has_permission?('admin.account.create')).to be false
    end

    it 'is NOT held by a member' do
      member = create(:user, account: account, permissions: [])
      member.roles << Role.find_by!(name: 'member', account_id: nil)

      expect(member.has_permission?('admin.account.create')).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Authorization oracle: absence of effect.
  # ---------------------------------------------------------------------------
  describe 'authorization' do
    context 'when the caller lacks admin.account.create' do
      let(:unprivileged) { create(:user, account: account, permissions: [ 'user.read' ]) }
      # let! so the caller (and their own account) exist BEFORE the expect block —
      # otherwise the lazily-created fixture itself moves Account.count and the
      # absence-of-effect oracle reports a change it did not cause.
      let!(:unprivileged_headers) { auth_headers_for(unprivileged) }

      it 'creates NO account' do
        expect {
          post '/api/v1/accounts', params: valid_payload, headers: unprivileged_headers, as: :json
        }.not_to change(Account, :count)
      end

      it 'creates NO user' do
        expect {
          post '/api/v1/accounts', params: valid_payload, headers: unprivileged_headers, as: :json
        }.not_to change(User, :count)
      end

      it 'writes NO account_created audit entry' do
        expect {
          post '/api/v1/accounts', params: valid_payload, headers: unprivileged_headers, as: :json
        }.not_to change(AuditLog.where(action: 'account_created'), :count)
      end

      it 'also reports 403 (secondary to the absence of effect above)' do
        post '/api/v1/accounts', params: valid_payload, headers: unprivileged_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when the caller is a tenant owner (holds admin.settings.update but not admin.account.create)' do
      let(:owner) do
        user = create(:user, account: account, permissions: [])
        user.roles << Role.find_by!(name: 'owner', account_id: nil)
        user
      end
      let!(:owner_headers) { auth_headers_for(owner) }

      it 'creates NO account' do
        expect {
          post '/api/v1/accounts', params: valid_payload, headers: owner_headers, as: :json
        }.not_to change(Account, :count)
      end
    end

    context 'when unauthenticated' do
      it 'creates NO account' do
        expect {
          post '/api/v1/accounts', params: valid_payload, as: :json
        }.not_to change(Account, :count)
      end
    end

    # A worker is the most interesting non-user principal: Worker#has_permission?
    # is an exact-name role join that does NOT expand system.admin, and the
    # controller additionally refuses any principal without a current_user. Both
    # are load-bearing, so the closed state is pinned here rather than left to
    # hold by accident.
    context 'when the caller is a worker principal presenting a forwarded mTLS identity' do
      let!(:worker) { create(:worker, account: account) }
      let(:worker_headers) do
        {
          'X-Forwarded-Tls-Client-Cert-Info' =>
            CGI.escape(%(Subject="CN=#{worker.node_instance_id}")),
          'Content-Type' => 'application/json'
        }
      end

      it 'creates NO account' do
        expect {
          post '/api/v1/accounts', params: valid_payload, headers: worker_headers, as: :json
        }.not_to change(Account, :count)
      end

      it 'writes NO account_created audit entry' do
        expect {
          post '/api/v1/accounts', params: valid_payload, headers: worker_headers, as: :json
        }.not_to change(AuditLog.where(action: 'account_created'), :count)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # The permitted path, and what "well-formed" means.
  # ---------------------------------------------------------------------------
  describe 'when the caller holds admin.account.create' do
    let(:operator) { create(:user, account: account, permissions: [ 'admin.account.create' ]) }
    # let! for the same reason as above: the caller must pre-exist so that every
    # `change(Account, :count)` delta is attributable to the request alone.
    let!(:headers) { auth_headers_for(operator) }

    it 'creates exactly one account' do
      expect {
        post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json
      }.to change(Account, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it 'creates the initial administrator inside the new account' do
      post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json

      created = Account.find(json_response['data']['id'])
      administrator = created.users.sole

      expect(administrator.email).to eq('hub-b-admin@example.com')
      expect(administrator.account_id).to eq(created.id)
    end

    it 'gives the initial administrator the account-scoped owner role, NOT super_admin' do
      post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json

      administrator = Account.find(json_response['data']['id']).users.sole

      expect(administrator.roles.map(&:name)).to include('owner')
      expect(administrator.roles.map(&:name)).not_to include('super_admin')
      expect(administrator.has_permission?('admin.account.create')).to be false
    end

    it 'leaves the administrator able to sign in — verified and holding real permissions' do
      post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json

      administrator = Account.find(json_response['data']['id']).users.sole

      expect(administrator.email_verified?).to be true
      expect(administrator.authenticate('S3cure-Hub-B-Passw0rd!')).to be_truthy
      expect(administrator.has_permission?('admin.settings.update')).to be true
    end

    # The strongest well-formedness oracle available: drive the REAL login
    # endpoint as the freshly created administrator. A tenant whose administrator
    # cannot sign in is the "half-usable account" this increment exists to avoid,
    # and no amount of row-shape assertion proves the negative.
    it 'produces a tenant whose administrator can actually sign in through the real auth endpoint' do
      post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json
      created_id = json_response['data']['id']

      post '/api/v1/auth/login',
           params: { email: 'hub-b-admin@example.com', password: 'S3cure-Hub-B-Passw0rd!' },
           as: :json

      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body['data']['access_token']).to be_present
      expect(body['data']['account']['id']).to eq(created_id)
      expect(body['data']['user']['permissions']).to include('admin.settings.update')
      # ...and that session must NOT carry platform-tier authority.
      expect(body['data']['user']['permissions']).not_to include('admin.account.create')
    end

    it 'derives a unique subdomain when none is supplied' do
      post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json
      first = Account.find(json_response['data']['id'])

      post '/api/v1/accounts',
           params: valid_payload.deep_merge(account: { admin_email: 'second@example.com' }),
           headers: headers, as: :json
      second = Account.find(json_response['data']['id'])

      expect(first.subdomain).to be_present
      expect(second.subdomain).to be_present
      expect(second.subdomain).not_to eq(first.subdomain)
    end

    it 'does NOT rebind the platform system worker to the new account' do
      system_worker = Workers::EnsureSystemWorker.call(account: account)
      skip 'no system worker in this environment' if system_worker.nil?

      expect {
        post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json
      }.not_to change { system_worker.reload.account_id }
    end

    it 'rolls the whole provision back when the administrator is invalid' do
      expect {
        post '/api/v1/accounts',
             params: valid_payload.deep_merge(account: { admin_email: 'not-an-email' }),
             headers: headers, as: :json
      }.to change(Account, :count).by(0)

      expect(response).to have_http_status(:unprocessable_content)
    end

    # A derived subdomain must satisfy Account's 3..30 length validation without
    # the operator ever seeing an error about a field they left blank.
    it 'clamps a derived subdomain down from an over-long account name' do
      post '/api/v1/accounts',
           params: valid_payload.deep_merge(
             account: { name: 'Acme Corporation International Holdings And Partners' }
           ),
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      created = Account.find(json_response['data']['id'])
      expect(created.subdomain.length).to be_between(3, 30)
    end

    it 'falls back to a valid stem when the account name slugifies too short' do
      post '/api/v1/accounts',
           params: valid_payload.deep_merge(account: { name: 'Ab' }),
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      created = Account.find(json_response['data']['id'])
      expect(created.subdomain.length).to be >= 3
    end

    it 'rejects a duplicate subdomain without creating anything' do
      existing = create(:account, subdomain: 'taken-subdomain')

      expect {
        post '/api/v1/accounts',
             params: valid_payload.deep_merge(account: { subdomain: existing.subdomain }),
             headers: headers, as: :json
      }.not_to change(Account, :count)
    end

    # -------------------------------------------------------------------------
    # Audit: the entry must actually land in the AuditLog table, attributed to
    # the acting operator and filed under the operator's account (that is the
    # trail a reviewer reads).
    # -------------------------------------------------------------------------
    describe 'audit' do
      it 'writes an account_created row to the audit log' do
        expect {
          post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json
        }.to change(AuditLog.where(action: 'account_created'), :count).by(1)
      end

      it 'attributes the row to the acting operator and their account, naming the new tenant' do
        post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json
        created_id = json_response['data']['id']

        entry = AuditLog.where(action: 'account_created').order(:created_at).last

        expect(entry.user_id).to eq(operator.id)
        expect(entry.account_id).to eq(account.id)
        expect(entry.resource_type).to eq('Account')
        expect(entry.resource_id).to eq(created_id)
        expect(entry.source).to eq('api')
        expect(entry.severity).to eq('high')
        expect(entry.new_values['administrator_email']).to eq('hub-b-admin@example.com')
      end

      it 'never records the administrator password' do
        post '/api/v1/accounts', params: valid_payload, headers: headers, as: :json

        entry = AuditLog.where(action: 'account_created').order(:created_at).last

        expect(entry.attributes.to_s).not_to include('S3cure-Hub-B-Passw0rd!')
      end
    end
  end
end
