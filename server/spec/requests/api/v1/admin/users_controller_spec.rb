# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::UsersController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: ['admin.user.view', 'admin.user.create', 'admin.user.update', 'admin.user.delete', 'admin.user.impersonate']) }
  let(:view_only_user) { create(:user, account: account, permissions: ['admin.user.view']) }
  let(:non_admin_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:view_only_headers) { auth_headers_for(view_only_user) }
  let(:non_admin_headers) { auth_headers_for(non_admin_user) }

  describe 'GET /api/v1/admin/users' do
    context 'with admin user view permission' do
      before do
        create_list(:user, 3, account: account)
      end

      it 'returns list of all users across all accounts' do
        get '/api/v1/admin/users', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.length).to be >= 4 # At least admin_user + 3 created users
      end
    end

    context 'without admin user view permission' do
      it 'returns forbidden error' do
        get '/api/v1/admin/users', headers: non_admin_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/admin/users/:id' do
    let(:target_user) { create(:user, account: account) }

    context 'with admin user view permission' do
      it 'returns user details' do
        get "/api/v1/admin/users/#{target_user.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'id' => target_user.id,
          'email' => target_user.email
        )
        expect(data).to have_key('roles')
        expect(data).to have_key('permissions')
        expect(data).to have_key('account')
      end

      it 'returns not found error for non-existent user' do
        get '/api/v1/admin/users/nonexistent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/admin/users' do
    context 'with admin user create permission' do
      it 'creates a new user successfully' do
        allow(WorkerJobService).to receive(:enqueue_welcome_email)

        expect {
          post '/api/v1/admin/users',
               params: {
                 account_id: account.id,
                 user: {
                   email: 'newuser@example.com',
                   name: 'New User'
                 }
               }.to_json,
               headers: headers
        }.to change { User.count }.by(1)

        expect_success_response
        data = json_response_data
        expect(data['email']).to eq('newuser@example.com')
        expect(data['name']).to eq('New User')
      end

      it 'creates audit log for user creation' do
        allow(WorkerJobService).to receive(:enqueue_welcome_email)

        expect {
          post '/api/v1/admin/users',
               params: {
                 account_id: account.id,
                 user: {
                   email: 'newuser@example.com',
                   name: 'New User'
                 }
               }.to_json,
               headers: headers
        }.to change { AuditLog.count }.by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('create')
        expect(audit_log.resource_type).to eq('User')
      end

      it 'returns error when account_id is missing' do
        post '/api/v1/admin/users',
             params: {
               user: {
                 email: 'newuser@example.com',
                 name: 'New User'
               }
             }.to_json,
             headers: headers

        expect_error_response('Account ID required', 400)
      end

      it 'returns validation error for invalid email' do
        post '/api/v1/admin/users',
             params: {
               account_id: account.id,
               user: {
                 email: 'invalid-email',
                 name: 'New User'
               }
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without admin user create permission' do
      it 'returns forbidden error' do
        post '/api/v1/admin/users',
             params: {
               account_id: account.id,
               user: {
                 email: 'newuser@example.com',
                 name: 'New User'
               }
             }.to_json,
             headers: view_only_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/admin/users/:id' do
    let(:target_user) { create(:user, account: account, name: 'Original Name') }

    context 'with admin user update permission' do
      it 'updates user successfully' do
        patch "/api/v1/admin/users/#{target_user.id}",
              params: {
                user: {
                  name: 'Updated Name'
                }
              }.to_json,
              headers: headers

        expect_success_response
        data = json_response_data
        expect(data['name']).to eq('Updated Name')
      end

      it 'updates user roles' do
        role = create(:role, name: 'custom_role')

        patch "/api/v1/admin/users/#{target_user.id}",
              params: {
                user: {
                  roles: ['custom_role']
                }
              }.to_json,
              headers: headers

        expect_success_response
        expect(target_user.reload.roles.pluck(:name)).to include('custom_role')
      end

      it 'creates audit log for role changes' do
        role = create(:role, name: 'custom_role')

        expect {
          patch "/api/v1/admin/users/#{target_user.id}",
                params: {
                  user: {
                    roles: ['custom_role']
                  }
                }.to_json,
                headers: headers
        }.to change { AuditLog.where(action: 'role_change').count }.by(1)
      end

      it 'prevents removing own system admin role' do
        system_admin_role = create(:role, name: 'system.admin')
        admin_user.user_roles.create!(role: system_admin_role, granted_by: admin_user)

        patch "/api/v1/admin/users/#{admin_user.id}",
              params: {
                user: {
                  roles: []
                }
              }.to_json,
              headers: headers

        expect_error_response('You cannot remove your own system admin role', 403)
      end

      it 'returns error for invalid roles' do
        patch "/api/v1/admin/users/#{target_user.id}",
              params: {
                user: {
                  roles: ['nonexistent_role']
                }
              }.to_json,
              headers: headers

        expect_error_response(/Invalid roles/, 422)
      end
    end

    context 'without admin user update permission' do
      it 'returns forbidden error' do
        patch "/api/v1/admin/users/#{target_user.id}",
              params: {
                user: {
                  name: 'Updated Name'
                }
              }.to_json,
              headers: view_only_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/admin/users/:id' do
    let(:target_user) { create(:user, account: account) }

    context 'with admin user delete permission' do
      it 'deletes user successfully' do
        user_id = target_user.id

        expect {
          delete "/api/v1/admin/users/#{user_id}", headers: headers, as: :json
        }.to change { User.count }.by(-1)

        expect_success_response
      end

      it 'creates audit log for user deletion' do
        user_id = target_user.id

        expect {
          delete "/api/v1/admin/users/#{user_id}", headers: headers, as: :json
        }.to change { AuditLog.where(action: 'delete', resource_type: 'User').count }.by(1)
      end

      it 'prevents self-deletion' do
        delete "/api/v1/admin/users/#{admin_user.id}", headers: headers, as: :json

        expect_error_response('You cannot delete your own account', 403)
      end
    end

    context 'without admin user delete permission' do
      it 'returns forbidden error' do
        delete "/api/v1/admin/users/#{target_user.id}", headers: view_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/admin/users/:id/impersonate' do
    let(:target_user) { create(:user, account: account) }

    context 'with admin user impersonate permission' do
      it 'starts impersonation successfully' do
        service = double('ImpersonationService')
        allow(Auth::ImpersonationService).to receive(:new).and_return(service)
        allow(service).to receive(:start_impersonation).and_return('impersonation-token')

        post "/api/v1/admin/users/#{target_user.id}/impersonate",
             params: { reason: 'Support request' }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('token', 'target_user', 'expires_at')
      end

      it 'handles impersonation service errors' do
        service = double('ImpersonationService')
        error = Auth::ImpersonationService::Error.new('Impersonation not allowed')
        allow(error).to receive(:http_status).and_return(:forbidden)
        allow(error).to receive(:error_code).and_return('impersonation_forbidden')
        allow(Auth::ImpersonationService).to receive(:new).and_return(service)
        allow(service).to receive(:start_impersonation).and_raise(error)

        post "/api/v1/admin/users/#{target_user.id}/impersonate",
             params: { reason: 'Test' }.to_json,
             headers: headers

        expect_error_response('Impersonation not allowed', 403)
      end
    end

    context 'without admin user impersonate permission' do
      it 'returns forbidden error' do
        post "/api/v1/admin/users/#{target_user.id}/impersonate",
             params: { reason: 'Test' }.to_json,
             headers: view_only_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
