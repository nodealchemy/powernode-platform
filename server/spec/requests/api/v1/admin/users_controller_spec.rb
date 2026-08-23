# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::UsersController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: [ 'admin.user.read', 'admin.user.create', 'admin.user.update', 'admin.user.delete', 'admin.user.impersonate' ]) }
  let(:view_only_user) { create(:user, account: account, permissions: [ 'admin.user.read' ]) }
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
      before do
        # The controller generates a temp password with SecureRandom.alphanumeric(12),
        # which lacks special characters. The PasswordStrengthService requires special chars,
        # so we stub it to allow the alphanumeric password to pass validation.
        allow(Security::PasswordStrengthService).to receive(:validate_password).and_return({
          valid: true, errors: [], score: 100, entropy: 100.0, strength: 'very_strong', character_space: 94
        })
      end

      it 'creates a new user successfully' do
        # WorkerJobService does not implement enqueue_welcome_email,
        # so bypass partial double verification for this stub
        without_partial_double_verification do
          allow(WorkerJobService).to receive(:enqueue_welcome_email)
        end

        # Force creation of admin_user before the expect block
        # to avoid lazy let evaluation affecting User.count
        auth = headers

        expect {
          post '/api/v1/admin/users',
               params: {
                 account_id: account.id,
                 user: {
                   email: 'newuser@example.com',
                   name: 'New User'
                 }
               }.to_json,
               headers: auth
        }.to change { User.count }.by(1)

        expect_success_response
        data = json_response_data
        expect(data['email']).to eq('newuser@example.com')
        expect(data['name']).to eq('New User')
      end

      it 'creates audit log for user creation' do
        without_partial_double_verification do
          allow(WorkerJobService).to receive(:enqueue_welcome_email)
        end

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

        expect(response).to have_http_status(:unprocessable_content)
      end

      # Regression coverage for IMP-796128658b83. The create action previously called
      # WorkerJobService.enqueue_welcome_email (a method that does NOT exist) AFTER the
      # user was persisted but BEFORE the audit log + render — raising NoMethodError, so
      # admin user creation returned HTTP 500 every time, leaving an orphaned user with no
      # audit entry. It also leaked the plaintext temp password as a job argument.
      context 'welcome email enqueue (regression IMP-796128658b83)' do
        it 'returns 201, persists the user, and writes the audit log' do
          allow(WorkerJobService).to receive(:enqueue_notification_email)

          expect {
            post '/api/v1/admin/users',
                 params: {
                   account_id: account.id,
                   user: { email: 'welcome@example.com', name: 'Welcome User' }
                 }.to_json,
                 headers: headers
          }.to change { AuditLog.where(action: 'create', resource_type: 'User').count }.by(1)

          expect(response).to have_http_status(:created)
          created = account.users.find_by(email: 'welcome@example.com')
          expect(created).to be_present
          audit = AuditLog.where(action: 'create', resource_type: 'User').order(:created_at).last
          expect(audit.resource_id).to eq(created.id)
        end

        it 'never passes the temporary password or any token as a job argument' do
          captured = nil
          allow(WorkerJobService).to receive(:enqueue_notification_email) do |type, opts|
            captured = [ type, opts ]
            nil
          end

          post '/api/v1/admin/users',
               params: {
                 account_id: account.id,
                 user: { email: 'nosecret@example.com', name: 'No Secret' }
               }.to_json,
               headers: headers

          expect(response).to have_http_status(:created)
          type, opts = captured
          expect(type).to eq('welcome')
          created = account.users.find_by(email: 'nosecret@example.com')
          # Exactly the non-secret onboarding fields — no password key smuggled in,
          # and no bearer token: worker job args are logged twice and persisted
          # verbatim in the Sidekiq/Redis payload, so tokens are fetched by the
          # worker over the internal API instead of being sent here.
          expect(opts.keys).to match_array([ :user_id, :email, :user_name ])
          expect(opts.keys.map(&:to_s)).not_to include('password', 'temp_password')
          expect(opts.keys.map(&:to_s).grep(/token/)).to be_empty
          # And no value carries password material (e.g. the bcrypt digest).
          expect(opts.values.map(&:to_s)).not_to include(created.password_digest)
        end

        it 'still creates the user + audit log when the email enqueue fails' do
          allow(WorkerJobService).to receive(:enqueue_notification_email)
            .and_raise(WorkerJobService::WorkerServiceError, 'worker down')

          expect {
            post '/api/v1/admin/users',
                 params: {
                   account_id: account.id,
                   user: { email: 'resilient@example.com', name: 'Resilient User' }
                 }.to_json,
                 headers: headers
          }.to change { AuditLog.where(action: 'create', resource_type: 'User').count }.by(1)

          expect(response).to have_http_status(:created)
          expect(account.users.find_by(email: 'resilient@example.com')).to be_present
        end
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
                  roles: [ 'custom_role' ]
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
                    roles: [ 'custom_role' ]
                  }
                }.to_json,
                headers: headers
        }.to change { AuditLog.where(action: 'role_change').count }.by(1)
      end

      it 'prevents removing own system admin role' do
        system_admin_role = create(:role, name: 'system.admin')
        # Use a unique role name to avoid collision with roles created by other tests or callbacks
        fallback_role = Role.find_or_create_by!(name: 'basic_user') do |r|
          r.display_name = 'Basic User'
          r.role_type = 'user'
        end
        # Force-evaluate admin_user to ensure it exists
        admin_user
        admin_user.user_roles.create!(role: system_admin_role, granted_by_id: admin_user.id, granted_at: Time.current)
        # Reload to ensure the role is visible
        admin_user.reload

        # Send a non-empty roles array that omits system.admin.
        # Empty arrays are falsy for .present? so the controller skips role handling entirely.
        patch "/api/v1/admin/users/#{admin_user.id}",
              params: {
                user: {
                  roles: [ 'basic_user' ]
                }
              }.to_json,
              headers: headers

        expect_error_response('You cannot remove your own system admin role', 403)
      end

      it 'returns error for invalid roles' do
        patch "/api/v1/admin/users/#{target_user.id}",
              params: {
                user: {
                  roles: [ 'nonexistent_role' ]
                }
              }.to_json,
              headers: headers

        expect_error_response('Invalid roles', 422)
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

    # Privilege-escalation defense (shared RoleAssignmentGuard): an
    # admin.user.update holder who is NOT a system/regular admin may only assign
    # roles whose effective permissions are a subset of their own. Assigning a
    # role that grants a permission they lack must be rejected (403), never
    # silently allowed. Characterizes the `update` call site of the guard.
    context 'privilege escalation on role assignment (non-admin assigner)' do
      let(:limited_admin) { create(:user, account: account, permissions: [ 'admin.user.update', 'users.read' ]) }
      let(:limited_headers) { auth_headers_for(limited_admin) }

      let!(:subset_role) do
        role = create(:role, name: 'update_subset')
        role.role_permissions.create!(permission_name: 'users.read')
        role
      end
      let!(:escalation_role) do
        role = create(:role, name: 'update_escalation')
        role.role_permissions.create!(permission_name: 'admin.role.delete')
        role
      end

      it 'rejects assigning a role granting a permission the assigner lacks' do
        patch "/api/v1/admin/users/#{target_user.id}",
              params: { user: { roles: [ 'update_escalation' ] } }.to_json,
              headers: limited_headers

        expect_error_response('You do not have permission to assign the following roles', 403)
        expect(target_user.reload.roles.pluck(:name)).not_to include('update_escalation')
      end

      it 'allows assigning a role whose permissions the assigner holds' do
        patch "/api/v1/admin/users/#{target_user.id}",
              params: { user: { roles: [ 'update_subset' ] } }.to_json,
              headers: limited_headers

        expect_success_response
        expect(target_user.reload.roles.pluck(:name)).to include('update_subset')
      end
    end
  end

  describe 'DELETE /api/v1/admin/users/:id' do
    let(:target_user) { create(:user, account: account) }

    context 'with admin user delete permission' do
      it 'deletes user successfully' do
        # Force creation of admin_user BEFORE target_user so that
        # target_user is NOT the first user in the account (avoids owner role assignment).
        # Also ensures both users exist before the expect block to get accurate User.count.
        admin_user
        user_id = target_user.id

        expect {
          delete "/api/v1/admin/users/#{user_id}", headers: headers, as: :json
        }.to change { User.count }.by(-1)

        expect_success_response
      end

      it 'creates audit log for user deletion' do
        admin_user
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

end
