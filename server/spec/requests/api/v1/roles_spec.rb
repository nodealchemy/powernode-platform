# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Roles', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/roles' do
    let(:headers) { auth_headers_for(admin_user) }

    before do
      # Ensure some roles exist via sync
      Role.sync_from_config! if Role.count.zero?
    end

    context 'with admin.role.read permission' do
      it 'returns list of all roles' do
        get '/api/v1/roles', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to be_an(Array)
        expect(response_data['data'].length).to be > 0
      end

      it 'includes role permissions' do
        get '/api/v1/roles', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        first_role = response_data['data'].first
        expect(first_role).to include('id', 'name', 'description', 'permissions')
      end

      it 'indicates system roles' do
        get '/api/v1/roles', headers: headers, as: :json

        response_data = json_response
        role_with_system_flag = response_data['data'].find { |r| r.key?('system_role') }
        expect(role_with_system_flag).to be_present
      end
    end

    # N14: role_data read role.users.count and role.role_permissions.pluck per
    # role (2 queries each). Those are now a single grouped user-count query and
    # eager-loaded grants. Verify users_count/permissions stay correct across
    # multiple roles, and that user-count queries don't scale with role count.
    context 'per-role aggregates across multiple roles (no N+1)' do
      let!(:role_alpha) do
        role = create(:role, name: 'fleetalpha', account_id: account.id)
        role.role_permissions.create!(permission_name: 'users.read')
        role.role_permissions.create!(permission_name: 'users.create')
        role
      end
      let!(:role_beta) do
        role = create(:role, name: 'fleetbeta', account_id: account.id)
        role.role_permissions.create!(permission_name: 'users.read')
        role
      end
      let!(:role_gamma) { create(:role, name: 'fleetgamma', account_id: account.id) }

      before do
        2.times { UserRole.create!(user: create(:user, account: account), role: role_alpha) }
        UserRole.create!(user: create(:user, account: account), role: role_beta)
      end

      def role_in(response_data, id)
        response_data['data'].find { |r| r['id'] == id }
      end

      it 'computes users_count and permissions correctly per role' do
        get '/api/v1/roles', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        alpha = role_in(response_data, role_alpha.id)
        expect(alpha['users_count']).to eq(2)
        expect(alpha['permissions'].map { |p| p['name'] }).to eq(%w[users.create users.read])

        beta = role_in(response_data, role_beta.id)
        expect(beta['users_count']).to eq(1)
        expect(beta['permissions'].map { |p| p['name'] }).to eq(%w[users.read])

        gamma = role_in(response_data, role_gamma.id)
        expect(gamma['users_count']).to eq(0)
        expect(gamma['permissions']).to eq([])
      end

      it 'does not issue more user-count queries as roles are added (no N+1)' do
        # Warm the acting user's permission cache first: the auth check also
        # touches user_roles, and that cost is cross-request cached — measuring
        # cold-vs-warm would mask the role-count signal we care about.
        get '/api/v1/roles', headers: headers, as: :json

        baseline = count_queries(/\buser_roles\b/) do
          get '/api/v1/roles', headers: headers, as: :json
        end

        3.times do |i|
          create(:role, name: "fleetextra#{%w[one two three][i]}", account_id: account.id)
        end

        grown = count_queries(/\buser_roles\b/) do
          get '/api/v1/roles', headers: headers, as: :json
        end

        expect(grown).to eq(baseline)
      end
    end

    context 'without admin.role.read permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/roles', headers: headers, as: :json

        expect_error_response('Permission denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/roles', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/roles/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:role) { Role.first || create(:role, :with_permissions) }

    context 'with admin.role.read permission' do
      it 'returns role details' do
        get "/api/v1/roles/#{role.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => role.id,
          'name' => role.name
        )
      end

      it 'includes permissions list' do
        get "/api/v1/roles/#{role.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('permissions')
        expect(response_data['data']['permissions']).to be_an(Array)
      end

      it 'includes users_count' do
        get "/api/v1/roles/#{role.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('users_count')
      end
    end

    context 'when role does not exist' do
      it 'returns not found error' do
        get '/api/v1/roles/nonexistent-id', headers: headers, as: :json

        expect_error_response('Role not found', 404)
      end
    end
  end

  describe 'GET /api/v1/roles/:id/users' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:role) { Role.find_by(name: 'member') || create(:role, name: 'member') }

    before do
      create_list(:user, 3, account: account).each do |user|
        user.add_role(role.name) unless user.has_role?(role.name)
      end
    end

    context 'with admin.role.read permission' do
      it 'returns users with the role' do
        get "/api/v1/roles/#{role.id}/users", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to be_an(Array)
        expect(response_data['data'].length).to be >= 3
      end

      it 'includes user details with roles' do
        get "/api/v1/roles/#{role.id}/users", headers: headers, as: :json

        response_data = json_response
        first_user = response_data['data'].first

        expect(first_user).to include('id', 'email', 'roles')
      end
    end
  end

  describe 'POST /api/v1/roles' do
    let(:headers) { auth_headers_for(admin_user) }

    context 'with admin.role.create permission' do
      let(:role_user) { create(:user, account: account, permissions: [ 'admin.role.create', 'admin.role.read' ]) }
      let(:role_headers) { auth_headers_for(role_user) }

      # The controller permits only :name and :description but Role validates :display_name presence.
      # We use a before_validation callback stub to auto-set display_name for testing.
      before do
        allow_any_instance_of(Role).to receive(:valid?).and_wrap_original do |m|
          m.receiver.display_name = m.receiver.name&.titleize if m.receiver.display_name.blank?
          m.call
        end
      end

      it 'creates a new custom role' do
        # Pre-materialize the role_user let (which creates roles via factory callbacks)
        # so the count change only measures the POST request
        role_headers

        expect {
          post '/api/v1/roles', params: { role: { name: 'custom_role', description: 'A custom test role' } },
               headers: role_headers, as: :json
        }.to change(Role, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['success']).to be true
        expect(response_data['data']['name']).to eq('custom_role')
      end

      it 'sets role as non-system role' do
        post '/api/v1/roles', params: { role: { name: 'custom_nonsys', description: 'A custom test role' } },
             headers: role_headers, as: :json

        response_data = json_response
        expect(response_data['data']['system_role']).to be false
      end

      it 'can assign permissions to role' do
        # Grants are by NAME; the user may only grant permissions it holds.
        post '/api/v1/roles',
             params: { role: { name: 'custom_perms', description: 'Test' }, permission_names: [ 'admin.role.read' ] },
             headers: role_headers, as: :json

        expect_success_response
        new_role = Role.find_by(name: 'custom_perms', account_id: account.id)
        expect(new_role.permission_names).to include('admin.role.read')
      end
    end

    context 'with invalid data' do
      it 'returns validation error for blank name' do
        post '/api/v1/roles',
             params: { role: { name: '', description: 'Test' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without admin.role.create permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        post '/api/v1/roles',
             params: { role: { name: 'test', description: 'Test' } },
             headers: headers,
             as: :json

        expect_error_response('Permission denied', 403)
      end
    end
  end

  describe 'PATCH /api/v1/roles/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    # Only account-scoped custom roles are editable; global (code) roles are read-only.
    let(:custom_role) { create(:role, name: 'editable_role', is_system: false, account_id: account.id) }

    context 'with admin.role.update permission' do
      it 'updates role description' do
        patch "/api/v1/roles/#{custom_role.id}",
              params: { role: { description: 'Updated description' } },
              headers: headers,
              as: :json

        expect_success_response

        custom_role.reload
        expect(custom_role.description).to eq('Updated description')
      end

      it 'updates role permissions by name' do
        patch "/api/v1/roles/#{custom_role.id}",
              params: { role: { description: 'Test' }, permission_names: [ 'users.read' ] },
              headers: headers,
              as: :json

        expect_success_response
        expect(custom_role.reload.permission_names).to include('users.read')
      end
    end

    context 'when updating a global (code-defined) role' do
      # account_id nil => global; the controller rejects edits to these.
      let(:global_role) { create(:role, name: 'global_code_role', role_type: 'user', account_id: nil) }

      it 'returns forbidden error' do
        patch "/api/v1/roles/#{global_role.id}",
              params: { role: { description: 'Hacked' } },
              headers: headers,
              as: :json

        expect_error_response('Global roles are code-defined and read-only', 403)
      end
    end

    context 'without admin.role.update permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        patch "/api/v1/roles/#{custom_role.id}",
              params: { role: { description: 'Hacked' } },
              headers: headers,
              as: :json

        expect_error_response('Permission denied', 403)
      end
    end
  end

  describe 'DELETE /api/v1/roles/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    # Only account-scoped custom roles can be deleted.
    let(:custom_role) { create(:role, name: 'deletable_role', is_system: false, account_id: account.id) }

    context 'with admin.role.delete permission' do
      it 'deletes the role successfully' do
        role_id = custom_role.id

        delete "/api/v1/roles/#{role_id}", headers: headers, as: :json

        expect_success_response
        expect(Role.find_by(id: role_id)).to be_nil
      end
    end

    context 'when role has assigned users' do
      before do
        user = create(:user, account: account)
        UserRole.create!(user: user, role: custom_role)
      end

      it 'returns conflict error' do
        delete "/api/v1/roles/#{custom_role.id}", headers: headers, as: :json

        expect_error_response('Cannot delete role that is assigned to users', 409)
      end
    end

    context 'when deleting a global (code-defined) role' do
      # account_id nil => global; the controller refuses to delete these.
      let(:global_role) { create(:role, name: 'global_undeletable_role', role_type: 'user', account_id: nil) }

      it 'returns forbidden error' do
        delete "/api/v1/roles/#{global_role.id}", headers: headers, as: :json

        expect_error_response('Global roles are code-defined and cannot be deleted', 403)
      end
    end
  end

  describe 'GET /api/v1/roles/assignable' do
    let(:headers) { auth_headers_for(admin_user) }

    it 'returns roles that can be assigned' do
      get '/api/v1/roles/assignable', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to be_an(Array)
    end

    it 'excludes system roles' do
      get '/api/v1/roles/assignable', headers: headers, as: :json

      response_data = json_response
      role_types = response_data['data'].map { |r| r['system_role'] }

      # All assignable roles should have system_role: false
      expect(role_types.compact.uniq).not_to include(true)
    end

    # Privilege-escalation defense (shared RoleAssignmentGuard): a non-admin may
    # only be offered roles whose effective permissions are a subset of their
    # own. A role granting a permission they do NOT hold must never be offered —
    # otherwise assigning it would escalate privilege. Characterizes the
    # `assignable` call site of the escalation guard.
    context 'privilege escalation (non-admin subset filtering)' do
      let(:limited_user) { create(:user, account: account, permissions: [ 'users.read' ]) }
      let(:limited_headers) { auth_headers_for(limited_user) }

      let!(:subset_role) do
        role = create(:role, name: 'assignable_subset', account_id: account.id)
        role.role_permissions.create!(permission_name: 'users.read')
        role
      end
      let!(:escalation_role) do
        role = create(:role, name: 'assignable_escalation', account_id: account.id)
        role.role_permissions.create!(permission_name: 'admin.role.delete')
        role
      end

      it 'offers roles whose permissions the user already holds' do
        get '/api/v1/roles/assignable', headers: limited_headers, as: :json

        names = json_response['data'].map { |r| r['name'] }
        expect(names).to include('assignable_subset')
      end

      it 'never offers a role granting a permission the user lacks' do
        get '/api/v1/roles/assignable', headers: limited_headers, as: :json

        names = json_response['data'].map { |r| r['name'] }
        expect(names).not_to include('assignable_escalation')
      end
    end
  end

  describe 'POST /api/v1/roles/:id/assign_to_user/:user_id' do
    let(:assign_user) { create(:user, account: account, permissions: [ 'admin.role.assign' ]) }
    let(:assign_headers) { auth_headers_for(assign_user) }
    let(:target_user) { create(:user, account: account) }
    let(:role) { create(:role, is_system: false) }

    context 'with admin.role.assign permission' do
      it 'assigns the role to the user and records the grantor' do
        post "/api/v1/roles/#{role.id}/assign_to_user/#{target_user.id}",
             headers: assign_headers,
             as: :json

        expect(target_user.reload.roles).to include(role)

        user_role = UserRole.find_by(user: target_user, role: role)
        expect(user_role).to be_present
        expect(user_role.granted_by_id).to eq(assign_user.id)
      end
    end

    context 'when user does not exist' do
      it 'returns not found error' do
        post "/api/v1/roles/#{role.id}/assign_to_user/nonexistent-id",
             headers: assign_headers,
             as: :json

        # find_user rescues RecordNotFound and renders 404 directly
        expect(response).to have_http_status(:not_found)
        expect(target_user.reload.roles).not_to include(role)
      end
    end

    context 'when role does not exist' do
      it 'returns not found error and assigns nothing' do
        roles_before = target_user.roles.to_a

        post "/api/v1/roles/nonexistent-id/assign_to_user/#{target_user.id}",
             headers: assign_headers,
             as: :json

        expect_error_response('Role not found', 404)
        expect(target_user.reload.roles).to match_array(roles_before)
      end
    end
  end

  describe 'DELETE /api/v1/roles/:id/remove_from_user/:user_id' do
    let(:assign_user) { create(:user, account: account, permissions: [ 'admin.role.assign' ]) }
    let(:assign_headers) { auth_headers_for(assign_user) }
    let(:target_user) { create(:user, account: account) }
    let(:role) { create(:role, is_system: false) }

    before do
      target_user.add_role(role.name)
    end

    context 'with admin.role.assign permission' do
      it 'removes the role from the user' do
        expect(target_user.roles).to include(role)

        delete "/api/v1/roles/#{role.id}/remove_from_user/#{target_user.id}",
               headers: assign_headers,
               as: :json

        expect(target_user.reload.roles).not_to include(role)
      end
    end

    context 'without permission' do
      let(:no_perm_headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error and does not remove the role' do
        delete "/api/v1/roles/#{role.id}/remove_from_user/#{target_user.id}",
               headers: no_perm_headers,
               as: :json

        expect_error_response('Permission denied', 403)
        expect(target_user.reload.roles).to include(role)
      end
    end
  end

  # Cross-tenant IDOR: an account admin with admin.role.assign must NOT be able to
  # target a user that belongs to a DIFFERENT account. find_user must scope to the
  # acting account's users, so a foreign user_id resolves to "User not found".
  describe 'cross-account role assignment (IDOR)' do
    let(:assign_user) { create(:user, account: account, permissions: [ 'admin.role.assign' ]) }
    let(:assign_headers) { auth_headers_for(assign_user) }
    let(:role) { create(:role, is_system: false) }

    let(:other_account) { create(:account) }
    let(:foreign_user) { create(:user, account: other_account) }

    it 'does not resolve a user in another account on assign_to_user' do
      post "/api/v1/roles/#{role.id}/assign_to_user/#{foreign_user.id}",
           headers: assign_headers,
           as: :json

      expect_error_response('User not found', 404)
    end

    it 'does not resolve a user in another account on remove_from_user' do
      delete "/api/v1/roles/#{role.id}/remove_from_user/#{foreign_user.id}",
             headers: assign_headers,
             as: :json

      expect_error_response('User not found', 404)
    end
  end
end
