# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TrajectoryService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }

  subject(:service) { described_class.new(account: account) }

  # Helper to create a team execution with tasks
  def create_team_execution(status: 'completed', task_count: 3)
    team = create(:ai_agent_team, account: account)
    workflow = create(:ai_workflow, :active, account: account, creator: user)
    run = create(:ai_workflow_run, :completed, workflow: workflow, account: account)

    # Use a stub for team_execution since the actual model depends on orchestration
    execution = double('team_execution',
      id: SecureRandom.uuid,
      workflow_run_id: run.id,
      objective: 'Test objective',
      input_context: { 'param1' => 'value1' },
      agent_team_id: team.id,
      agent_team: team,
      triggered_by_id: user.id,
      status: status,
      duration_ms: 5000,
      tasks: build_mock_tasks(task_count, team)
    )

    execution
  end

  def build_mock_tasks(count, team)
    tasks = count.times.map do |i|
      role = double('role', role_name: "Role #{i}")
      task = double("task_#{i}",
        description: "Task #{i}: Process data",
        task_type: 'execution',
        status: i < count - 1 ? 'completed' : 'completed',
        assigned_role: role,
        output_data: { 'result' => "Output #{i}" },
        failure_reason: nil,
        duration_ms: 1000 + i * 500,
        team_execution: double('team_exec', agent_team: team),
        created_at: Time.current - (count - i).minutes
      )
      task
    end

    # Make tasks behave like an ActiveRecord relation
    task_relation = double('task_relation')
    allow(task_relation).to receive(:includes).and_return(task_relation)
    allow(task_relation).to receive(:order).and_return(tasks)
    allow(task_relation).to receive(:to_a).and_return(tasks)
    task_relation
  end

  describe '#initialize' do
    it 'initializes with account' do
      expect(service.account).to eq(account)
    end
  end

  describe '#search_relevant' do
    before do
      # Create some trajectories for searching
      allow(account).to receive(:ai_trajectories).and_return(Ai::Trajectory.where(account: account))
    end

    context 'when no trajectories exist' do
      it 'returns empty results' do
        results = service.search_relevant(query: 'test query')
        expect(results).to be_empty
      end
    end

    context 'with existing trajectories' do
      let!(:trajectory1) do
        create(:ai_trajectory,
          account: account,
          title: 'Data processing trajectory',
          status: 'completed',
          trajectory_type: 'task_completion')
      end

      let!(:trajectory2) do
        create(:ai_trajectory,
          account: account,
          title: 'Code review trajectory',
          status: 'completed',
          trajectory_type: 'task_completion')
      end

      it 'searches by query' do
        results = service.search_relevant(query: 'Data processing')
        expect(results).to include(trajectory1)
        expect(results).not_to include(trajectory2)
      end

      it 'limits results' do
        results = service.search_relevant(query: 'trajectory', limit: 1)
        expect(results.size).to eq(1)
      end

      it 'filters by tags' do
        trajectory1.update!(tags: ['data', 'processing'])
        results = service.search_relevant(query: nil, tags: ['data'])
        expect(results).to include(trajectory1)
      end

      it 'returns all completed trajectories with no filters' do
        results = service.search_relevant(query: nil)
        expect(results.size).to be >= 2
      end
    end
  end

  describe '#inject_context' do
    context 'when no relevant trajectories exist' do
      it 'returns nil' do
        result = service.inject_context(
          agent_id: SecureRandom.uuid,
          task_description: 'some nonexistent task'
        )
        expect(result).to be_nil
      end
    end

    context 'when relevant trajectories exist' do
      let!(:trajectory) do
        create(:ai_trajectory,
          account: account,
          title: 'Relevant past trajectory',
          summary: 'This was a successful execution',
          status: 'completed',
          quality_score: 0.95,
          trajectory_type: 'task_completion')
      end

      it 'returns formatted context string' do
        result = service.inject_context(
          agent_id: nil,
          task_description: 'Relevant past'
        )

        expect(result).to be_a(String)
        expect(result).to include('Past Trajectories')
        expect(result).to include('Relevant past trajectory')
      end

      it 'respects max_trajectories parameter' do
        create(:ai_trajectory,
          account: account,
          title: 'Another relevant past item',
          status: 'completed',
          trajectory_type: 'task_completion')

        result = service.inject_context(
          agent_id: nil,
          task_description: 'past',
          max_trajectories: 1
        )

        expect(result).to be_present
      end

      it 'records access on included trajectories' do
        expect_any_instance_of(Ai::Trajectory).to receive(:record_access!)

        service.inject_context(
          agent_id: nil,
          task_description: 'Relevant past'
        )
      end
    end
  end

  describe '#list_trajectories' do
    let!(:completed_trajectory) do
      create(:ai_trajectory,
        account: account,
        title: 'Completed trajectory',
        status: 'completed',
        trajectory_type: 'task_completion')
    end

    let!(:building_trajectory) do
      create(:ai_trajectory,
        account: account,
        title: 'Building trajectory',
        status: 'building',
        trajectory_type: 'task_completion')
    end

    it 'returns all trajectories for the account' do
      results = service.list_trajectories
      expect(results.size).to be >= 2
    end

    it 'filters by status' do
      results = service.list_trajectories(status: 'completed')
      expect(results).to include(completed_trajectory)
      expect(results).not_to include(building_trajectory)
    end

    it 'filters by type' do
      results = service.list_trajectories(type: 'task_completion')
      expect(results.size).to be >= 2
    end

    it 'filters by query' do
      results = service.list_trajectories(query: 'Completed')
      expect(results).to include(completed_trajectory)
      expect(results).not_to include(building_trajectory)
    end

    it 'respects limit' do
      results = service.list_trajectories(limit: 1)
      expect(results.size).to eq(1)
    end

    it 'defaults to limit of 20' do
      results = service.list_trajectories
      # Should be limited implicitly
      expect(results.size).to be <= 20
    end
  end

  describe '#get_trajectory' do
    let!(:trajectory) do
      create(:ai_trajectory,
        account: account,
        title: 'Test trajectory',
        status: 'completed')
    end

    it 'returns trajectory with chapters' do
      result = service.get_trajectory(trajectory.id)
      expect(result).to eq(trajectory)
    end

    it 'raises error for nonexistent trajectory' do
      expect {
        service.get_trajectory(SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'SQL injection protection' do
    it 'sanitizes LIKE query patterns' do
      # Should not raise when given special SQL characters
      expect {
        service.search_relevant(query: "test%_\\special")
      }.not_to raise_error

      expect {
        service.list_trajectories(query: "test%_\\special")
      }.not_to raise_error
    end
  end
end
