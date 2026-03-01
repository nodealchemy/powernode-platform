# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentTeamOrchestrator, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }

  # Helper to create team with members
  def create_team_with_members(team_type:, member_count: 3, with_lead: false)
    # Set appropriate coordination strategy based on team type
    coordination_strategy = case team_type
    when 'hierarchical'
                             'manager_led'
    when 'sequential'
                             'priority_based'
    when 'mesh'
                             'consensus'
    when 'parallel'
                             'round_robin'
    else
                             'manager_led'
    end

    team = create(:ai_agent_team,
                  team_type: team_type,
                  coordination_strategy: coordination_strategy,
                  account: account)

    # Create agents for the team
    agents = member_count.times.map do |i|
      create(:ai_agent, account: account, provider: provider, name: "Agent #{i}")
    end

    # Add members
    agents.each_with_index do |agent, idx|
      is_lead = with_lead && idx.zero?
      role = is_lead ? 'manager' : 'executor'

      create(:ai_agent_team_member,
             team: team,
             agent: agent,
             role: role,
             is_lead: is_lead,
             capabilities: [ 'processing', 'analysis' ])
    end

    team.reload
  end

  # Mock A2A task execution to avoid actual agent calls
  def mock_a2a_execution
    allow_any_instance_of(Ai::A2a::Service).to receive(:submit_task) do |_service, args|
      task = create(:ai_a2a_task,
        account: account,
        status: 'completed',
        output: { result: 'processed' }
      )
      task
    end

    allow_any_instance_of(Ai::A2aTask).to receive(:reload).and_return(nil)
  end

  describe '#initialize' do
    it 'initializes with team and user' do
      team = create(:ai_agent_team, account: account)
      orchestrator = described_class.new(team: team, user: user)

      expect(orchestrator.team).to eq(team)
      expect(orchestrator.user).to eq(user)
    end
  end

  describe '#execute' do
    context 'validation' do
      it 'raises error if team is not active' do
        team = create(:ai_agent_team, :inactive, account: account)
        orchestrator = described_class.new(team: team, user: user)

        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to raise_error(Ai::AgentTeamOrchestrator::TeamNotActiveError)
      end

      it 'raises error if team has no members' do
        team = create(:ai_agent_team, account: account)
        orchestrator = described_class.new(team: team, user: user)

        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to raise_error(Ai::AgentTeamOrchestrator::NoMembersError)
      end
    end

    context 'sequential execution' do
      let(:team) { create_team_with_members(team_type: 'sequential', member_count: 3) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      before { mock_a2a_execution }

      it 'executes members in priority order' do
        result = orchestrator.execute(input: { task: 'sequential task' })

        expect(result[:success]).to be true
        expect(result[:execution_type]).to eq('sequential')
        expect(result[:members_executed]).to eq(3)
      end
    end

    context 'parallel execution' do
      let(:team) { create_team_with_members(team_type: 'parallel', member_count: 3) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      before { mock_a2a_execution }

      it 'executes all members concurrently' do
        result = orchestrator.execute(input: { task: 'parallel task' })

        expect(result[:success]).to be true
        expect(result[:execution_type]).to eq('parallel')
        expect(result[:members_executed]).to eq(3)
        expect(result[:individual_results].size).to eq(3)
      end

      it 'aggregates results from all members' do
        result = orchestrator.execute(input: { task: 'test' })

        expect(result[:output][:aggregated]).to be true
        expect(result[:output][:count]).to eq(3)
      end
    end

    context 'hierarchical execution' do
      let(:team) { create_team_with_members(team_type: 'hierarchical', member_count: 4, with_lead: true) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      before { mock_a2a_execution }

      it 'requires a lead member' do
        team_without_lead = create_team_with_members(team_type: 'hierarchical', member_count: 3, with_lead: false)
        orchestrator = described_class.new(team: team_without_lead, user: user)

        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to raise_error(Ai::AgentTeamOrchestrator::NoMembersError, /requires a lead/)
      end

      it 'lead delegates to workers' do
        result = orchestrator.execute(input: { task: 'hierarchical task' })

        expect(result[:success]).to be true
        expect(result[:execution_type]).to eq('hierarchical')
        expect(result[:lead]).to be_present
        expect(result[:workers_executed]).to eq(3) # 4 members - 1 lead = 3 workers
      end

      it 'synthesizes worker results' do
        result = orchestrator.execute(input: { task: 'test' })

        expect(result[:output][:synthesized]).to be true
        expect(result[:output][:worker_outputs].size).to eq(3)
      end
    end

    context 'mesh execution' do
      let(:team) { create_team_with_members(team_type: 'mesh', member_count: 3) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      before { mock_a2a_execution }

      it 'uses collaboration pattern' do
        result = orchestrator.execute(input: { task: 'mesh task' })

        expect(result[:success]).to be true
        expect(result[:execution_type]).to eq('mesh')
        expect(result[:members_executed]).to eq(3)
        expect(result[:contributions]).to be_present
      end

      it 'aggregates all member contributions' do
        result = orchestrator.execute(input: { task: 'test' })

        expect(result[:output][:collaborative_result]).to be true
        expect(result[:output][:contributor_count]).to eq(3)
      end
    end

    context 'workflow run tracking' do
      let(:team) { create_team_with_members(team_type: 'sequential', member_count: 2) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      before { mock_a2a_execution }

      it 'creates workflow run for tracking' do
        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to change { Ai::WorkflowRun.count }.by(1)

        run = Ai::WorkflowRun.last
        expect(run.status).to eq('completed')
        expect(run.input_variables['team_id']).to eq(team.id)
      end

      it 'updates execution status' do
        orchestrator.execute(input: { task: 'test' })

        status = orchestrator.execution_status
        expect(status[:status]).to eq('completed')
        expect(status[:team_name]).to eq(team.name)
        expect(status[:started_at]).to be_present
        expect(status[:completed_at]).to be_present
      end
    end

    context 'error handling' do
      let(:team) { create_team_with_members(team_type: 'sequential', member_count: 2) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      it 'handles execution failures' do
        allow_any_instance_of(Ai::A2a::Service).to receive(:submit_task)
          .and_raise(StandardError, 'Execution failed')

        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to raise_error(StandardError, 'Execution failed')

        # Verify workflow run marked as failed
        run = Ai::WorkflowRun.last
        expect(run.status).to eq('failed')
        expect(run.error_details).to eq('Execution failed')
      end
    end

    context 'A2A service integration' do
      let(:team) { create_team_with_members(team_type: 'mesh', member_count: 2) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      before { mock_a2a_execution }

      it 'initializes A2A service' do
        orchestrator.execute(input: { task: 'test' })

        expect(orchestrator.a2a_service).to be_a(Ai::A2a::Service)
        expect(orchestrator.workflow_run).to be_persisted
      end

      it 'creates agent cards for team members' do
        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to change { Ai::AgentCard.count }.by_at_least(1)
      end
    end
  end

  describe '#execution_status' do
    let(:team) { create_team_with_members(team_type: 'sequential', member_count: 2) }
    let(:orchestrator) { described_class.new(team: team, user: user) }

    it 'returns not_started before execution' do
      status = orchestrator.execution_status
      expect(status[:status]).to eq('not_started')
    end

    it 'returns execution details after execution' do
      mock_a2a_execution

      orchestrator.execute(input: { task: 'test' })
      status = orchestrator.execution_status

      expect(status).to include(:status, :team_id, :team_name, :started_at, :completed_at)
      expect(status[:a2a_tasks]).to be_present
    end
  end
end
