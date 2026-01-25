# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:regular_user) { create(:user, account: account) }
  let(:plan) { create(:plan) }

  before do
    # Create a subscription for the account to enable user creation
    create(:subscription, :active, account: account, plan: plan)
  end

  describe 'GET /api/v1/users' do
    let(:headers) { auth_headers_for(admin_user) }

    context 'with admin.user.view permission' do
      before do
        create_list(:user, 3, account: account)
      end

      it 'returns paginated list of users' do
        get '/api/v1/users', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to be_an(Array)
        expect(response_data['meta']['pagination']).to include(
          'current_page' => 1,
          'total_count' => 5 # admin_user + regular_user + 3 created
        )
      end

      it 'respects per_page parameter' do
        get '/api/v1/users', params: { per_page: 2 }, headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data'].length).to eq(2)
        expect(response_data['meta']['pagination']['per_page']).to eq(2)
      end

      it 'respects page parameter' do
        get '/api/v1/users', params: { page: 2, per_page: 2 }, headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['meta']['pagination']['current_page']).to eq(2)
      end

      it 'enforces maximum per_page limit' do
        get '/api/v1/users', params: { per_page: 500 }, headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['meta']['pagination']['per_page']).to be <= 100
      end

      it 'returns users with role information' do
        get '/api/v1/users', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        first_user = response_data['data'].first
        expect(first_user).to include('id', 'email', 'name', 'status')
      end
    end

    context 'without admin.user.view permission' do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it 'returns forbidden error' do
        get '/api/v1/users', headers: headers, as: :json

        expect_error_response('Permission denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/users', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/users/:id' do
    let(:target_user) { create(:user, account: account) }

    context 'when accessing own profile' do
      let(:headers) { auth_headers_for(target_user) }

      it 'returns user data successfully' do
        get "/api/v1/users/#{target_user.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => target_user.id,
          'email' => target_user.email,
          'name' => target_user.name
        )
      end
    end

    context 'when accessing another user with users.read permission' do
      let(:user_with_permission) { create(:user, account: account, permissions: ['users.read']) }
      let(:headers) { auth_headers_for(user_with_permission) }

      it 'returns the other user data' do
        get "/api/v1/users/#{target_user.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['id']).to eq(target_user.id)
      end
    end

    context 'when accessing another user without permission' do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it 'returns forbidden error' do
        get "/api/v1/users/#{target_user.id}", headers: headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'when user is from different account' do
      let(:other_user) { create(:user, account: other_account) }
      let(:headers) { auth_headers_for(admin_user) }

      it 'returns not found error' do
        get "/api/v1/users/#{other_user.id}", headers: headers, as: :json

        expect_error_response('User not found', 404)
      end
    end

    context 'when user does not exist' do
      let(:headers) { auth_headers_for(admin_user) }

      it 'returns not found error' do
        get '/api/v1/users/nonexistent-id', headers: headers, as: :json

        expect_error_response('User not found', 404)
      end
    end
  end

  describe 'POST /api/v1/users' do
    let(:headers) { auth_headers_for(admin_user) }

    context 'with admin.user.create permission' do
      let(:valid_params) do
        {
          user: {
            email: 'newuser@example.com',
            name: 'New User',
            password: 'SecurePassword123!',
            password_confirmation: 'SecurePassword123!'
          }
        }
      end

      it 'creates a new user successfully' do
        expect {
          post '/api/v1/users', params: valid_params, headers: headers, as: :json
        }.to change(User, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['success']).to be true
        expect(response_data['data']['email']).to eq('newuser@example.com')
      end

      it 'assigns user to same account' do
        post '/api/v1/users', params: valid_params, headers: headers, as: :json

        new_user = User.find_by(email: 'newuser@example.com')
        expect(new_user.account).to eq(account)
      end
    end

    context 'with invalid data' do
      it 'returns validation error for missing email' do
        post '/api/v1/users',
             params: { user: { name: 'Test', password: 'pass' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end

      it 'returns validation error for duplicate email' do
        post '/api/v1/users',
             params: { user: { email: admin_user.email, name: 'Dup', password: 'pass123' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without admin.user.create permission' do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it 'returns forbidden error' do
        post '/api/v1/users',
             params: { user: { email: 'test@example.com' } },
             headers: headers,
             as: :json

        expect_error_response('Permission denied', 403)
      end
    end
  end

  describe 'PATCH /api/v1/users/:id' do
    let(:target_user) { create(:user, account: account) }

    context 'when updating own profile' do
      let(:headers) { auth_headers_for(target_user) }

      it 'updates name successfully' do
        patch "/api/v1/users/#{target_user.id}",
              params: { user: { name: 'Updated Name' } },
              headers: headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['name']).to eq('Updated Name')

        target_user.reload
        expect(target_user.name).to eq('Updated Name')
      end
    end

    context 'when updating password with current password' do
      let(:headers) { auth_headers_for(target_user) }
      let(:current_password) { TestUsers::PASSWORD }

      it 'updates password successfully' do
        patch "/api/v1/users/#{target_user.id}",
              params: {
                user: {
                  current_password: current_password,
                  password: 'NewPassword123!',
                  password_confirmation: 'NewPassword123!'
                }
              },
              headers: headers,
              as: :json

        expect_success_response

        target_user.reload
        expect(target_user.authenticate('NewPassword123!')).to be_truthy
      end
    end

    context 'when updating another user with users.update permission' do
      let(:user_with_permission) { create(:user, account: account, permissions: ['users.update']) }
      let(:headers) { auth_headers_for(user_with_permission) }

      it 'updates the other user successfully' do
        patch "/api/v1/users/#{target_user.id}",
              params: { user: { name: 'Admin Updated' } },
              headers: headers,
              as: :json

        expect_success_response

        target_user.reload
        expect(target_user.name).to eq('Admin Updated')
      end
    end
  end

  describe 'DELETE /api/v1/users/:id' do
    let(:target_user) { create(:user, account: account) }
    let(:headers) { auth_headers_for(admin_user) }

    context 'with admin.user.delete permission' do
      it 'deletes the user successfully' do
        delete "/api/v1/users/#{target_user.id}", headers: headers, as: :json

        expect_success_response
        expect(User.find_by(id: target_user.id)).to be_nil
      end
    end

    context 'when trying to delete own account' do
      let(:headers) { auth_headers_for(admin_user) }

      it 'returns error' do
        delete "/api/v1/users/#{admin_user.id}", headers: headers, as: :json

        expect_error_response('Cannot delete your own user account', 422)
      end
    end

    context 'when user is from different account' do
      let(:other_user) { create(:user, account: other_account) }

      it 'returns not found error' do
        delete "/api/v1/users/#{other_user.id}", headers: headers, as: :json

        expect_error_response('User not found', 404)
      end
    end
  end

  describe 'GET /api/v1/users/stats' do
    let(:headers) { auth_headers_for(admin_user) }

    before do
      create_list(:user, 2, account: account)
      create(:user, :suspended, account: account)
      create(:user, :unverified, account: account)
    end

    context 'with admin.user.view permission' do
      it 'returns user statistics' do
        get '/api/v1/users/stats', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'total_users',
          'active_users',
          'suspended_users',
          'unverified_users',
          'recent_logins'
        )
      end

      it 'returns correct counts' do
        get '/api/v1/users/stats', headers: headers, as: :json

        response_data = json_response

        # admin_user + regular_user + 2 created + 1 suspended + 1 unverified = 6
        expect(response_data['data']['total_users']).to eq(6)
        expect(response_data['data']['suspended_users']).to eq(1)
        expect(response_data['data']['unverified_users']).to eq(1)
      end
    end

    context 'without permission' do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it 'returns forbidden error' do
        get '/api/v1/users/stats', headers: headers, as: :json

        expect_error_response('Permission denied', 403)
      end
    end
  end
end
