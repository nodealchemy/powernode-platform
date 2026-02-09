# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Teams - Channels', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.teams.read', 'ai.teams.write' ]) }
  let(:headers) { auth_headers_for(user) }
  let(:team_service) { instance_double(Ai::TeamOrchestrationService) }

  before do
    allow(Ai::TeamOrchestrationService).to receive(:new).and_return(team_service)
  end

  let(:channel_double) do
    double(
      id: 'ch-123',
      name: 'General',
      channel_type: 'broadcast',
      description: 'General channel',
      is_persistent: true,
      message_retention_hours: 24,
      participant_roles: ['role-1'],
      message_count: 5,
      routing_rules: { priority_routing: true },
      message_schema: { type: 'structured' },
      metadata: { custom: 'data' },
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  let(:message_double) do
    replies_double = double(count: 2)
    double(
      id: 'msg-123',
      sequence_number: 1,
      message_type: 'task_update',
      content: 'Test message',
      from_role_id: 'role-1',
      from_role: double(role_name: 'Lead'),
      to_role_id: 'role-2',
      to_role: double(role_name: 'Worker'),
      channel_id: 'ch-123',
      priority: 'normal',
      requires_response: false,
      responded_at: nil,
      created_at: Time.current,
      structured_content: { key: 'value' },
      attachments: [],
      read_at: nil,
      in_reply_to_id: nil,
      replies: replies_double
    )
  end

  describe 'GET /api/v1/ai/teams/:team_id/channels' do
    it 'returns list of channels' do
      allow(team_service).to receive(:get_team).and_return(double(id: 't-123'))
      allow(team_service).to receive(:list_channels).and_return([channel_double])

      get '/api/v1/ai/teams/t-123/channels', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['channels']).to be_an(Array)
      expect(data['channels'].first['id']).to eq('ch-123')
      expect(data['channels'].first['routing_rules']).to be_present
      expect(data['channels'].first['message_schema']).to be_present
      expect(data['channels'].first['metadata']).to be_present
      expect(data['channels'].first['created_at']).to be_present
      expect(data['channels'].first['updated_at']).to be_present
    end
  end

  describe 'GET /api/v1/ai/teams/:team_id/channels/:id' do
    it 'returns single channel with full serialization' do
      allow(team_service).to receive(:get_team).and_return(double(id: 't-123'))
      allow(team_service).to receive(:get_channel).and_return(channel_double)

      get '/api/v1/ai/teams/t-123/channels/ch-123', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['id']).to eq('ch-123')
      %w[id name channel_type description is_persistent message_retention_hours
         participant_roles message_count routing_rules message_schema metadata
         created_at updated_at].each do |field|
        expect(data).to have_key(field), "Missing field: #{field}"
      end
    end

    it 'returns 404 for non-existent channel' do
      allow(team_service).to receive(:get_team).and_return(double(id: 't-123'))
      allow(team_service).to receive(:get_channel).and_raise(
        ActiveRecord::RecordNotFound.new("Couldn't find channel", 'Ai::TeamChannel')
      )

      get '/api/v1/ai/teams/t-123/channels/bad-id', headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/ai/teams/:team_id/channels' do
    it 'creates channel and returns 201' do
      allow(team_service).to receive(:get_team).and_return(double(id: 't-123'))
      allow(team_service).to receive(:create_channel).and_return(channel_double)

      post '/api/v1/ai/teams/t-123/channels',
           params: { channel: { name: 'General', channel_type: 'broadcast' } },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data['id']).to eq('ch-123')
    end
  end

  describe 'PATCH /api/v1/ai/teams/:team_id/channels/:id' do
    it 'updates channel' do
      allow(team_service).to receive(:get_team).and_return(double(id: 't-123'))
      allow(team_service).to receive(:update_channel).and_return(channel_double)

      patch '/api/v1/ai/teams/t-123/channels/ch-123',
            params: { channel: { name: 'Updated' } },
            headers: headers,
            as: :json

      expect_success_response
      data = json_response_data
      expect(data['id']).to eq('ch-123')
    end
  end

  describe 'DELETE /api/v1/ai/teams/:team_id/channels/:id' do
    it 'deletes channel' do
      allow(team_service).to receive(:get_team).and_return(double(id: 't-123'))
      allow(team_service).to receive(:delete_channel).and_return(true)

      delete '/api/v1/ai/teams/t-123/channels/ch-123', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to include('deleted')
    end
  end

  describe 'POST /api/v1/ai/teams/cleanup_messages' do
    it 'runs cleanup and returns counts' do
      team = create(:ai_agent_team, account: account)
      create(:ai_team_channel, agent_team: team, message_retention_hours: 1)

      post '/api/v1/ai/teams/cleanup_messages', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('channels_processed')
      expect(data).to have_key('messages_deleted')
    end
  end

  describe 'message serialization' do
    it 'includes all enhanced fields' do
      execution_double = double(id: 'ex-123')
      allow(team_service).to receive(:get_execution).and_return(execution_double)
      allow(team_service).to receive(:get_messages).and_return([message_double])

      get '/api/v1/ai/teams/executions/ex-123/messages', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      msg = data['messages'].first
      expect(msg).to have_key('structured_content')
      expect(msg).to have_key('attachments')
      expect(msg).to have_key('read_at')
      expect(msg).to have_key('in_reply_to_id')
      expect(msg).to have_key('reply_count')
    end
  end
end
