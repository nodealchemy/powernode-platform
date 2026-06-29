# frozen_string_literal: true

require 'rails_helper'

# Authorization guard coverage for Api::V1::Ai::TeamRolesChannelsController.
#
# The controller previously ran every action with `authenticate_request` only
# and NO authorization filter — list/show and create/update/delete of roles and
# channels all executed for any authenticated user. These specs lock in the gate:
#
#   READ  actions  -> require_any_permission("ai.teams.manage", "ai.teams.execute")
#   WRITE actions  -> require_permission("ai.teams.execute")
#
# (cleanup_messages is a worker-internal endpoint and is intentionally NOT gated
# by a user permission — see the controller note — so it is not exercised here.)
#
# Role holdings (see config/permissions.rb): `member` holds ai.teams.manage but
# NOT ai.teams.execute (intended read-only); `manager`/`owner`/`admin` hold both.
RSpec.describe 'Api::V1::Ai::TeamRolesChannelsController authorization', type: :request do
  let(:account) { create(:account) }
  let!(:team) { create(:ai_agent_team, account: account) }
  let!(:role) { create(:ai_team_role, account: account, agent_team: team) }
  let!(:channel) { create(:ai_team_channel, agent_team: team) }

  # Representative READ + WRITE endpoints across both roles and channels.
  def get_read_list_roles(user)
    get "/api/v1/ai/teams/#{team.id}/roles", headers: auth_headers_for(user)
  end

  def get_read_show_channel(user)
    get "/api/v1/ai/teams/#{team.id}/channels/#{channel.id}", headers: auth_headers_for(user)
  end

  def post_write_create_role(user)
    post "/api/v1/ai/teams/#{team.id}/roles",
         params: { role_name: 'Worker', role_type: 'worker' }.to_json,
         headers: auth_headers_for(user)
  end

  def delete_write_delete_channel(user)
    delete "/api/v1/ai/teams/#{team.id}/channels/#{channel.id}", headers: auth_headers_for(user)
  end

  describe 'user with NO permissions (permissions: [])' do
    let(:user) { create(:user, account: account, permissions: []) }

    it 'is forbidden on a READ action (list_roles)' do
      get_read_list_roles(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a READ action (show_channel)' do
      get_read_show_channel(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (create_role)' do
      post_write_create_role(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (delete_channel)' do
      delete_write_delete_channel(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user with ONLY ai.teams.manage (member-equivalent, read-only)' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.manage']) }

    it 'is NOT forbidden on a READ action (list_roles)' do
      get_read_list_roles(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a READ action (show_channel)' do
      get_read_show_channel(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (create_role) — manage can read but not mutate' do
      post_write_create_role(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (delete_channel) — manage can read but not mutate' do
      delete_write_delete_channel(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user with ai.teams.execute' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.execute']) }

    it 'is NOT forbidden on a READ action (list_roles)' do
      get_read_list_roles(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a WRITE action (create_role)' do
      post_write_create_role(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a WRITE action (delete_channel)' do
      delete_write_delete_channel(user)
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  # Cross-tenant isolation for create_role's `agent_id`. The team is already
  # account-scoped, but the referenced agent was wired in raw — so a caller could
  # attach ANOTHER account's private agent to their own team's role. The agent
  # must be constrained to Ai::Agent.for_account (own + GLOBAL).
  describe 'create_role agent_id tenancy' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.execute']) }

    def create_role_with_agent(agent_id)
      post "/api/v1/ai/teams/#{team.id}/roles",
           params: { role_name: 'Worker', role_type: 'worker', agent_id: agent_id }.to_json,
           headers: auth_headers_for(user)
    end

    it 'attaches an agent the account owns' do
      own_agent = create(:ai_agent, account: account)

      create_role_with_agent(own_agent.id)

      expect(response).to have_http_status(:created)
      expect(json_response_data['agent_id']).to eq(own_agent.id)
      expect(Ai::TeamRole.find(json_response_data['id']).ai_agent_id).to eq(own_agent.id)
    end

    it 'attaches a GLOBAL (account_id nil) agent' do
      global_agent = create(:ai_agent, account: account)
      global_agent.update_column(:account_id, nil)

      create_role_with_agent(global_agent.id)

      expect(response).to have_http_status(:created)
      expect(json_response_data['agent_id']).to eq(global_agent.id)
    end

    it "does NOT attach another account's agent (404, no role created)" do
      foreign_agent = create(:ai_agent, account: create(:account))

      expect {
        create_role_with_agent(foreign_agent.id)
      }.not_to change(Ai::TeamRole, :count)

      expect(response).to have_http_status(:not_found)
      expect(Ai::TeamRole.where(ai_agent_id: foreign_agent.id)).to be_empty
    end
  end
end
