# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::TeamRolesChannelsController", type: :request do
  let(:account) { create(:account) }
  let(:auth_user) { user_with_permissions('ai.teams.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  let!(:team) { create(:ai_agent_team, account: account) }
  let!(:role) { create(:ai_team_role, account: account, agent_team: team) }
  let!(:channel) { create(:ai_team_channel, agent_team: team) }

  # Service mocks
  let(:mock_crud_service) { instance_double(::Ai::Teams::CrudService) }
  let(:mock_config_service) { instance_double(::Ai::Teams::ConfigurationService) }

  before do
    allow(::Ai::Teams::CrudService).to receive(:new).and_return(mock_crud_service)
    allow(::Ai::Teams::ConfigurationService).to receive(:new).and_return(mock_config_service)
    allow(mock_crud_service).to receive(:get_team).and_return(team)
  end

  # =========================================================================
  # LIST ROLES
  # =========================================================================
  describe "GET /api/v1/ai/teams/:team_id/roles" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/roles" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_config_service).to receive(:list_roles).with(team.id).and_return([role])

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('roles')
    end
  end

  # =========================================================================
  # CREATE ROLE
  # =========================================================================
  describe "POST /api/v1/ai/teams/:team_id/roles" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/roles" }
    let(:role_params) { { role_name: "Developer", role_type: "worker" } }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 201 when role created successfully' do
      new_role = build(:ai_team_role, account: account, agent_team: team, role_name: "Developer")
      allow(new_role).to receive(:id).and_return(SecureRandom.uuid)
      allow(new_role).to receive(:ai_agent).and_return(nil)
      allow(mock_config_service).to receive(:create_role).and_return(new_role)

      post path, params: role_params,
                 headers: auth_headers_for(auth_user),
                 as: :json
      expect(response).to have_http_status(:created)
    end
  end

  # =========================================================================
  # UPDATE ROLE
  # =========================================================================
  describe "PATCH /api/v1/ai/teams/:team_id/roles/:id" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/roles/#{role.id}" }

    it 'returns 401 when unauthenticated' do
      patch path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when role updated' do
      allow(mock_config_service).to receive(:update_role).and_return(role)

      patch path, params: { role_name: "Updated Role" },
                  headers: auth_headers_for(auth_user),
                  as: :json
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # DELETE ROLE
  # =========================================================================
  describe "DELETE /api/v1/ai/teams/:team_id/roles/:id" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/roles/#{role.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when role deleted' do
      allow(mock_config_service).to receive(:delete_role).and_return(true)

      delete path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # ASSIGN AGENT TO ROLE
  # =========================================================================
  describe "POST /api/v1/ai/teams/:team_id/roles/:id/assign_agent" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/roles/#{role.id}/assign_agent" }
    let(:agent) { create(:ai_agent, account: account) }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when agent assigned' do
      allow(mock_config_service).to receive(:assign_agent_to_role).and_return(role)

      post path, params: { agent_id: agent.id },
                 headers: auth_headers_for(auth_user),
                 as: :json
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # LIST CHANNELS
  # =========================================================================
  describe "GET /api/v1/ai/teams/:team_id/channels" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/channels" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_config_service).to receive(:list_channels).with(team.id).and_return([channel])

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('channels')
    end
  end

  # =========================================================================
  # CREATE CHANNEL
  # =========================================================================
  describe "POST /api/v1/ai/teams/:team_id/channels" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/channels" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 201 when channel created' do
      new_channel = build(:ai_team_channel, agent_team: team, name: "New Channel")
      allow(new_channel).to receive(:id).and_return(SecureRandom.uuid)
      allow(new_channel).to receive(:message_count).and_return(0)
      allow(mock_config_service).to receive(:create_channel).and_return(new_channel)

      post path, params: { channel: { name: "New Channel", channel_type: "broadcast" } },
                 headers: auth_headers_for(auth_user),
                 as: :json
      expect(response).to have_http_status(:created)
    end
  end

  # =========================================================================
  # SHOW CHANNEL
  # =========================================================================
  describe "GET /api/v1/ai/teams/:team_id/channels/:id" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/channels/#{channel.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_config_service).to receive(:get_channel).and_return(channel)

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # UPDATE CHANNEL
  # =========================================================================
  describe "PATCH /api/v1/ai/teams/:team_id/channels/:id" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/channels/#{channel.id}" }

    it 'returns 401 when unauthenticated' do
      patch path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when channel updated' do
      allow(mock_config_service).to receive(:update_channel).and_return(channel)

      patch path, params: { channel: { name: "Updated Channel" } },
                  headers: auth_headers_for(auth_user),
                  as: :json
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # DELETE CHANNEL
  # =========================================================================
  describe "DELETE /api/v1/ai/teams/:team_id/channels/:id" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/channels/#{channel.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when channel deleted' do
      allow(mock_config_service).to receive(:delete_channel).and_return(true)

      delete path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CLEANUP MESSAGES
  # =========================================================================
  describe "POST /api/v1/ai/teams/cleanup_messages" do
    let(:path) { "/api/v1/ai/teams/cleanup_messages" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      post path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('channels_processed')
      expect(json_response['data']).to have_key('messages_deleted')
    end
  end
end
