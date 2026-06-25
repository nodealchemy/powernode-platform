# frozen_string_literal: true

require 'rails_helper'

# Authorization guard coverage for Api::V1::Ai::AgentTeamExecutionsController.
#
# The controller previously ran every action with `authenticate_request` only
# and NO authorization filter — index/show reads and cancel/pause/resume/retry
# mutations all executed for any authenticated user. These specs lock in the gate:
#
#   READ  actions  -> require_any_permission("ai.teams.manage", "ai.teams.execute")
#   WRITE actions  -> require_permission("ai.teams.execute")
#
# Role holdings (see config/permissions.rb): `member` holds ai.teams.manage but
# NOT ai.teams.execute (intended read-only); `manager`/`owner`/`admin` hold both.
RSpec.describe 'Api::V1::Ai::AgentTeamExecutionsController authorization', type: :request do
  let(:account) { create(:account) }
  let!(:team) { create(:ai_agent_team, account: account) }
  let!(:execution) { create(:ai_team_execution, :running, account: account, agent_team: team) }

  # Representative READ + WRITE endpoints.
  def get_read_index(user)
    get "/api/v1/ai/agent_teams/#{team.id}/executions", headers: auth_headers_for(user)
  end

  def get_read_show(user)
    get "/api/v1/ai/agent_teams/#{team.id}/executions/#{execution.id}", headers: auth_headers_for(user)
  end

  def post_write_cancel(user)
    post "/api/v1/ai/agent_teams/#{team.id}/executions/#{execution.id}/cancel",
         params: {}.to_json,
         headers: auth_headers_for(user)
  end

  def post_write_pause(user)
    post "/api/v1/ai/agent_teams/#{team.id}/executions/#{execution.id}/pause",
         params: {}.to_json,
         headers: auth_headers_for(user)
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

    it 'is forbidden on a WRITE action (cancel)' do
      post_write_cancel(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (pause)' do
      post_write_pause(user)
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

    it 'is forbidden on a WRITE action (cancel) — manage can read but not mutate' do
      post_write_cancel(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (pause) — manage can read but not mutate' do
      post_write_pause(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user with ai.teams.execute' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.execute']) }

    it 'is NOT forbidden on a READ action (index)' do
      get_read_index(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a WRITE action (cancel)' do
      post_write_cancel(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a WRITE action (pause)' do
      post_write_pause(user)
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
