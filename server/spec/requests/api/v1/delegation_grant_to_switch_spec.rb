# frozen_string_literal: true

require 'rails_helper'

# fc-20 review: the delegations management UI and the account switcher are
# separate frontend features (features/delegations and
# features/account/switcher) built on the SAME server model, Account::Delegation.
# delegations_spec.rb pins the grant endpoint's own response; accounts_spec.rb
# pins GET /accounts/accessible and POST /accounts/switch against delegation
# rows built directly through the factory. Neither connects the two: this
# spec proves the actual end-to-end flow a user experiences — grant through
# the real API the delegations UI calls, then see and use it through the real
# API the account switcher calls — so a regression in either side's mapping of
# the shared model cannot hide behind the other's isolated coverage.
RSpec.describe 'Delegation grant -> account switcher visibility -> switch', type: :request do
  let(:account) { create(:account) }
  let(:manager_user) do
    user = create(:user, :manager, account: account)
    user.roles.first.role_permissions.find_or_create_by!(permission_name: 'accounts.manage')
    user.reload
    user
  end
  let(:external_account) { create(:account) }
  let(:delegated_user) { create(:user, account: external_account) }
  let(:manager_headers) { auth_headers_for(manager_user) }
  let(:delegated_user_headers) { auth_headers_for(delegated_user) }

  it 'lists the granted account in the delegated user\'s switcher, and lets them switch into it' do
    post "/api/v1/accounts/#{account.id}/delegations",
         params: { delegation: { delegated_user_email: delegated_user.email, permission_names: [ 'users.read' ] } },
         headers: manager_headers, as: :json

    expect(response).to have_http_status(:created)
    delegation_id = JSON.parse(response.body).dig('data', 'delegation', 'id')
    expect(delegation_id).to be_present

    get '/api/v1/accounts/accessible', headers: delegated_user_headers, as: :json

    expect(response).to have_http_status(:ok)
    accessible = JSON.parse(response.body).dig('data', 'accounts')
    granted = accessible.find { |a| a['id'] == account.id }
    expect(granted).to be_present
    expect(granted['is_primary']).to be false
    expect(granted.dig('delegation', 'id')).to eq(delegation_id)

    post '/api/v1/accounts/switch', params: { account_id: account.id }, headers: delegated_user_headers, as: :json

    expect(response).to have_http_status(:ok)
    switched = JSON.parse(response.body)
    expect(switched['success']).to be true
    expect(switched.dig('data', 'account', 'id')).to eq(account.id)
  end

  it 'no longer lists the account, and refuses the switch, once the delegation is revoked' do
    post "/api/v1/accounts/#{account.id}/delegations",
         params: { delegation: { delegated_user_email: delegated_user.email, permission_names: [ 'users.read' ] } },
         headers: manager_headers, as: :json
    delegation_id = JSON.parse(response.body).dig('data', 'delegation', 'id')

    patch "/api/v1/accounts/#{account.id}/delegations/#{delegation_id}/revoke", headers: manager_headers, as: :json
    expect(response).to have_http_status(:ok)

    get '/api/v1/accounts/accessible', headers: delegated_user_headers, as: :json
    accessible = JSON.parse(response.body).dig('data', 'accounts')
    expect(accessible.find { |a| a['id'] == account.id }).to be_nil

    post '/api/v1/accounts/switch', params: { account_id: account.id }, headers: delegated_user_headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  # fc-20 review item 5: a delegated user cannot switch into an account they
  # were never granted at all -- not merely one whose grant was revoked. No
  # Account::Delegation row exists for (delegated_user, another_account) here.
  it 'refuses the switch into an account the user was never delegated at all' do
    another_account = create(:account)

    post '/api/v1/accounts/switch', params: { account_id: another_account.id }, headers: delegated_user_headers, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
