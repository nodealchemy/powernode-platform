# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Delegations', type: :request do
  let(:account) { create(:account) }
  let(:manager_user) do
    user = create(:user, :manager, account: account)
    # Grant account.manage permission
    permission = Permission.find_or_create_by!(resource: 'account', action: 'manage') do |p|
      p.description = 'Manage account settings and delegations'
      p.category = 'resource'
    end
    user.roles.first.permissions << permission unless user.roles.first.permissions.include?(permission)
    user.reload
    user
  end
  # Create external user (different account) for delegation tests
  let(:external_account) { create(:account) }
  let(:delegated_user) { create(:user, account: external_account) }
  let(:headers) { auth_headers_for(manager_user) }
  let(:admin_role) do
    role = create(:role, name: 'account.admin', display_name: 'Account Admin', role_type: 'user')
    permission = Permission.find_or_create_by!(resource: 'users', action: 'create') do |p|
      p.description = 'Create users'
      p.category = 'resource'
    end
    role.permissions << permission unless role.permissions.include?(permission)
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
      regular_user = create(:user, account: account)
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
      expect(json['data']['delegation']['permissions'].size).to eq(0) # No specific delegation_permissions
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
      regular_user = create(:user, account: account)
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
    let(:permission) do
      perm = Permission.find_or_create_by!(resource: 'reports', action: 'generate') do |p|
        p.description = 'Generate reports'
        p.category = 'resource'
      end
      perm
    end

    it 'adds permission to delegation without role' do
      post "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/permissions",
           params: { permission_id: permission.id },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Permission added successfully')
    end

    it 'returns error when delegation not found' do
      post "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000/permissions",
           params: { permission_id: permission.id },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/delegations/:id/permissions/:permission_id' do
    let(:permission) do
      Permission.find_or_create_by!(resource: 'test', action: 'delete') do |p|
        p.description = 'Delete test'
        p.category = 'resource'
      end
    end
    let(:delegation) do
      user = create(:user, account: account)
      d = create(:account_delegation, :active, account: account, delegated_by: manager_user, delegated_user: user, role: admin_role)
      admin_role.permissions << permission unless admin_role.permissions.include?(permission)
      d.delegation_permissions.create!(permission: permission)
      d
    end

    it 'removes permission from delegation' do
      delete "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}/permissions/#{permission.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['message']).to eq('Permission removed successfully')
    end

    it 'returns error when delegation not found' do
      delete "/api/v1/accounts/#{account.id}/delegations/00000000-0000-0000-0000-000000000000/permissions/#{permission.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
