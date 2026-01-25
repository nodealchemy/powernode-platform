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

    context 'with admin.role.view permission' do
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

    context 'without admin.role.view permission' do
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

    context 'with admin.role.view permission' do
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

    context 'with admin.role.view permission' do
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
      let(:valid_params) do
        {
          role: {
            name: 'custom_role',
            description: 'A custom test role'
          }
        }
      end

      it 'creates a new custom role' do
        expect {
          post '/api/v1/roles', params: valid_params, headers: headers, as: :json
        }.to change(Role, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['success']).to be true
        expect(response_data['data']['name']).to eq('custom_role')
      end

      it 'sets role as non-system role' do
        post '/api/v1/roles', params: valid_params, headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['system_role']).to be false
      end

      it 'can assign permissions to role' do
        permission = create(:permission)
        params_with_permissions = valid_params.deep_merge(permission_ids: [permission.id])

        post '/api/v1/roles', params: params_with_permissions, headers: headers, as: :json

        expect_success_response
        new_role = Role.find_by(name: 'custom_role')
        expect(new_role.permissions).to include(permission)
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
    let(:custom_role) { create(:role, name: 'editable_role', is_system: false) }

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

      it 'updates role permissions' do
        permission = create(:permission)

        patch "/api/v1/roles/#{custom_role.id}",
              params: { role: { description: 'Test' }, permission_ids: [permission.id] },
              headers: headers,
              as: :json

        expect_success_response
        expect(custom_role.reload.permissions).to include(permission)
      end
    end

    context 'when updating system role' do
      let(:system_role) { Role.find_by(is_system: true) || create(:role, :system) }

      it 'returns forbidden error' do
        patch "/api/v1/roles/#{system_role.id}",
              params: { role: { description: 'Hacked' } },
              headers: headers,
              as: :json

        expect_error_response('System roles cannot be modified', 403)
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
    let(:custom_role) { create(:role, name: 'deletable_role', is_system: false) }

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
        user.add_role(custom_role.name)
      end

      it 'returns conflict error' do
        delete "/api/v1/roles/#{custom_role.id}", headers: headers, as: :json

        expect_error_response('Cannot delete role that is assigned to users', 409)
      end
    end

    context 'when deleting system role' do
      let(:system_role) { Role.find_by(is_system: true) || create(:role, :system) }

      it 'returns forbidden error' do
        delete "/api/v1/roles/#{system_role.id}", headers: headers, as: :json

        expect_error_response('System roles cannot be deleted', 403)
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
  end

  describe 'POST /api/v1/roles/:role_id/assign_to_user/:user_id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:target_user) { create(:user, account: account) }
    let(:role) { create(:role, is_system: false) }

    context 'with admin.role.assign permission' do
      it 'assigns role to user' do
        post "/api/v1/roles/#{role.id}/assign_to_user/#{target_user.id}",
             headers: headers,
             as: :json

        expect_success_response

        target_user.reload
        expect(target_user.has_role?(role.name)).to be true
      end

      it 'returns updated user data' do
        post "/api/v1/roles/#{role.id}/assign_to_user/#{target_user.id}",
             headers: headers,
             as: :json

        response_data = json_response
        expect(response_data['data']['roles']).to include(role.name)
      end
    end

    context 'when user does not exist' do
      it 'returns not found error' do
        post "/api/v1/roles/#{role.id}/assign_to_user/nonexistent-id",
             headers: headers,
             as: :json

        expect_error_response('User not found', 404)
      end
    end

    context 'when role does not exist' do
      it 'returns not found error' do
        post "/api/v1/roles/nonexistent-id/assign_to_user/#{target_user.id}",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/roles/:role_id/remove_from_user/:user_id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:target_user) { create(:user, account: account) }
    let(:role) { create(:role, is_system: false) }

    before do
      target_user.add_role(role.name)
    end

    context 'with admin.role.assign permission' do
      it 'removes role from user' do
        delete "/api/v1/roles/#{role.id}/remove_from_user/#{target_user.id}",
               headers: headers,
               as: :json

        expect_success_response

        target_user.reload
        expect(target_user.has_role?(role.name)).to be false
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        delete "/api/v1/roles/#{role.id}/remove_from_user/#{target_user.id}",
               headers: headers,
               as: :json

        expect_error_response('Permission denied', 403)
      end
    end
  end
end
