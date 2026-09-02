# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Delegations', type: :request do
  let(:account) { create(:account) }
  let(:manager_user) do
    user = create(:user, :manager, account: account)
    # Delegation management requires accounts.manage; grant it BY NAME through
    # the user's role (permissions are code-defined, no Permission AR model).
    user.roles.first.role_permissions.find_or_create_by!(permission_name: 'accounts.manage')
    # A delegation may only carry authority the delegator already holds, so the
    # examples below that delegate `admin_role` need its permission held here.
    user.roles.first.role_permissions.find_or_create_by!(permission_name: 'users.create')
    user.reload
    user
  end
  # Create external user (different account) for delegation tests
  let(:external_account) { create(:account) }
  let(:delegated_user) { create(:user, account: external_account) }
  let(:headers) { auth_headers_for(manager_user) }
  let(:admin_role) do
    role = create(:role, name: 'account.admin', display_name: 'Account Admin', role_type: 'user')
    role.role_permissions.find_or_create_by!(permission_name: 'users.create')
    role
  end

  describe 'GET /api/v1/accounts/:account_id/delegations' do
    let!(:active_delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :active, account: account, delegated_by: manager_user, delegated_user: user)
    end
    let!(:inactive_delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :inactive, account: account, delegated_by: manager_user, delegated_user: user)
    end
    let!(:revoked_delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :revoked, account: account, delegated_by: manager_user, delegated_user: user)
    end

    it 'returns all delegations for the account' do
      get "/api/v1/accounts/#{account.id}/delegations", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['delegations'].size).to eq(3)
      expect(json['data']['meta']['total_count']).to eq(3)
      expect(json['data']['meta']['active_count']).to eq(1)
    end

    it 'filters delegations by status' do
      get "/api/v1/accounts/#{account.id}/delegations", params: { status: 'active' }, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['data']['delegations'].size).to eq(1)
      expect(json['data']['delegations'].first['status']).to eq('active')
    end

    it 'filters delegations by role_id' do
      role = create(:role, name: 'test.role', display_name: 'Test Role')
      user = create(:user, account: account)
      with_role = create(:account_delegation, account: account, delegated_by: manager_user, delegated_user: user, role: role)

      get "/api/v1/accounts/#{account.id}/delegations", params: { role_id: role.id }, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['data']['delegations'].size).to eq(1)
      expect(json['data']['delegations'].first['id']).to eq(with_role.id)
    end

    it 'requires authentication' do
      get "/api/v1/accounts/#{account.id}/delegations"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires account.manage permission' do
      # Explicitly permissionless: the first user in an account would otherwise
      # be auto-assigned the owner role (which holds accounts.manage).
      regular_user = create(:user, account: account, permissions: [])
      regular_headers = auth_headers_for(regular_user)

      get "/api/v1/accounts/#{account.id}/delegations", headers: regular_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/delegations/:id' do
    let(:delegation) do
      user = create(:user, account: account)
      create(:account_delegation, account: account, delegated_by: manager_user, delegated_user: user, role: admin_role)
    end

    it 'returns delegation details' do
      get "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['delegation']['id']).to eq(delegation.id)
      expect(json['data']['delegation']['delegated_user']['id']).to eq(delegation.delegated_user.id)
      expect(json['data']['delegation']['delegated_by']['id']).to eq(manager_user.id)
      expect(json['data']['delegation']['role']['id']).to eq(admin_role.id)
    end

    it 'allows delegated user to view their own delegation' do
      delegated_headers = auth_headers_for(delegation.delegated_user)

      get "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}", headers: delegated_headers

      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 for non-existent delegation' do
      get "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/delegations' do
    let(:delegation_params) do
      {
        delegation: {
          delegated_user_email: delegated_user.email,
          role_id: admin_role.id,
          expires_at: 30.days.from_now,
          notes: 'Test delegation'
        }
      }
    end

    it 'creates a new delegation' do
      expect {
        post "/api/v1/accounts/#{account.id}/delegations", params: delegation_params, headers: headers, as: :json
      }.to change(Account::Delegation, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Delegation created successfully')
      expect(json['data']['delegation']['delegated_user']['email']).to eq(delegated_user.email)
      expect(json['data']['delegation']['role']['id']).to eq(admin_role.id)
    end

    it 'creates delegation with role-based permissions' do
      # When role is specified, delegation inherits role permissions
      expect {
        post "/api/v1/accounts/#{account.id}/delegations", params: delegation_params, headers: headers, as: :json
      }.to change(Account::Delegation, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']['delegation']['role']['id']).to eq(admin_role.id)
      expect(json['data']['delegation']['permission_source']).to eq('role')
      # No specific delegation_permissions rows, so the delegation resolves to
      # the ROLE's set — and `permissions` reports what it CONFERS
      # (Account::Delegation#configured_permissions), not the stored rows.
      expect(json['data']['delegation']['permissions'].map { |p| p['name'] })
        .to match_array(admin_role.permission_names)
      expect(json['data']['delegation']['stale_permission_names']).to eq([])
    end

    it 'returns error for non-existent user email' do
      params = delegation_params.deep_merge(delegation: { delegated_user_email: 'nonexistent@example.com' })

      post "/api/v1/accounts/#{account.id}/delegations", params: params, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
    end

    it 'requires authentication' do
      post "/api/v1/accounts/#{account.id}/delegations", params: delegation_params, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires account.manage permission' do
      # Explicitly permissionless: the first user in an account would otherwise
      # be auto-assigned the owner role (which holds accounts.manage).
      regular_user = create(:user, account: account, permissions: [])
      regular_headers = auth_headers_for(regular_user)

      post "/api/v1/accounts/#{account.id}/delegations", params: delegation_params, headers: regular_headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/delegations/:id' do
    let(:delegation) do
      user = create(:user, account: account)
      create(:account_delegation, account: account, delegated_by: manager_user, delegated_user: user, role: admin_role, notes: 'Original notes')
    end
    let(:new_role) { create(:role, name: 'account.viewer', display_name: 'Account Viewer') }

    it 'updates delegation details' do
      patch "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}",
            params: { delegation: { role_id: new_role.id, notes: 'Updated notes' } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Delegation updated successfully')
      expect(json['data']['delegation']['role']['id']).to eq(new_role.id)
      expect(json['data']['delegation']['notes']).to eq('Updated notes')
    end

    it 'updates expiration date' do
      new_expiry = 60.days.from_now

      patch "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}",
            params: { delegation: { expires_at: new_expiry } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(Time.parse(json['data']['delegation']['expires_at'])).to be_within(1.second).of(new_expiry)
    end

    it 'returns 404 for non-existent delegation' do
      patch "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000",
            params: { delegation: { notes: 'Updated' } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/delegations/:id' do
    let(:delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :active, account: account, delegated_by: manager_user, delegated_user: user)
    end

    it 'revokes the delegation' do
      delete "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Delegation revoked successfully')
      expect(delegation.reload.status).to eq('revoked')
    end

    it 'returns 404 for non-existent delegation' do
      delete "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/delegations/:id/activate' do
    let(:delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :inactive, account: account, delegated_by: manager_user, delegated_user: user)
    end

    it 'activates the delegation' do
      patch "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/activate", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Delegation activated successfully')
      expect(json['data']['delegation']['status']).to eq('active')
    end

    it 'returns 404 for non-existent delegation' do
      patch "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000/activate", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/delegations/:id/deactivate' do
    let(:delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :active, account: account, delegated_by: manager_user, delegated_user: user)
    end

    it 'deactivates the delegation' do
      patch "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/deactivate", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Delegation deactivated successfully')
      expect(json['data']['delegation']['status']).to eq('inactive')
    end

    it 'returns 404 for non-existent delegation' do
      patch "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000/deactivate", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/delegations/:id/revoke' do
    let(:delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :active, account: account, delegated_by: manager_user, delegated_user: user)
    end

    it 'revokes the delegation' do
      patch "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/revoke", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Delegation revoked successfully')
      expect(json['data']['delegation']['status']).to eq('revoked')
      expect(json['data']['delegation']['revoked_at']).to be_present
      expect(json['data']['delegation']['revoked_by']['id']).to eq(manager_user.id)
    end

    it 'returns 404 for non-existent delegation' do
      patch "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000/revoke", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/delegations/available_permissions' do
    it 'returns all permissions when no role specified' do
      get "/api/v1/accounts/#{account.id}/delegations/available_permissions", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['permissions']).to be_an(Array)
    end

    it 'returns role-specific permissions when role_id provided' do
      get "/api/v1/accounts/#{account.id}/delegations/available_permissions", params: { role_id: admin_role.id }, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['permissions']).to be_an(Array)
      expect(json['data']['role_id']).to eq(admin_role.id)
    end
  end

  describe 'POST /api/v1/delegations/:id/permissions' do
    let(:delegation) do
      # Use external user for delegation WITHOUT role for granular permission control
      external_user = create(:user, account: external_account)
      create(:account_delegation, :active, account: account, delegated_by: manager_user, delegated_user: external_user, role: nil)
    end
    # Permissions are code-defined and referenced by NAME.
    let(:permission_name) { 'report.generate' }

    it 'adds permission to delegation without role' do
      post "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/permissions",
           params: { permission_name: permission_name },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Permission added successfully')
    end

    it 'returns error when delegation not found' do
      post "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000/permissions",
           params: { permission_name: permission_name },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/delegations/:id/permissions/:permission_name' do
    # :permission_name is a dotted catalog key the admin_role grants.
    let(:permission_name) { 'users.create' }
    let(:delegation) do
      user = create(:user, account: account)
      d = create(:account_delegation, :active, account: account, delegated_by: manager_user, delegated_user: user, role: admin_role)
      d.delegation_permissions.create!(permission_name: permission_name)
      d
    end

    it 'removes permission from delegation' do
      delete "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/permissions/#{permission_name}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Permission removed successfully')
    end

    it 'returns error when delegation not found' do
      delete "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000/permissions/#{permission_name}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  # Privilege escalation across every delegation write transport.
  #
  # A delegated session's authority IS the delegation: Authentication#has_permission?
  # short-circuits a JWT carrying a delegation_id straight to
  # Account::Delegation#effective_permissions, ahead of any role lookup. So whatever
  # a delegation carries is live authority in the target account, and the delegator
  # must only be able to confer authority it already holds — the same rule
  # Api::V1::RolesController#apply_permission_names enforces through
  # User#can_grant_permission? (held, and never the system tier).
  #
  # Every assertion below is on the stored ROW / effective_permissions, not on the
  # HTTP status: a guard that renders an error from an action body does not halt,
  # and the write can still land.
  describe 'privilege escalation on what a delegation may carry' do
    # manager_user holds the manager role + accounts.manage + users.create.
    let(:held_permission) { 'report.generate' }
    let(:unheld_permission) { 'admin.user.delete' }

    def post_delegation(permission_names: nil, role_id: nil)
      post "/api/v1/accounts/#{account.id}/delegations",
           params: {
             delegation: {
               delegated_user_email: delegated_user.email,
               permission_names: permission_names,
               role_id: role_id
             }.compact
           },
           headers: headers,
           as: :json
    end

    def conferred_permissions
      Account::Delegation.for_user(delegated_user).flat_map(&:effective_permissions)
    end

    it 'holds the premise: the delegator does not hold the escalation targets' do
      expect(manager_user.has_permission?('system.admin')).to be false
      expect(manager_user.has_permission?(unheld_permission)).to be false
      expect(manager_user.has_permission?(held_permission)).to be true
    end

    context 'POST /delegations (custom permission_names)' do
      it 'does not mint a delegation carrying system.admin' do
        expect { post_delegation(permission_names: [ 'system.admin' ]) }
          .not_to change(Account::Delegation, :count)

        expect(conferred_permissions).not_to include('system.admin')
      end

      it 'does not mint a delegation carrying a catalog permission the delegator lacks' do
        expect { post_delegation(permission_names: [ unheld_permission ]) }
          .not_to change(Account::DelegationPermission, :count)

        expect(conferred_permissions).not_to include(unheld_permission)
      end

      it 'still mints a delegation carrying a permission the delegator does hold' do
        expect { post_delegation(permission_names: [ held_permission ]) }
          .to change(Account::Delegation, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(conferred_permissions).to include(held_permission)
      end
    end

    context 'POST /delegations (role_id)' do
      it 'does not mint a delegation whose role grants a permission the delegator lacks' do
        escalating_role = create(:role, name: 'account.escalated', display_name: 'Escalated')
        escalating_role.role_permissions.find_or_create_by!(permission_name: unheld_permission)

        expect { post_delegation(role_id: escalating_role.id) }
          .not_to change(Account::Delegation, :count)

        expect(conferred_permissions).not_to include(unheld_permission)
      end

      it 'still mints a delegation whose role grants only permissions the delegator holds' do
        safe_role = create(:role, name: 'account.reporter', display_name: 'Reporter')
        safe_role.role_permissions.find_or_create_by!(permission_name: held_permission)

        expect { post_delegation(role_id: safe_role.id) }
          .to change(Account::Delegation, :count).by(1)

        expect(conferred_permissions).to include(held_permission)
      end

      # NO-LOCKOUT, and the reason the role half of this guard is NOT the
      # "grantable" (held-minus-system-tier) rule: extensions register real
      # system.* names onto the seeded global admin/manager roles, so a
      # grantable-based role test would make the platform's two broadest roles
      # undelegatable by everyone, including a system.admin holder. The shared
      # RoleAssignmentGuard rule is the one that matches this question.
      it 'still lets an admin delegate a seeded global role carrying system-tier permissions' do
        admin_delegator = create(:user, :admin, account: account)
        global_admin_role = Role.find_by(name: 'admin')

        expect(global_admin_role).to be_present
        expect(global_admin_role.permission_names.select { |n| n.start_with?('system.') }).not_to be_empty

        expect {
          post "/api/v1/accounts/#{account.id}/delegations",
               params: { delegation: { delegated_user_email: delegated_user.email,
                                       role_id: global_admin_role.id } },
               headers: auth_headers_for(admin_delegator),
               as: :json
        }.to change(Account::Delegation, :count).by(1)

        expect(response).to have_http_status(:created)
      end
    end

    context 'existing delegation write transports' do
      let(:existing_delegation) do
        d = create(:account_delegation, :active, account: account, delegated_by: manager_user,
                                                 delegated_user: delegated_user, role: nil)
        d.delegation_permissions.create!(permission_name: held_permission)
        d
      end

      it 'does not add an unheld permission through POST /delegations/:id/permissions' do
        expect {
          post "/api/v1/accounts/#{account.id}/delegations/#{existing_delegation.id}/permissions",
               params: { permission_name: unheld_permission },
               headers: headers,
               as: :json
        }.not_to change { existing_delegation.reload.permission_names.sort }

        expect(existing_delegation.reload.effective_permissions).not_to include(unheld_permission)
      end

      it 'still adds a held permission through POST /delegations/:id/permissions' do
        post "/api/v1/accounts/#{account.id}/delegations/#{existing_delegation.id}/permissions",
             params: { permission_name: 'report.export' },
             headers: headers,
             as: :json

        expect(existing_delegation.reload.permission_names).to include('report.export')
      end

      it 'does not widen an existing delegation through PATCH /delegations/:id' do
        expect {
          patch "/api/v1/accounts/#{account.id}/delegations/#{existing_delegation.id}",
                params: { delegation: { permission_names: [ unheld_permission ] } },
                headers: headers,
                as: :json
        }.not_to change { existing_delegation.reload.permission_names.sort }

        expect(existing_delegation.reload.effective_permissions).not_to include(unheld_permission)
      end

      it 'still rewrites an existing delegation to held permissions through PATCH /delegations/:id' do
        patch "/api/v1/accounts/#{account.id}/delegations/#{existing_delegation.id}",
              params: { delegation: { permission_names: [ 'report.export' ] } },
              headers: headers,
              as: :json

        expect(existing_delegation.reload.permission_names).to eq([ 'report.export' ])
      end
    end

    # RESIDUALS of this same escalation, disclosed by 4da742156's own executor
    # rather than swept in. Everything that commit added constrains what a write
    # ADDS. Two paths are not additions and were therefore left uncovered:
    #
    #   1. REMOVAL. Account::Delegation#effective_permissions falls back to the
    #      ROLE whenever the custom set is empty (to #role_backed_permissions —
    #      the role's grants bounded by the delegator since IMP-1635cb7fa768),
    #      so emptying the custom set PROMOTES the delegation off its pin. A
    #      call named "remove" can raise effective authority.
    #   2. ACTIVATION. activate_delegation re-validated nothing, so a row
    #      carrying authority its activator could not confer was honoured
    #      verbatim the moment it went active.
    #
    # Every assertion below is on effective_permissions, NEVER on the
    # delegation_permissions rows: the rows SHRINKING is exactly what makes the
    # effective set GROW, so a row-level assertion passes straight over item 1.
    # HTTP status is asserted alongside, so a green cannot come from a 500 or an
    # early return instead of the guard.
    context 'residual 1: removal must not widen the effective set' do
      def delete_permission(delegation, name)
        delete "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/permissions/#{name}",
               headers: headers
      end

      # Reachable through the PUBLIC API today, with no unheld permission
      # anywhere: a role plus a NARROWER custom subset of it. The delegator holds
      # every name involved, so this is not an escalation beyond the delegator —
      # the widening is intrinsic to the fallback.
      it 'does not promote a narrowed delegation to the role set when the last custom permission goes' do
        narrowing_role = create(:role, name: 'account.narrowed', display_name: 'Narrowed')
        narrowing_role.role_permissions.find_or_create_by!(permission_name: held_permission)
        narrowing_role.role_permissions.find_or_create_by!(permission_name: 'report.export')

        post_delegation(permission_names: [ held_permission ], role_id: narrowing_role.id)
        expect(response).to have_http_status(:created)

        delegation = Account::Delegation.for_user(delegated_user).first
        before_set = delegation.effective_permissions
        expect(before_set).to contain_exactly(held_permission)

        delete_permission(delegation, held_permission)

        after_set = delegation.reload.effective_permissions
        expect(after_set - before_set).to be_empty
        expect(after_set).not_to include('report.export')
        expect(response).to have_http_status(:unprocessable_content)
      end

      # The escalating flavour: a row whose ROLE carries a permission the
      # delegator does not hold, narrowed by a custom subset. Built directly
      # because the create guard now refuses to mint it — this is the shape a
      # pre-4da742156 row, or a role that later gained a permission, leaves behind.
      it 'does not promote a delegation to a role permission the remover does not hold' do
        escalating_role = create(:role, name: 'account.residual', display_name: 'Residual')
        escalating_role.role_permissions.find_or_create_by!(permission_name: held_permission)
        escalating_role.role_permissions.find_or_create_by!(permission_name: unheld_permission)

        delegation = create(:account_delegation, :active, account: account, delegated_by: manager_user,
                                                          delegated_user: delegated_user, role: escalating_role)
        delegation.delegation_permissions.create!(permission_name: held_permission)
        expect(delegation.effective_permissions).to contain_exactly(held_permission)

        delete_permission(delegation, held_permission)

        expect(delegation.reload.effective_permissions).not_to include(unheld_permission)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'still removes a permission when the removal genuinely narrows' do
        delegation = create(:account_delegation, :active, account: account, delegated_by: manager_user,
                                                          delegated_user: delegated_user, role: nil)
        delegation.delegation_permissions.create!(permission_name: held_permission)
        delegation.delegation_permissions.create!(permission_name: 'report.export')

        delete_permission(delegation, 'report.export')

        expect(response).to have_http_status(:ok)
        expect(delegation.reload.effective_permissions).to contain_exactly(held_permission)
      end

      # Emptying a role-LESS delegation leaves it carrying nothing. That narrows,
      # so it must stay allowed — the guard is "never widen", not "never empty".
      it 'still empties a role-less delegation down to no permissions' do
        delegation = create(:account_delegation, :active, account: account, delegated_by: manager_user,
                                                          delegated_user: delegated_user, role: nil)
        delegation.delegation_permissions.create!(permission_name: held_permission)

        delete_permission(delegation, held_permission)

        expect(response).to have_http_status(:ok)
        expect(delegation.reload.effective_permissions).to be_empty
      end
    end

    # SAME MECHANISM, DIFFERENT TRANSPORT — surfaced by the independent review of
    # the removal guard above, not by the brief. update_delegation rewrites the
    # custom set as destroy_all + assign_permission, and #assign_permission
    # returns false for a NON-ACTIVE delegation while update_delegation guards
    # only against `revoked?`. Ignoring that return value made "narrow this
    # delegation to [X]" wipe the custom set and add nothing back — which is
    # exactly the empty-set promotion the removal guard exists to prevent,
    # reached through a method that never calls remove_permission at all.
    context 'residual 1b: a permission REWRITE must not empty the custom set' do
      it 'does not promote an inactive delegation to its role set through a narrowing PATCH' do
        role = create(:role, name: 'account.rewrite', display_name: 'Rewrite')
        role.role_permissions.find_or_create_by!(permission_name: held_permission)
        role.role_permissions.find_or_create_by!(permission_name: 'report.export')
        # The activator must be able to confer the whole role, or the activation
        # re-check would refuse and mask the defect under test.
        expect(role.assignable_by?(manager_user)).to be true

        delegation = create(:account_delegation, :inactive, account: account, delegated_by: manager_user,
                                                            delegated_user: delegated_user, role: role)
        delegation.delegation_permissions.create!(permission_name: held_permission)

        patch "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}",
              params: { delegation: { permission_names: [ held_permission ] } },
              headers: headers,
              as: :json

        patch "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/activate", headers: headers

        expect(delegation.reload).to be_active
        expect(delegation.effective_permissions).to contain_exactly(held_permission)
      end
    end

    context 'residual 2: activation must re-check what the row already carries' do
      def activate(delegation, as_headers = headers)
        patch "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/activate", headers: as_headers
      end

      # NOTE ON THE ORACLE: #effective_permissions returns [] for any non-active
      # delegation, so "the activated set excludes X" would pass vacuously on a
      # refusal AND on a crash. The row's own status is asserted alongside it.
      it 'does not activate a row carrying a permission the activator cannot grant' do
        delegation = create(:account_delegation, :inactive, account: account, delegated_by: manager_user,
                                                            delegated_user: delegated_user, role: nil)
        delegation.delegation_permissions.create!(permission_name: unheld_permission)

        activate(delegation)

        expect(response).to have_http_status(:unprocessable_content)
        expect(delegation.reload).not_to be_active
        expect(delegation.effective_permissions).not_to include(unheld_permission)
      end

      it 'still activates a row carrying only permissions the activator holds' do
        delegation = create(:account_delegation, :inactive, account: account, delegated_by: manager_user,
                                                            delegated_user: delegated_user, role: nil)
        delegation.delegation_permissions.create!(permission_name: held_permission)

        activate(delegation)

        expect(response).to have_http_status(:ok)
        expect(delegation.reload).to be_active
        expect(delegation.effective_permissions).to include(held_permission)
      end

      # NO-LOCKOUT, for the same reason 4da742156 used the role-assignment rule
      # and not the grantable rule for whole-role conferral: extensions register
      # real system.* names onto the seeded global roles, so a grantable-based
      # test here would make them unactivatable by everyone, including an admin.
      it 'still activates a role-only delegation on a seeded global role carrying system-tier permissions' do
        admin_delegator = create(:user, :admin, account: account)
        global_admin_role = Role.find_by(name: 'admin')
        expect(global_admin_role).to be_present
        expect(global_admin_role.permission_names.select { |n| n.start_with?('system.') }).not_to be_empty

        delegation = create(:account_delegation, :inactive, account: account, delegated_by: admin_delegator,
                                                            delegated_user: delegated_user, role: global_admin_role)

        activate(delegation, auth_headers_for(admin_delegator))

        expect(response).to have_http_status(:ok)
        expect(delegation.reload).to be_active
      end
    end
  end
end
