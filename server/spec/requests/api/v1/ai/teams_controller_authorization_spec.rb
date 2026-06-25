# frozen_string_literal: true

require 'rails_helper'

# Authorization guard coverage for Api::V1::Ai::TeamsController.
#
# The controller previously ran every action with `authenticate_request` only
# and NO authorization filter — list/show/analytics and create/update/destroy
# all executed for any authenticated user. These specs lock in the gate:
#
#   READ  actions  -> require_any_permission("ai.teams.manage", "ai.teams.execute")
#   WRITE actions  -> require_permission("ai.teams.execute")
#
# Role holdings (see config/permissions.rb): `member` holds ai.teams.manage but
# NOT ai.teams.execute (intended read-only); `manager`/`owner`/`admin` hold both.
RSpec.describe 'Api::V1::Ai::TeamsController authorization', type: :request do
  let(:account) { create(:account) }
  let!(:team) { create(:ai_agent_team, account: account) }

  # Representative READ + WRITE endpoints. The gate is shared per group, so two
  # endpoints exercise the full mapping without enumerating all 8 actions.
  def get_read_index(user)
    get "/api/v1/ai/teams", headers: auth_headers_for(user)
  end

  def get_read_show(user)
    get "/api/v1/ai/teams/#{team.id}", headers: auth_headers_for(user)
  end

  def post_write_create(user)
    post "/api/v1/ai/teams",
         params: { name: 'New Team' }.to_json,
         headers: auth_headers_for(user)
  end

  def delete_write_destroy(user)
    delete "/api/v1/ai/teams/#{team.id}", headers: auth_headers_for(user)
  end

  describe 'user with NO permissions (permissions: [])' do
    let(:user) { create(:user, account: account, permissions: []) }

    it 'is forbidden on a READ action (index)' do
      get_read_index(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a READ action (show)' do
      get_read_show(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (create)' do
      post_write_create(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (destroy)' do
      delete_write_destroy(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user with ONLY ai.teams.manage (member-equivalent, read-only)' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.manage']) }

    it 'is NOT forbidden on a READ action (index)' do
      get_read_index(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a READ action (show)' do
      get_read_show(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (create) — manage can read but not mutate' do
      post_write_create(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (destroy) — manage can read but not mutate' do
      delete_write_destroy(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user with ai.teams.execute' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.execute']) }

    it 'is NOT forbidden on a READ action (index)' do
      get_read_index(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a WRITE action (create)' do
      post_write_create(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a WRITE action (destroy)' do
      delete_write_destroy(user)
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
