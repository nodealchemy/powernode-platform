# frozen_string_literal: true

require 'rails_helper'

# THE DISPLAY MUST AGREE WITH THE RESOLVER (IMP-985b86a62bd0).
#
# Account::Delegation#configured_permissions_for bounds a delegation's explicit
# custom set by its role LIVE, so a stored name whose role grant was removed
# underneath the row no longer resolves. The serializer reported the stored
# delegation_permissions rows verbatim, so the API listed a permission the
# delegation does not confer — an operator deciding whether a delegation is
# over-scoped read authority that in fact 403s.
#
# The oracle is the delegation's RESOLVED set, never its delegation_permissions
# rows: an assertion against the stored rows passes against the broken
# behaviour.
RSpec.describe 'Api::V1::Delegations serializer resolved permissions', type: :request do
  let(:account) { create(:account) }
  let(:manager_user) do
    user = create(:user, :manager, account: account)
    user.roles.first.role_permissions.find_or_create_by!(permission_name: 'accounts.manage')
    user.reload
    user
  end
  let(:headers) { auth_headers_for(manager_user) }
  let(:delegated_user) { create(:user, account: create(:account)) }

  let(:live_permission) { 'users.read' }
  let(:stale_permission) { 'report.export' }

  let(:delegation_role) do
    role = create(:role, name: 'account.analyst', display_name: 'Account Analyst', role_type: 'user')
    role.role_permissions.find_or_create_by!(permission_name: live_permission)
    role.role_permissions.find_or_create_by!(permission_name: stale_permission)
    role
  end

  # A delegation whose custom set was legal when written, then had one of its
  # names removed from the role underneath it (what a catalog-remap migration
  # does — delegation_permissions is a second, independent store of NAMES that
  # such a migration does not reach).
  let!(:delegation) do
    d = create(:account_delegation, :active,
               account: account,
               delegated_by: manager_user,
               delegated_user: delegated_user,
               role: delegation_role)
    d.delegation_permissions.create!(permission_name: live_permission)
    d.delegation_permissions.create!(permission_name: stale_permission)
    delegation_role.role_permissions.where(permission_name: stale_permission).delete_all
    delegation_role.reload
    d.reload
  end

  def serialized(json_delegation)
    json_delegation['permissions'].map { |p| p['name'] }
  end

  describe 'GET /api/v1/accounts/:account_id/delegations/:id' do
    it 'lists the permissions the delegation actually confers, not the stored names' do
      get "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(delegation.reload.configured_permissions).to eq([ live_permission ])
      expect(serialized(json['data']['delegation']))
        .to match_array(delegation.configured_permissions)
      expect(serialized(json['data']['delegation'])).not_to include(stale_permission)
    end

    it 'surfaces the stored names that no longer resolve in a separate labelled field' do
      get "/api/v1/accounts/#{account.id}/delegations/#{delegation.id}", headers: headers

      json = JSON.parse(response.body)
      expect(json['data']['delegation']['stale_permission_names']).to eq([ stale_permission ])
    end
  end

  describe 'GET /api/v1/accounts/:account_id/delegations' do
    it 'agrees with the resolver in the index payload too' do
      get "/api/v1/accounts/#{account.id}/delegations", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      row = json['data']['delegations'].find { |d| d['id'] == delegation.id }

      # Anchored to the LITERAL live name as well as to the resolver: comparing
      # only against #configured_permissions would move both sides together if
      # the resolver itself regressed.
      expect(serialized(row)).to eq([ live_permission ])
      expect(serialized(row)).to match_array(delegation.reload.configured_permissions)
      expect(row['stale_permission_names']).to eq([ stale_permission ])
    end
  end

  describe 'a delegation with no stale names' do
    let!(:clean_delegation) do
      role = create(:role, name: 'account.reader', display_name: 'Account Reader', role_type: 'user')
      role.role_permissions.find_or_create_by!(permission_name: live_permission)
      d = create(:account_delegation, :active,
                 account: account,
                 delegated_by: manager_user,
                 delegated_user: create(:user, account: create(:account)),
                 role: role)
      d.delegation_permissions.create!(permission_name: live_permission)
      d.reload
    end

    it 'reports an empty stale list and the full configured set' do
      get "/api/v1/accounts/#{account.id}/delegations/#{clean_delegation.id}", headers: headers

      json = JSON.parse(response.body)
      expect(serialized(json['data']['delegation'])).to eq([ live_permission ])
      expect(json['data']['delegation']['stale_permission_names']).to eq([])
    end
  end

  describe 'a role-only delegation' do
    let!(:role_only_delegation) do
      role = create(:role, name: 'account.auditor', display_name: 'Account Auditor', role_type: 'user')
      role.role_permissions.find_or_create_by!(permission_name: live_permission)
      create(:account_delegation, :active,
             account: account,
             delegated_by: manager_user,
             delegated_user: create(:user, account: create(:account)),
             role: role)
    end

    it 'lists the role set it actually confers and no stale names' do
      get "/api/v1/accounts/#{account.id}/delegations/#{role_only_delegation.id}", headers: headers

      json = JSON.parse(response.body)
      # Literal anchor first — the role grants exactly `live_permission`, so an
      # empty custom set resolves to exactly that.
      expect(serialized(json['data']['delegation'])).to eq([ live_permission ])
      expect(serialized(json['data']['delegation']))
        .to match_array(role_only_delegation.configured_permissions)
      expect(json['data']['delegation']['stale_permission_names']).to eq([])
    end
  end

  # `permissions` is the CONFIGURED set and is status-INDEPENDENT, while
  # `permissions_summary` is built from #effective_permissions and is empty
  # unless the delegation is active. On a non-active row the two therefore
  # disagree, deliberately — this pins that split in BOTH directions so a later
  # change to either field has to state which basis it meant.
  describe 'a non-active delegation' do
    let!(:revoked_delegation) do
      role = create(:role, name: 'account.retired', display_name: 'Account Retired', role_type: 'user')
      role.role_permissions.find_or_create_by!(permission_name: live_permission)
      d = create(:account_delegation, :revoked,
                 account: account,
                 delegated_by: manager_user,
                 delegated_user: create(:user, account: create(:account)),
                 role: role)
      d.delegation_permissions.create!(permission_name: live_permission)
      d.reload
    end

    it 'reports the configured set with an effective summary that says it confers nothing' do
      get "/api/v1/accounts/#{account.id}/delegations/#{revoked_delegation.id}", headers: headers

      json = JSON.parse(response.body)
      body = json['data']['delegation']

      expect(body['is_active']).to be(false)
      expect(body['status']).to eq('revoked')
      expect(serialized(body)).to eq([ live_permission ])
      expect(body['permissions_summary']).to eq('No permissions')
      expect(body['stale_permission_names']).to eq([])
    end

    it 'still filters the stale stored name out of the configured set' do
      # The role loses the only name the stored row carries, underneath the row.
      revoked_delegation.role.role_permissions.where(permission_name: live_permission).delete_all
      revoked_delegation.role.reload

      get "/api/v1/accounts/#{account.id}/delegations/#{revoked_delegation.id}", headers: headers

      body = JSON.parse(response.body)['data']['delegation']
      expect(serialized(body)).to eq([])
      expect(body['stale_permission_names']).to eq([ live_permission ])
    end
  end
end
