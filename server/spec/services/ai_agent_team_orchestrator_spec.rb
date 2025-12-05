# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentTeamOrchestrator, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }

  # Helper to create team with members
  def create_team_with_members(team_type:, member_count: 3, with_lead: false)
    # Set appropriate coordination strategy based on team type
    coordination_strategy = case team_type
                           when 'hierarchical'
                             'manager_worker'
                           when 'sequential'
                             'manager_worker'
                           when 'mesh'
                             'peer_to_peer'
                           when 'parallel'
                             'hybrid'
                           else
                             'manager_worker'
                           end

    team = create(:ai_agent_team,
                  team_type: team_type,
                  coordination_strategy: coordination_strategy,
                  account: account)

    # Create agents for the team
    agents = member_count.times.map do |i|
      create(:ai_agent, account: account, ai_provider: provider, name: "Agent #{i}")
    end

    # Add members
    agents.each_with_index do |agent, idx|
      is_lead = with_lead && idx.zero?
      role = is_lead ? 'manager' : 'executor'

      create(:ai_agent_team_member,
             ai_agent_team: team,
             ai_agent: agent,
             role: role,
             is_lead: is_lead,
             capabilities: ['processing', 'analysis'])
    end

    team.reload
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
        }.to raise_error(AiAgentTeamOrchestrator::TeamNotActiveError)
      end

      it 'raises error if team has no members' do
        team = create(:ai_agent_team, account: account)
        orchestrator = described_class.new(team: team, user: user)

        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to raise_error(AiAgentTeamOrchestrator::NoMembersError)
      end
    end

    context 'sequential execution' do
      let(:team) { create_team_with_members(team_type: 'sequential', member_count: 3) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      it 'executes members in priority order' do
        # Mock member execution to avoid actual agent calls
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'processed' }
        )

        result = orchestrator.execute(input: { task: 'sequential task' })

        expect(result[:success]).to be true
        expect(result[:execution_type]).to eq('sequential')
        expect(result[:members_executed]).to eq(3)
      end

      it 'passes output from one member to the next' do
        execution_order = []

        allow_any_instance_of(AiAgentTeamMember).to receive(:execute) do |member, args|
          execution_order << member.priority_order
          { success: true, output: "output_#{member.priority_order}" }
        end

        result = orchestrator.execute(input: { task: 'test' })

        expect(execution_order).to eq([0, 1, 2])
        expect(result[:output]).to eq('output_2') # Last member's output
      end
    end

    context 'parallel execution' do
      let(:team) { create_team_with_members(team_type: 'parallel', member_count: 3) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      it 'executes all members concurrently' do
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'parallel result' }
        )

        result = orchestrator.execute(input: { task: 'parallel task' })

        expect(result[:success]).to be true
        expect(result[:execution_type]).to eq('parallel')
        expect(result[:members_executed]).to eq(3)
        expect(result[:individual_results].size).to eq(3)
      end

      it 'aggregates results from all members' do
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'result' }
        )

        result = orchestrator.execute(input: { task: 'test' })

        expect(result[:output][:aggregated]).to be true
        expect(result[:output][:count]).to eq(3)
      end
    end

    context 'hierarchical execution' do
      let(:team) { create_team_with_members(team_type: 'hierarchical', member_count: 4, with_lead: true) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      it 'requires a lead member' do
        team_without_lead = create_team_with_members(team_type: 'hierarchical', member_count: 3, with_lead: false)
        orchestrator = described_class.new(team: team_without_lead, user: user)

        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to raise_error(AiAgentTeamOrchestrator::NoMembersError, /requires a lead/)
      end

      it 'lead delegates to workers' do
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'worker output' }
        )

        result = orchestrator.execute(input: { task: 'hierarchical task' })

        expect(result[:success]).to be true
        expect(result[:execution_type]).to eq('hierarchical')
        expect(result[:lead]).to be_present
        expect(result[:workers_executed]).to eq(3) # 4 members - 1 lead = 3 workers
      end

      it 'synthesizes worker results' do
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'output' }
        )

        result = orchestrator.execute(input: { task: 'test' })

        expect(result[:output][:synthesized]).to be true
        expect(result[:output][:worker_outputs].size).to eq(3)
      end
    end

    context 'mesh execution' do
      let(:team) { create_team_with_members(team_type: 'mesh', member_count: 3) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      it 'uses blackboard pattern for collaboration' do
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'contribution' }
        )

        result = orchestrator.execute(input: { task: 'mesh task' })

        expect(result[:success]).to be true
        expect(result[:execution_type]).to eq('mesh')
        expect(result[:members_executed]).to eq(3)
        expect(result[:contributions]).to be_present
      end

      it 'aggregates all member contributions' do
        contribution_count = 0

        allow_any_instance_of(AiAgentTeamMember).to receive(:execute) do
          contribution_count += 1
          { success: true, output: "contribution_#{contribution_count}" }
        end

        result = orchestrator.execute(input: { task: 'test' })

        expect(result[:output][:collaborative_result]).to be true
        expect(result[:output][:contributor_count]).to eq(3)
      end
    end

    context 'workflow run tracking' do
      let(:team) { create_team_with_members(team_type: 'sequential', member_count: 2) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      it 'creates workflow run for tracking' do
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'result' }
        )

        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to change { AiWorkflowRun.count }.by(1)

        run = AiWorkflowRun.last
        expect(run.status).to eq('completed')
        expect(run.input_variables['team_id']).to eq(team.id)
      end

      it 'updates execution status' do
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'result' }
        )

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

      it 'handles member execution failures' do
        # First member succeeds, second member fails
        call_count = 0
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute) do
          call_count += 1
          if call_count == 1
            { success: true, output: 'first output' }
          else
            raise StandardError, 'Execution failed'
          end
        end

        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to raise_error(StandardError, 'Execution failed')

        # Verify workflow run marked as failed
        run = AiWorkflowRun.last
        expect(run.status).to eq('failed')
        expect(run.error_details).to eq('Execution failed')
      end
    end

    context 'communication hub integration' do
      let(:team) { create_team_with_members(team_type: 'mesh', member_count: 2) }
      let(:orchestrator) { described_class.new(team: team, user: user) }

      it 'initializes communication hub' do
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'result' }
        )

        orchestrator.execute(input: { task: 'test' })

        expect(orchestrator.communication_hub).to be_a(Mcp::MultiAgentCommunicationHub)
        expect(orchestrator.workflow_run).to be_persisted
      end

      it 'creates team context pool' do
        allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
          { success: true, output: 'result' }
        )

        expect {
          orchestrator.execute(input: { task: 'test' })
        }.to change { AiSharedContextPool.count }.by_at_least(1)

        # Find the team context pool (shared_memory type, not blackboard)
        pool = AiSharedContextPool.where(pool_type: 'shared_memory').last
        expect(pool.scope).to eq('agent_group')
        expect(pool.context_data['team_id']).to eq(team.id)
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
      allow_any_instance_of(AiAgentTeamMember).to receive(:execute).and_return(
        { success: true, output: 'result' }
      )

      orchestrator.execute(input: { task: 'test' })
      status = orchestrator.execution_status

      expect(status).to include(:status, :team_id, :team_name, :started_at, :completed_at)
      expect(status[:communication_stats]).to be_present
    end
  end
end
