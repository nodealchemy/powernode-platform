# frozen_string_literal: true

require 'rails_helper'

# Stub Ai::AgentTeamExecutionJob (defined in worker service)
module Ai
  class AgentTeamExecutionJob
    def self.perform_async(*args)
      'job-id'
    end
  end
end

RSpec.describe 'Api::V1::Ai::AgentTeams', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  let!(:team_role) do
    role = Role.create!(
      name: 'ai_team_manager',
      display_name: 'AI Team Manager',
      role_type: 'user',
      description: 'Can manage AI agent teams'
    )

    # Create and assign permissions
    [ 'ai.teams.manage', 'ai.teams.execute' ].each do |perm_name|
      permission = Permission.find_or_create_from_name!(perm_name, {
        resource: 'ai.teams',
        action: perm_name.split('.').last,
        description: "#{perm_name.split('.').last.capitalize} AI agent teams"
      })
      role.permissions << permission unless role.permissions.include?(permission)
    end

    role
  end

  # Force eager evaluation with let! and save after role assignment
  let!(:user) do
    u = create(:user, :manager, account: account)
    UserRole.find_or_create_by!(user: u, role: team_role)
    u.reload # Reload to get fresh permissions
    u
  end

  let!(:other_user) { create(:user, :manager, account: other_account) }
  let!(:limited_user) { create(:user, :member, account: account) }

  let(:headers) { auth_headers_for(user) }
  let(:other_headers) { auth_headers_for(other_user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  describe 'GET /api/v1/ai/agent_teams' do
    let!(:team1) { create(:ai_agent_team, account: account, name: 'Team 1', team_type: 'sequential', status: 'active') }
    let!(:team2) { create(:ai_agent_team, account: account, name: 'Team 2', team_type: 'parallel', status: 'active') }
    let!(:team3) { create(:ai_agent_team, account: account, name: 'Team 3', team_type: 'hierarchical', status: 'inactive') }
    let!(:other_team) { create(:ai_agent_team, account: other_account) }

    context 'with valid authentication' do
      it 'returns all teams for the account' do
        get '/api/v1/ai/agent_teams', headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data'].size).to eq(3)
        expect(full_response['data'].map { |t| t['name'] }).to match_array([ 'Team 1', 'Team 2', 'Team 3' ])
      end

      it 'filters by status' do
        get '/api/v1/ai/agent_teams', params: { status: 'active' }, headers: headers

        expect_success_response
        full_response = json_response_full
        expect(full_response['data'].size).to eq(2)
        expect(full_response['data'].all? { |t| t['status'] == 'active' }).to be true
        expect(full_response['meta']['filters']['status']).to eq('active')
      end

      it 'filters by team_type' do
        get '/api/v1/ai/agent_teams', params: { team_type: 'sequential' }, headers: headers

        expect_success_response
        full_response = json_response_full
        expect(full_response['data'].size).to eq(1)
        expect(full_response['data'].first['team_type']).to eq('sequential')
        expect(full_response['meta']['filters']['team_type']).to eq('sequential')
      end

      it 'includes member count in response' do
        create(:ai_agent_team_member, team: team1)
        create(:ai_agent_team_member, team: team1)

        get '/api/v1/ai/agent_teams', headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        team1_data = full_response['data'].find { |t| t['id'] == team1.id }
        expect(team1_data['member_count']).to eq(2)
      end

      it 'does not include teams from other accounts' do
        get '/api/v1/ai/agent_teams', headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data'].none? { |t| t['id'] == other_team.id }).to be true
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get '/api/v1/ai/agent_teams', as: :json
        expect_error_response('Access token required', 401)
      end
    end

    context 'without permission' do
      let(:no_perm_user) { create(:user, account: account, permissions: []) }

      it 'returns forbidden' do
        get '/api/v1/ai/agent_teams', headers: auth_headers_for(no_perm_user), as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/agent_teams/:id' do
    let(:team) { create(:ai_agent_team, :content_generation_crew, account: account) }

    context 'with valid authentication' do
      it 'returns team details' do
        get "/api/v1/ai/agent_teams/#{team.id}", headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['id']).to eq(team.id)
        expect(full_response['data']['name']).to eq(team.name)
        expect(full_response['data']['team_type']).to eq(team.team_type)
      end

      it 'includes team members' do
        get "/api/v1/ai/agent_teams/#{team.id}", headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['members']).to be_an(Array)
        expect(full_response['data']['members'].size).to eq(3)

        # Verify members are ordered by priority
        priorities = full_response['data']['members'].map { |m| m['priority_order'] }
        expect(priorities).to eq([ 0, 1, 2 ])
      end

      it 'includes team config' do
        team.update!(team_config: { 'max_iterations' => 5, 'timeout' => 300 })
        get "/api/v1/ai/agent_teams/#{team.id}", headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['team_config']).to eq({ 'max_iterations' => 5, 'timeout' => 300 })
      end

      it 'includes team stats' do
        get "/api/v1/ai/agent_teams/#{team.id}", headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['stats']).to be_a(Hash)
        expect(full_response['data']['stats']).to have_key('member_count')
        expect(full_response['data']['stats']).to have_key('has_lead')
      end
    end

    context 'with team from another account' do
      let(:other_team) { create(:ai_agent_team, account: other_account) }

      it 'returns not found' do
        get "/api/v1/ai/agent_teams/#{other_team.id}", headers: headers, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with non-existent team' do
      it 'returns not found' do
        get "/api/v1/ai/agent_teams/#{SecureRandom.uuid}", headers: headers, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/agent_teams' do
    let(:valid_params) do
      {
        name: 'New Team',
        description: 'A new test team',
        team_type: 'sequential',
        coordination_strategy: 'priority_based',
        status: 'active',
        team_config: { 'max_iterations' => 10 }
      }
    end

    context 'with valid params' do
      it 'creates a new team' do
        expect {
          post '/api/v1/ai/agent_teams', params: valid_params, headers: headers, as: :json
        }.to change(Ai::AgentTeam, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['name']).to eq('New Team')
        expect(full_response['data']['team_type']).to eq('sequential')
      end

      it 'associates team with current account' do
        post '/api/v1/ai/agent_teams', params: valid_params, headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        team = Ai::AgentTeam.find(full_response['data']['id'])
        expect(team.account_id).to eq(account.id)
      end

      it 'creates audit log entry' do
        post '/api/v1/ai/agent_teams', params: valid_params, headers: headers, as: :json

        audit_log = AuditLog.where(action: 'ai_agent_team.created').last
        expect(audit_log).to be_present
        expect(audit_log.resource_type).to eq('Ai::AgentTeam')
        expect(audit_log.metadata['team_name']).to eq('New Team')
      end
    end

    context 'with invalid params' do
      it 'returns validation errors for missing name' do
        invalid_params = valid_params.deep_dup
        invalid_params[:name] = nil

        post '/api/v1/ai/agent_teams', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        full_response = json_response_full
        expect(full_response['success']).to be false
        expect(full_response['details']).to be_present
      end

      it 'returns validation errors for invalid team_type' do
        invalid_params = valid_params.deep_dup
        invalid_params[:team_type] = 'invalid_type'

        post '/api/v1/ai/agent_teams', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns validation errors for incompatible coordination strategy' do
        invalid_params = valid_params.deep_dup
        invalid_params[:team_type] = 'mesh'
        invalid_params[:coordination_strategy] = 'manager_led'

        post '/api/v1/ai/agent_teams', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        full_response = json_response_full
        expect(full_response['details']['errors'].join).to include(/coordination strategy/i)
      end
    end
  end

  describe 'PATCH /api/v1/ai/agent_teams/:id' do
    let(:team) { create(:ai_agent_team, account: account, name: 'Original Name') }

    context 'with valid params' do
      let(:update_params) do
        {
          name: 'Updated Name',
          description: 'Updated description',
          status: 'inactive'
        }
      end

      it 'updates the team' do
        patch "/api/v1/ai/agent_teams/#{team.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['name']).to eq('Updated Name')
        expect(full_response['data']['description']).to eq('Updated description')
        expect(full_response['data']['status']).to eq('inactive')
      end

      it 'creates audit log entry' do
        patch "/api/v1/ai/agent_teams/#{team.id}", params: update_params, headers: headers, as: :json

        audit_log = AuditLog.where(action: 'ai_agent_team.updated').last
        expect(audit_log).to be_present
        expect(audit_log.resource_type).to eq('Ai::AgentTeam')
        expect(audit_log.metadata['changes']).to include('name', 'description', 'status')
      end
    end

    context 'with invalid params' do
      it 'returns validation errors' do
        invalid_params = { name: '' }
        patch "/api/v1/ai/agent_teams/#{team.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        full_response = json_response_full
        expect(full_response['success']).to be false
      end
    end
  end

  describe 'DELETE /api/v1/ai/agent_teams/:id' do
    let!(:team) { create(:ai_agent_team, account: account) }

    context 'with valid team' do
      it 'deletes the team' do
        expect {
          delete "/api/v1/ai/agent_teams/#{team.id}", headers: headers, as: :json
        }.to change(Ai::AgentTeam, :count).by(-1)

        expect_success_response
        full_response = json_response_full
      end

      it 'creates audit log entry' do
        team_name = team.name
        delete "/api/v1/ai/agent_teams/#{team.id}", headers: headers, as: :json

        audit_log = AuditLog.where(action: 'ai_agent_team.deleted').last
        expect(audit_log).to be_present
        expect(audit_log.resource_type).to eq('Ai::AgentTeam')
        expect(audit_log.metadata['team_name']).to eq(team_name)
      end
    end
  end

  describe 'POST /api/v1/ai/agent_teams/:id/members' do
    let(:team) { create(:ai_agent_team, account: account) }
    let(:agent) { create(:ai_agent, account: account) }

    context 'with valid params' do
      let(:member_params) do
        {
          agent_id: agent.id,
          role: 'researcher',
          capabilities: [ 'data_analysis', 'research' ],
          priority_order: 0,
          is_lead: true
        }
      end

      it 'adds member to team' do
        expect {
          post "/api/v1/ai/agent_teams/#{team.id}/members", params: member_params, headers: headers, as: :json
        }.to change(team.members, :count).by(1)

        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['role']).to eq('researcher')
        expect(full_response['data']['capabilities']).to match_array([ 'data_analysis', 'research' ])
        expect(full_response['data']['is_lead']).to be true
      end

      it 'creates audit log entry' do
        post "/api/v1/ai/agent_teams/#{team.id}/members", params: member_params, headers: headers, as: :json

        audit_log = AuditLog.where(action: 'ai_agent_team.member_added').last
        expect(audit_log).to be_present
        expect(audit_log.resource_type).to eq('Ai::AgentTeamMember')
        expect(audit_log.metadata['agent_id']).to eq(agent.id)
        expect(audit_log.metadata['role']).to eq('researcher')
      end

      it 'auto-assigns priority order if not provided' do
        params_without_priority = member_params.except(:priority_order)

        post "/api/v1/ai/agent_teams/#{team.id}/members", params: params_without_priority, headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['priority_order']).to be >= 0
      end
    end

    context 'with non-existent agent' do
      it 'returns not found' do
        params = { agent_id: SecureRandom.uuid, role: 'researcher' }
        post "/api/v1/ai/agent_teams/#{team.id}/members", params: params, headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        full_response = json_response_full
        expect(full_response['error']).to eq('Agent not found')
      end
    end

    context 'with agent from another account' do
      let(:other_agent) { create(:ai_agent, account: other_account) }

      it 'returns not found' do
        params = { agent_id: other_agent.id, role: 'researcher' }
        post "/api/v1/ai/agent_teams/#{team.id}/members", params: params, headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with invalid params' do
      it 'returns validation errors for missing role' do
        params = { agent_id: agent.id }
        post "/api/v1/ai/agent_teams/#{team.id}/members", params: params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        full_response = json_response_full
        expect(full_response['success']).to be false
      end
    end
  end

  describe 'DELETE /api/v1/ai/agent_teams/:id/members/:member_id' do
    let(:team) { create(:ai_agent_team, account: account) }
    let(:member) { create(:ai_agent_team_member, team: team) }

    context 'with valid member' do
      it 'removes member from team' do
        member_id = member.id

        expect {
          delete "/api/v1/ai/agent_teams/#{team.id}/members/#{member_id}", headers: headers, as: :json
        }.to change(team.members, :count).by(-1)

        expect_success_response
        full_response = json_response_full
      end

      it 'creates audit log entry' do
        member_id = member.id
        agent_name = member.ai_agent_name
        delete "/api/v1/ai/agent_teams/#{team.id}/members/#{member_id}", headers: headers, as: :json

        audit_log = AuditLog.where(action: 'ai_agent_team.member_removed').last
        expect(audit_log).to be_present
        expect(audit_log.resource_type).to eq('Ai::AgentTeamMember')
        expect(audit_log.metadata['agent_name']).to eq(agent_name)
      end
    end

    context 'with non-existent member' do
      it 'returns not found' do
        delete "/api/v1/ai/agent_teams/#{team.id}/members/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        full_response = json_response_full
        expect(full_response['error']).to eq('Member not found')
      end
    end
  end

  describe 'POST /api/v1/ai/agent_teams/:id/execute' do
    let(:team) { create(:ai_agent_team, :content_generation_crew, account: account) }

    context 'with valid params' do
      let(:execute_params) do
        {
          input: { task: 'Generate blog post about AI' },
          context: { priority: 'high', deadline: '2024-12-31' }
        }
      end

      it 'queues team execution job' do
        expect(Ai::AgentTeamExecutionJob).to receive(:perform_async).with(
          hash_including(
            team_id: team.id,
            user_id: user.id
          )
        ).and_return('job-123')

        post "/api/v1/ai/agent_teams/#{team.id}/execute", params: execute_params, headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['team_id']).to eq(team.id)
        expect(full_response['data']['job_id']).to eq('job-123')
        expect(full_response['data']['status']).to eq('queued')
      end

      it 'handles empty input' do
        expect(Ai::AgentTeamExecutionJob).to receive(:perform_async).and_return('job-456')

        post "/api/v1/ai/agent_teams/#{team.id}/execute", headers: headers, as: :json

        expect_success_response
        full_response = json_response_full
        expect(full_response['data']['job_id']).to eq('job-456')
      end

      it 'creates audit log entry' do
        allow(Ai::AgentTeamExecutionJob).to receive(:perform_async).and_return('job-789')
        post "/api/v1/ai/agent_teams/#{team.id}/execute", params: execute_params, headers: headers, as: :json

        audit_log = AuditLog.where(action: 'ai_agent_team.execution_started').last
        expect(audit_log).to be_present
        expect(audit_log.resource_type).to eq('Ai::AgentTeam')
        expect(audit_log.metadata['job_id']).to eq('job-789')
      end
    end

    context 'without execute permission' do
      let(:manage_only_user) { create(:user, account: account, permissions: ['ai.teams.manage']) }

      it 'returns forbidden' do
        post "/api/v1/ai/agent_teams/#{team.id}/execute", headers: auth_headers_for(manage_only_user), as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when job fails to queue' do
      it 'returns error' do
        allow(Ai::AgentTeamExecutionJob).to receive(:perform_async).and_raise(StandardError, 'Queue error')

        post "/api/v1/ai/agent_teams/#{team.id}/execute", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        full_response = json_response_full
        expect(full_response['error']).to include('Failed to execute team')
      end
    end
  end

  describe 'POST /api/v1/ai/agent_teams/:id/execution_complete' do
    let!(:team) { create(:ai_agent_team, account: account) }

    context 'with valid params' do
      let(:completion_params) do
        {
          job_id: 'job-123',
          completed_at: Time.current.iso8601,
          result: { output: 'Generated content' }
        }
      end

      it 'records execution completion' do
        post "/api/v1/ai/agent_teams/#{team.id}/execute_complete",
             params: completion_params,
             headers: headers,
             as: :json

        expect_success_response

        audit_log = AuditLog.where(action: 'ai_agent_team.execution_completed').last
        expect(audit_log).to be_present
        expect(audit_log.resource_type).to eq('Ai::AgentTeam')
        expect(audit_log.metadata['job_id']).to eq('job-123')
      end
    end
  end

  describe 'POST /api/v1/ai/agent_teams/:id/execution_failed' do
    let!(:team) { create(:ai_agent_team, account: account) }

    context 'with valid params' do
      let(:failure_params) do
        {
          job_id: 'job-456',
          failed_at: Time.current.iso8601,
          error: 'Agent execution failed'
        }
      end

      it 'records execution failure' do
        post "/api/v1/ai/agent_teams/#{team.id}/execute_failed",
             params: failure_params,
             headers: headers,
             as: :json

        expect_success_response

        audit_log = AuditLog.where(action: 'ai_agent_team.execution_failed').last
        expect(audit_log).to be_present
        expect(audit_log.resource_type).to eq('Ai::AgentTeam')
        expect(audit_log.metadata['error']).to eq('Agent execution failed')
      end
    end
  end
end
