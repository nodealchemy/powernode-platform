# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Teams', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.teams.read', 'ai.teams.write']) }

  let(:headers) { auth_headers_for(user) }

  let(:team_service) { instance_double(Ai::TeamOrchestrationService) }

  before do
    allow(Ai::TeamOrchestrationService).to receive(:new).and_return(team_service)
  end

  describe 'GET /api/v1/ai/teams' do
    context 'with valid authentication' do
      it 'returns list of teams' do
        teams = double(total_count: 2, map: [])
        allow(team_service).to receive(:list_teams).and_return(teams)

        get '/api/v1/ai/teams', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['teams']).to be_an(Array)
        expect(data['total_count']).to eq(2)
      end
    end
  end

  describe 'GET /api/v1/ai/teams/:id' do
    let(:team) do
      double(
        id: 't123',
        name: 'Test Team',
        description: 'A test team',
        status: 'active',
        team_type: 'general',
        team_topology: 'hierarchical',
        coordination_strategy: 'central',
        communication_pattern: 'hub_spoke',
        max_parallel_tasks: 5,
        created_at: Time.current,
        goal_description: 'Test goal',
        task_timeout_seconds: 300,
        escalation_policy: {},
        shared_memory_config: {},
        human_checkpoint_config: {},
        team_config: {},
        ai_team_roles: double(count: 2),
        ai_team_channels: double(count: 1)
      )
    end

    before do
      allow(team_service).to receive(:get_team).and_return(team)
    end

    context 'with valid authentication' do
      it 'returns team details' do
        get '/api/v1/ai/teams/t123', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq('t123')
      end
    end
  end

  describe 'POST /api/v1/ai/teams' do
    let(:valid_params) do
      {
        name: 'Test Team',
        description: 'A test team',
        team_topology: 'hierarchical'
      }
    end
    let(:created_team) do
      double(
        id: 't123',
        name: 'Test Team',
        description: 'A test team',
        status: 'active',
        team_type: 'general',
        team_topology: 'hierarchical',
        coordination_strategy: 'central',
        communication_pattern: 'hub_spoke',
        max_parallel_tasks: 5,
        created_at: Time.current
      )
    end

    context 'with valid authentication' do
      it 'creates a new team' do
        allow(team_service).to receive(:create_team).and_return(created_team)

        post '/api/v1/ai/teams', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(team_service).to have_received(:create_team)
          .with(hash_including(name: 'Test Team'), user: user)
      end

      it 'creates team from template' do
        allow(team_service).to receive(:create_team_from_template).and_return(created_team)

        post '/api/v1/ai/teams', params: { template_id: 'tmpl123', name: 'Test Team' }, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(team_service).to have_received(:create_team_from_template)
      end
    end
  end

  describe 'PATCH /api/v1/ai/teams/:id' do
    let(:team) do
      double(
        id: 't123',
        name: 'Updated Team',
        description: 'A test team',
        status: 'active',
        team_type: 'general',
        team_topology: 'hierarchical',
        coordination_strategy: 'central',
        communication_pattern: 'hub_spoke',
        max_parallel_tasks: 5,
        created_at: Time.current
      )
    end
    let(:update_params) { { name: 'Updated Team' } }

    before do
      allow(team_service).to receive(:get_team).and_return(team)
      allow(team_service).to receive(:update_team).and_return(team)
    end

    context 'with valid authentication' do
      it 'updates the team' do
        patch '/api/v1/ai/teams/t123', params: update_params, headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:update_team).with('t123', hash_including(name: 'Updated Team'))
      end
    end
  end

  describe 'DELETE /api/v1/ai/teams/:id' do
    let(:team) { double(id: 't123') }

    before do
      allow(team_service).to receive(:get_team).and_return(team)
      allow(team_service).to receive(:delete_team).and_return(true)
    end

    context 'with valid authentication' do
      it 'deletes the team' do
        delete '/api/v1/ai/teams/t123', headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:delete_team).with('t123')
      end
    end
  end

  describe 'GET /api/v1/ai/teams/:team_id/roles' do
    let(:team) { double(id: 't123') }

    before do
      allow(team_service).to receive(:get_team).and_return(team)
    end

    context 'with valid authentication' do
      it 'returns list of roles' do
        roles = []
        allow(team_service).to receive(:list_roles).and_return(roles)

        get '/api/v1/ai/teams/t123/roles', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['roles']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/teams/:team_id/roles' do
    let(:team) { double(id: 't123') }
    let(:valid_params) do
      {
        role_name: 'Developer',
        role_type: 'specialist',
        responsibilities: 'Write code'
      }
    end
    let(:created_role) do
      double(
        id: 'r123',
        role_name: 'Developer',
        role_type: 'specialist',
        role_description: nil,
        responsibilities: 'Write code',
        goals: nil,
        capabilities: [],
        constraints: [],
        tools_allowed: [],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 3,
        ai_agent_id: nil,
        ai_agent: nil
      )
    end

    before do
      allow(team_service).to receive(:get_team).and_return(team)
    end

    context 'with valid authentication' do
      it 'creates a new role' do
        allow(team_service).to receive(:create_role).and_return(created_role)

        post '/api/v1/ai/teams/t123/roles', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(team_service).to have_received(:create_role)
      end
    end
  end

  describe 'PATCH /api/v1/ai/teams/:team_id/roles/:id' do
    let(:team) { double(id: 't123') }
    let(:role) do
      double(
        id: 'r123',
        role_name: 'Senior Dev',
        role_type: 'specialist',
        role_description: nil,
        responsibilities: 'Write code',
        goals: nil,
        capabilities: [],
        constraints: [],
        tools_allowed: [],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 3,
        ai_agent_id: nil,
        ai_agent: nil
      )
    end

    before do
      allow(team_service).to receive(:get_team).and_return(team)
      allow(team_service).to receive(:update_role).and_return(role)
    end

    context 'with valid authentication' do
      it 'updates the role' do
        patch '/api/v1/ai/teams/t123/roles/r123', params: { role_name: 'Senior Dev' }, headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:update_role)
      end
    end
  end

  describe 'DELETE /api/v1/ai/teams/:team_id/roles/:id' do
    let(:team) { double(id: 't123') }

    before do
      allow(team_service).to receive(:get_team).and_return(team)
      allow(team_service).to receive(:delete_role).and_return(true)
    end

    context 'with valid authentication' do
      it 'deletes the role' do
        delete '/api/v1/ai/teams/t123/roles/r123', headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:delete_role).with('t123', 'r123')
      end
    end
  end

  describe 'POST /api/v1/ai/teams/:team_id/roles/:id/assign_agent' do
    let(:team) { double(id: 't123') }
    let(:role) do
      double(
        id: 'r123',
        role_name: 'Developer',
        role_type: 'specialist',
        role_description: nil,
        responsibilities: 'Write code',
        goals: nil,
        capabilities: [],
        constraints: [],
        tools_allowed: [],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 3,
        ai_agent_id: 'a123',
        ai_agent: double(name: 'Test Agent')
      )
    end

    before do
      allow(team_service).to receive(:get_team).and_return(team)
      allow(team_service).to receive(:assign_agent_to_role).and_return(role)
    end

    context 'with valid authentication' do
      it 'assigns agent to role' do
        post '/api/v1/ai/teams/t123/roles/r123/assign_agent',
             params: { agent_id: 'a123' }, headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:assign_agent_to_role).with('t123', 'r123', 'a123')
      end
    end
  end

  describe 'GET /api/v1/ai/teams/:team_id/channels' do
    let(:team) { double(id: 't123') }

    before do
      allow(team_service).to receive(:get_team).and_return(team)
    end

    context 'with valid authentication' do
      it 'returns list of channels' do
        channels = []
        allow(team_service).to receive(:list_channels).and_return(channels)

        get '/api/v1/ai/teams/t123/channels', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['channels']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/teams/:team_id/channels' do
    let(:team) { double(id: 't123') }
    let(:valid_params) do
      {
        name: 'General',
        channel_type: 'broadcast'
      }
    end
    let(:created_channel) do
      double(
        id: 'ch123',
        name: 'General',
        channel_type: 'broadcast',
        description: nil,
        is_persistent: true,
        message_retention_hours: 72,
        participant_roles: [],
        message_count: 0
      )
    end

    before do
      allow(team_service).to receive(:get_team).and_return(team)
    end

    context 'with valid authentication' do
      it 'creates a new channel' do
        allow(team_service).to receive(:create_channel).and_return(created_channel)

        post '/api/v1/ai/teams/t123/channels', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(team_service).to have_received(:create_channel)
      end
    end
  end

  describe 'GET /api/v1/ai/teams/:team_id/executions' do
    let(:team) { double(id: 't123') }

    before do
      allow(team_service).to receive(:get_team).and_return(team)
    end

    context 'with valid authentication' do
      it 'returns list of executions' do
        executions = double(total_count: 5, map: [])
        allow(team_service).to receive(:list_executions).and_return(executions)

        get '/api/v1/ai/teams/t123/executions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['executions']).to be_an(Array)
        expect(data['total_count']).to eq(5)
      end
    end
  end

  describe 'POST /api/v1/ai/teams/:team_id/executions' do
    let(:team) { double(id: 't123') }
    let(:valid_params) do
      {
        objective: 'Complete project',
        input_context: { data: 'test' }
      }
    end
    let(:created_execution) do
      double(
        id: 'e123',
        execution_id: 'exec-123',
        status: 'running',
        objective: 'Complete project',
        tasks_total: 0,
        tasks_completed: 0,
        tasks_failed: 0,
        progress_percentage: 0.0,
        messages_exchanged: 0,
        total_tokens_used: 0,
        total_cost_usd: 0.0,
        started_at: Time.current,
        completed_at: nil,
        duration_ms: nil,
        created_at: Time.current,
        input_context: { data: 'test' },
        output_result: nil,
        shared_memory: {},
        termination_reason: nil,
        performance_metrics: {}
      )
    end

    before do
      allow(team_service).to receive(:get_team).and_return(team)
    end

    context 'with valid authentication' do
      it 'starts a new execution' do
        allow(team_service).to receive(:start_execution).and_return(created_execution)

        post '/api/v1/ai/teams/t123/executions', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(team_service).to have_received(:start_execution)
      end
    end
  end

  describe 'GET /api/v1/ai/teams/executions/:id' do
    let(:execution) do
      double(
        id: 'e123',
        execution_id: 'exec-123',
        status: 'running',
        objective: 'Complete project',
        tasks_total: 5,
        tasks_completed: 2,
        tasks_failed: 0,
        progress_percentage: 40.0,
        messages_exchanged: 10,
        total_tokens_used: 1000,
        total_cost_usd: 0.05,
        started_at: Time.current,
        completed_at: nil,
        duration_ms: nil,
        created_at: Time.current,
        input_context: {},
        output_result: nil,
        shared_memory: {},
        termination_reason: nil,
        performance_metrics: {}
      )
    end

    before do
      allow(team_service).to receive(:get_execution).and_return(execution)
    end

    context 'with valid authentication' do
      it 'returns execution details' do
        get '/api/v1/ai/teams/executions/e123', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq('e123')
      end
    end
  end

  describe 'POST /api/v1/ai/teams/executions/:id/pause' do
    let(:execution) do
      double(
        id: 'e123',
        execution_id: 'exec-123',
        status: 'paused',
        objective: 'Complete project',
        tasks_total: 5,
        tasks_completed: 2,
        tasks_failed: 0,
        progress_percentage: 40.0,
        messages_exchanged: 10,
        total_tokens_used: 1000,
        total_cost_usd: 0.05,
        started_at: Time.current,
        completed_at: nil,
        duration_ms: nil,
        created_at: Time.current
      )
    end

    before do
      allow(team_service).to receive(:get_execution).and_return(execution)
      allow(team_service).to receive(:pause_execution).and_return(execution)
    end

    context 'with valid authentication' do
      it 'pauses the execution' do
        post '/api/v1/ai/teams/executions/e123/pause', headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:pause_execution).with('e123')
      end
    end
  end

  describe 'POST /api/v1/ai/teams/executions/:id/resume' do
    let(:execution) do
      double(
        id: 'e123',
        execution_id: 'exec-123',
        status: 'running',
        objective: 'Complete project',
        tasks_total: 5,
        tasks_completed: 2,
        tasks_failed: 0,
        progress_percentage: 40.0,
        messages_exchanged: 10,
        total_tokens_used: 1000,
        total_cost_usd: 0.05,
        started_at: Time.current,
        completed_at: nil,
        duration_ms: nil,
        created_at: Time.current
      )
    end

    before do
      allow(team_service).to receive(:get_execution).and_return(execution)
      allow(team_service).to receive(:resume_execution).and_return(execution)
    end

    context 'with valid authentication' do
      it 'resumes the execution' do
        post '/api/v1/ai/teams/executions/e123/resume', headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:resume_execution).with('e123')
      end
    end
  end

  describe 'POST /api/v1/ai/teams/executions/:id/cancel' do
    let(:execution) do
      double(
        id: 'e123',
        execution_id: 'exec-123',
        status: 'cancelled',
        objective: 'Complete project',
        tasks_total: 5,
        tasks_completed: 2,
        tasks_failed: 0,
        progress_percentage: 40.0,
        messages_exchanged: 10,
        total_tokens_used: 1000,
        total_cost_usd: 0.05,
        started_at: Time.current,
        completed_at: Time.current,
        duration_ms: 5000,
        created_at: Time.current
      )
    end

    before do
      allow(team_service).to receive(:get_execution).and_return(execution)
      allow(team_service).to receive(:cancel_execution).and_return(execution)
    end

    context 'with valid authentication' do
      it 'cancels the execution' do
        post '/api/v1/ai/teams/executions/e123/cancel',
             params: { reason: 'User requested' }, headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:cancel_execution).with('e123', reason: 'User requested')
      end
    end
  end

  describe 'POST /api/v1/ai/teams/executions/:id/complete' do
    let(:execution) do
      double(
        id: 'e123',
        execution_id: 'exec-123',
        status: 'completed',
        objective: 'Complete project',
        tasks_total: 5,
        tasks_completed: 5,
        tasks_failed: 0,
        progress_percentage: 100.0,
        messages_exchanged: 20,
        total_tokens_used: 2000,
        total_cost_usd: 0.10,
        started_at: Time.current,
        completed_at: Time.current,
        duration_ms: 10000,
        created_at: Time.current
      )
    end

    before do
      allow(team_service).to receive(:get_execution).and_return(execution)
      allow(team_service).to receive(:complete_execution).and_return(execution)
    end

    context 'with valid authentication' do
      it 'completes the execution' do
        post '/api/v1/ai/teams/executions/e123/complete',
             params: { result: { success: true } }, headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:complete_execution)
      end
    end
  end

  describe 'GET /api/v1/ai/teams/executions/:id/details' do
    let(:execution) { double(id: 'e123') }

    before do
      allow(team_service).to receive(:get_execution).and_return(execution)
    end

    context 'with valid authentication' do
      it 'returns detailed execution information' do
        details = { tasks: [], messages: [] }
        allow(team_service).to receive(:get_execution_details).and_return(details)

        get '/api/v1/ai/teams/executions/e123/details', headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:get_execution_details).with('e123')
      end
    end
  end

  describe 'GET /api/v1/ai/teams/executions/:execution_id/tasks' do
    let(:tasks_relation) { double(includes: []) }
    let(:execution) { double(id: 'e123', tasks: tasks_relation) }

    before do
      allow(team_service).to receive(:get_execution).and_return(execution)
      allow(tasks_relation).to receive(:includes).with(:assigned_role, :assigned_agent).and_return([])
    end

    context 'with valid authentication' do
      it 'returns list of tasks' do
        get '/api/v1/ai/teams/executions/e123/tasks', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['tasks']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/teams/executions/:execution_id/tasks' do
    let(:execution) { double(id: 'e123') }
    let(:valid_params) do
      {
        description: 'Test task',
        task_type: 'execution'
      }
    end
    let(:created_task) do
      double(
        id: 'task123',
        task_id: 'task-123',
        description: 'Test task',
        status: 'pending',
        task_type: 'execution',
        priority: 'normal',
        assigned_role_id: nil,
        assigned_role: nil,
        assigned_agent_id: nil,
        tokens_used: 0,
        cost_usd: 0.0,
        retry_count: 0,
        started_at: nil,
        completed_at: nil,
        duration_ms: nil
      )
    end

    before do
      allow(team_service).to receive(:get_execution).and_return(execution)
    end

    context 'with valid authentication' do
      it 'creates a new task' do
        allow(team_service).to receive(:create_task).and_return(created_task)

        post '/api/v1/ai/teams/executions/e123/tasks', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(team_service).to have_received(:create_task)
      end
    end
  end

  describe 'GET /api/v1/ai/teams/templates' do
    context 'with valid authentication' do
      it 'returns list of templates' do
        templates = double(total_count: 3, map: [])
        allow(team_service).to receive(:list_templates).and_return(templates)

        get '/api/v1/ai/teams/templates', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['templates']).to be_an(Array)
        expect(data['total_count']).to eq(3)
      end
    end
  end

  describe 'GET /api/v1/ai/teams/:team_id/analytics' do
    let(:team) { double(id: 't123') }

    before do
      allow(team_service).to receive(:get_team).and_return(team)
    end

    context 'with valid authentication' do
      it 'returns team analytics' do
        analytics = { total_executions: 10, success_rate: 0.9 }
        allow(team_service).to receive(:get_team_analytics).and_return(analytics)

        get '/api/v1/ai/teams/t123/analytics', headers: headers, as: :json

        expect_success_response
        expect(team_service).to have_received(:get_team_analytics).with('t123', period_days: 30)
      end
    end
  end
end
