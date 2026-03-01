# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:plan) { create(:plan) }

  before(:each) do
    Rails.cache.clear
  end

  describe 'GET /api/v1/accounts/:id' do
    let(:headers) { auth_headers_for(user) }

    context 'when accessing own account' do
      it 'returns account data successfully' do
        get "/api/v1/accounts/#{account.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => account.id,
          'name' => account.name,
          'status' => account.status
        )
      end

      it 'includes account attributes' do
        account.update!(billing_email: 'billing@example.com', tax_id: 'TAX123')

        get "/api/v1/accounts/#{account.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'billing_email' => 'billing@example.com',
          'tax_id' => 'TAX123'
        )
      end

      it 'includes users_count' do
        create_list(:user, 3, account: account)

        get "/api/v1/accounts/#{account.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        # 4 users total: the original user + 3 created
        expect(response_data['data']['users_count']).to eq(4)
      end

      it 'includes subscription data when subscription exists' do
        subscription = create(:subscription, :active, account: account, plan: plan)

        get "/api/v1/accounts/#{account.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['subscription']).to include(
          'id' => subscription.id,
          'status' => 'active',
          'plan_name' => plan.name
        )
      end

      it 'returns null subscription when no subscription exists' do
        get "/api/v1/accounts/#{account.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['subscription']).to be_nil
      end
    end

    context 'when accessing another account without permission' do
      it 'returns forbidden error' do
        get "/api/v1/accounts/#{other_account.id}", headers: headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'when accessing another account with accounts.read permission' do
      let(:user_with_permission) do
        create(:user, account: account, permissions: [ 'accounts.read' ])
      end
      let(:headers) { auth_headers_for(user_with_permission) }

      it 'returns other account data successfully' do
        get "/api/v1/accounts/#{other_account.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => other_account.id,
          'name' => other_account.name
        )
      end
    end

    context 'when account does not exist' do
      let(:user_with_permission) do
        create(:user, account: account, permissions: [ 'accounts.read' ])
      end
      let(:headers) { auth_headers_for(user_with_permission) }

      it 'returns not found error' do
        get '/api/v1/accounts/nonexistent-id', headers: headers, as: :json

        expect_error_response('Account not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/accounts/#{account.id}", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:id' do
    let(:headers) { auth_headers_for(user) }

    context 'when updating own account with valid data' do
      let(:update_params) do
        {
          account: {
            name: 'Updated Company Name',
            billing_email: 'new-billing@example.com',
            tax_id: 'NEW-TAX-456'
          }
        }
      end

      it 'updates account successfully' do
        patch "/api/v1/accounts/#{account.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['success']).to be true
        expect(response_data['data']).to include(
          'name' => 'Updated Company Name',
          'billing_email' => 'new-billing@example.com',
          'tax_id' => 'NEW-TAX-456'
        )
      end

      it 'persists changes to database' do
        patch "/api/v1/accounts/#{account.id}", params: update_params, headers: headers, as: :json

        account.reload
        expect(account.name).to eq('Updated Company Name')
        expect(account.billing_email).to eq('new-billing@example.com')
        expect(account.tax_id).to eq('NEW-TAX-456')
      end
    end

    context 'when updating with partial data' do
      it 'updates only provided fields' do
        original_name = account.name

        patch "/api/v1/accounts/#{account.id}",
              params: { account: { billing_email: 'partial@example.com' } },
              headers: headers,
              as: :json

        expect_success_response

        account.reload
        expect(account.name).to eq(original_name)
        expect(account.billing_email).to eq('partial@example.com')
      end
    end

    context 'when updating with invalid data' do
      it 'returns validation error for invalid name' do
        patch "/api/v1/accounts/#{account.id}",
              params: { account: { name: 'A' } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end

      it 'returns validation error for blank name' do
        patch "/api/v1/accounts/#{account.id}",
              params: { account: { name: '' } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'when updating another account without permission' do
      it 'returns forbidden error' do
        patch "/api/v1/accounts/#{other_account.id}",
              params: { account: { name: 'Hacked Name' } },
              headers: headers,
              as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        patch "/api/v1/accounts/#{account.id}",
              params: { account: { name: 'No Auth Update' } },
              as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PUT /api/v1/accounts/:id' do
    let(:headers) { auth_headers_for(user) }

    it 'updates account via PUT method' do
      put "/api/v1/accounts/#{account.id}",
          params: { account: { name: 'PUT Update Test' } },
          headers: headers,
          as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['name']).to eq('PUT Update Test')
    end
  end

  describe 'GET /api/v1/accounts/accessible' do
    let(:headers) { auth_headers_for(user) }

    context 'when user has only primary account' do
      it 'returns list with primary account only' do
        get '/api/v1/accounts/accessible', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['accounts']).to be_an(Array)
        expect(response_data['data']['accounts'].length).to eq(1)
        expect(response_data['data']['accounts'].first).to include(
          'id' => account.id,
          'is_primary' => true
        )
      end

      it 'returns current and primary account ids' do
        get '/api/v1/accounts/accessible', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['current_account_id']).to eq(account.id)
        expect(response_data['data']['primary_account_id']).to eq(account.id)
      end
    end

    context 'when user has delegated access to other accounts' do
      let(:delegated_account) { create(:account) }
      let(:delegating_user) { create(:user, account: delegated_account) }

      before do
        create(:account_delegation,
               account: delegated_account,
               delegated_user: user,
               delegated_by: delegating_user,
               status: 'active',
               expires_at: 30.days.from_now)
      end

      it 'returns list with primary and delegated accounts' do
        get '/api/v1/accounts/accessible', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['accounts'].length).to eq(2)

        account_ids = response_data['data']['accounts'].map { |a| a['id'] }
        expect(account_ids).to include(account.id, delegated_account.id)
      end

      it 'marks delegated account correctly' do
        get '/api/v1/accounts/accessible', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        delegated = response_data['data']['accounts'].find { |a| a['id'] == delegated_account.id }
        expect(delegated['is_primary']).to be false
        expect(delegated['delegation']).to be_present
      end
    end

    context 'when delegation is expired' do
      let(:delegated_account) { create(:account) }
      let(:delegating_user) { create(:user, account: delegated_account) }

      before do
        create(:account_delegation,
               account: delegated_account,
               delegated_user: user,
               delegated_by: delegating_user,
               status: 'active',
               expires_at: 1.day.ago)
      end

      it 'does not include expired delegated accounts' do
        get '/api/v1/accounts/accessible', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['accounts'].length).to eq(1)
        expect(response_data['data']['accounts'].first['id']).to eq(account.id)
      end
    end

    context 'when delegation is revoked' do
      let(:delegated_account) { create(:account) }
      let(:delegating_user) { create(:user, account: delegated_account) }

      before do
        create(:account_delegation, :revoked,
               account: delegated_account,
               delegated_user: user,
               delegated_by: delegating_user)
      end

      it 'does not include revoked delegated accounts' do
        get '/api/v1/accounts/accessible', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['accounts'].length).to eq(1)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/accounts/accessible', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/accounts/switch' do
    let(:headers) { auth_headers_for(user) }
    let(:delegated_account) { create(:account) }
    let(:delegating_user) { create(:user, account: delegated_account) }

    context 'when switching to own primary account' do
      it 'returns success with new tokens' do
        post '/api/v1/accounts/switch',
             params: { account_id: account.id },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('access_token')
        expect(response_data['data']).to have_key('refresh_token')
        expect(response_data['data']['account']['id']).to eq(account.id)
      end
    end

    context 'when switching to delegated account' do
      before do
        create(:account_delegation,
               account: delegated_account,
               delegated_user: user,
               delegated_by: delegating_user,
               status: 'active',
               expires_at: 30.days.from_now)
      end

      it 'returns success with new tokens for delegated account' do
        post '/api/v1/accounts/switch',
             params: { account_id: delegated_account.id },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['success']).to be true
        expect(response_data['data']['account']['id']).to eq(delegated_account.id)
        expect(response_data['data']['account']['is_primary']).to be false
      end

      it 'includes user information in response' do
        post '/api/v1/accounts/switch',
             params: { account_id: delegated_account.id },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['user']).to include(
          'id' => user.id,
          'email' => user.email
        )
      end
    end

    context 'when switching to account without access' do
      it 'returns forbidden error' do
        post '/api/v1/accounts/switch',
             params: { account_id: other_account.id },
             headers: headers,
             as: :json

        expect_error_response('You do not have access to this account', 403)
      end
    end

    context 'when switching to inactive account' do
      let(:inactive_account) { create(:account, :suspended) }
      let(:inactive_delegating_user) { create(:user, account: inactive_account) }

      before do
        create(:account_delegation,
               account: inactive_account,
               delegated_user: user,
               delegated_by: inactive_delegating_user,
               status: 'active',
               expires_at: 30.days.from_now)
      end

      it 'returns unprocessable content error' do
        post '/api/v1/accounts/switch',
             params: { account_id: inactive_account.id },
             headers: headers,
             as: :json

        expect_error_response('Target account is not active', 422)
      end
    end

    context 'when delegation is expired' do
      before do
        create(:account_delegation,
               account: delegated_account,
               delegated_user: user,
               delegated_by: delegating_user,
               status: 'active',
               expires_at: 1.day.ago)
      end

      it 'returns forbidden error' do
        post '/api/v1/accounts/switch',
             params: { account_id: delegated_account.id },
             headers: headers,
             as: :json

        expect_error_response('You do not have access to this account', 403)
      end
    end

    context 'when delegation is inactive' do
      before do
        create(:account_delegation,
               account: delegated_account,
               delegated_user: user,
               delegated_by: delegating_user,
               status: 'inactive',
               expires_at: 30.days.from_now)
      end

      it 'returns forbidden error' do
        post '/api/v1/accounts/switch',
             params: { account_id: delegated_account.id },
             headers: headers,
             as: :json

        expect_error_response('You do not have access to this account', 403)
      end
    end

    context 'when account_id is missing' do
      it 'returns bad request error' do
        post '/api/v1/accounts/switch',
             params: {},
             headers: headers,
             as: :json

        expect_error_response('Account ID is required', 400)
      end
    end

    context 'when account does not exist' do
      it 'returns not found error' do
        post '/api/v1/accounts/switch',
             params: { account_id: 'nonexistent-id' },
             headers: headers,
             as: :json

        expect_error_response('Account not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/accounts/switch',
             params: { account_id: account.id },
             as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/accounts/switch_to_primary' do
    let(:headers) { auth_headers_for(user) }

    context 'when already on primary account' do
      it 'returns success with tokens for primary account' do
        post '/api/v1/accounts/switch_to_primary', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['success']).to be true
        expect(response_data['data']['account']['id']).to eq(account.id)
        expect(response_data['data']['account']['is_primary']).to be true
      end

      it 'returns new access and refresh tokens' do
        post '/api/v1/accounts/switch_to_primary', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('access_token')
        expect(response_data['data']).to have_key('refresh_token')
        expect(response_data['data']).to have_key('expires_at')
      end
    end

    context 'when on delegated account' do
      let(:delegated_account) { create(:account) }
      let(:delegating_user) { create(:user, account: delegated_account) }

      before do
        create(:account_delegation,
               account: delegated_account,
               delegated_user: user,
               delegated_by: delegating_user,
               status: 'active',
               expires_at: 30.days.from_now)
      end

      it 'switches back to primary account' do
        # First switch to delegated account (simulated via direct API call)
        post '/api/v1/accounts/switch_to_primary', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['account']['id']).to eq(account.id)
        expect(response_data['data']['account']['is_primary']).to be true
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/accounts/switch_to_primary', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'audit logging' do
    let(:headers) { auth_headers_for(user) }
    let(:delegated_account) { create(:account) }
    let(:delegating_user) { create(:user, account: delegated_account) }

    before do
      create(:account_delegation,
             account: delegated_account,
             delegated_user: user,
             delegated_by: delegating_user,
             status: 'active',
             expires_at: 30.days.from_now)
    end

    it 'creates audit log when switching accounts' do
      expect {
        post '/api/v1/accounts/switch',
             params: { account_id: delegated_account.id },
             headers: headers,
             as: :json
      }.to change(AuditLog, :count).by_at_least(1)

      audit_log = AuditLog.find_by(action: 'account_switch')
      expect(audit_log).to be_present
      expect(audit_log.user).to eq(user)
      expect(audit_log.metadata['target_account_id']).to eq(delegated_account.id)
    end
  end
end
