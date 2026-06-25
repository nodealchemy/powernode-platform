# frozen_string_literal: true

require 'rails_helper'

# Authorization guard coverage for Api::V1::Ai::TeamExecutionController.
#
# The controller previously ran every action with `authenticate_request` only
# and NO authorization filter — execution lifecycle, task ops, and messages all
# executed for any authenticated user. These specs lock in the intended gate:
#
#   READ  actions  -> require_any_permission("ai.teams.manage", "ai.teams.execute")
#   WRITE actions  -> require_permission("ai.teams.execute")
#
# Role holdings (see config/permissions.rb): `member` holds ai.teams.manage but
# NOT ai.teams.execute (intended read-only); `manager`/`owner`/`admin` hold both.
RSpec.describe 'Api::V1::Ai::TeamExecutionController authorization', type: :request do
  let(:account) { create(:account) }

  # A real team + execution in the user's account so set_team_service /
  # resolve_account_for_services and set_team/set_execution resolve cleanly —
  # the authorization gate (a before_action) runs before the action body, but
  # set_team_service runs earlier and needs an account to resolve.
  let!(:team) { create(:ai_agent_team, account: account) }
  let!(:execution) { create(:ai_team_execution, account: account, agent_team: team) }

  # Representative READ + WRITE endpoints (the gate is shared per group, so two
  # endpoints exercise the full mapping without enumerating all 20 actions).
  def get_read_list(user)
    get "/api/v1/ai/teams/#{team.id}/executions", headers: auth_headers_for(user)
  end

  def get_read_show(user)
    get "/api/v1/ai/teams/executions/#{execution.id}", headers: auth_headers_for(user)
  end

  def post_write_start(user)
    post "/api/v1/ai/teams/#{team.id}/executions",
         params: { objective: 'test objective' }.to_json,
         headers: auth_headers_for(user)
  end

  def post_write_cancel(user)
    post "/api/v1/ai/teams/executions/#{execution.id}/cancel",
         params: { reason: 'test' }.to_json,
         headers: auth_headers_for(user)
  end

  describe 'user with NO permissions (permissions: [])' do
    let(:user) { create(:user, account: account, permissions: []) }

    it 'is forbidden on a READ action (list_executions)' do
      get_read_list(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a READ action (show_execution)' do
      get_read_show(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (start_execution)' do
      post_write_start(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (cancel_execution)' do
      post_write_cancel(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user with ONLY ai.teams.manage (member-equivalent, read-only)' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.manage']) }

    it 'is NOT forbidden on a READ action (list_executions)' do
      get_read_list(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a READ action (show_execution)' do
      get_read_show(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (start_execution) — manage can read but not mutate' do
      post_write_start(user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'is forbidden on a WRITE action (cancel_execution) — manage can read but not mutate' do
      post_write_cancel(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'user with ai.teams.execute' do
    let(:user) { create(:user, account: account, permissions: ['ai.teams.execute']) }

    it 'is NOT forbidden on a READ action (list_executions)' do
      get_read_list(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a WRITE action (start_execution)' do
      post_write_start(user)
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is NOT forbidden on a WRITE action (cancel_execution)' do
      post_write_cancel(user)
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
