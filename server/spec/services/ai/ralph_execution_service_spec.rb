# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Ralph::ExecutionService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  let(:ralph_loop) do
    create(:ai_ralph_loop,
      account: account,
      name: 'Test Loop',
      status: 'pending',
      max_iterations: 10)
  end

  subject(:service) { described_class.new(ralph_loop: ralph_loop, user: user) }

  describe '#initialize' do
    it 'initializes with ralph_loop and user' do
      expect(service.ralph_loop).to eq(ralph_loop)
      expect(service.user).to eq(user)
      expect(service.account).to eq(account)
    end

    it 'derives account from ralph_loop if not provided' do
      svc = described_class.new(ralph_loop: ralph_loop)
      expect(svc.account).to eq(account)
    end
  end

  describe '#start_loop' do
    context 'with valid pending loop and tasks' do
      before do
        create_list(:ai_ralph_task, 3, ralph_loop: ralph_loop)
        ralph_loop.update!(total_tasks: 3)
      end

      it 'starts the loop successfully' do
        result = service.start_loop

        expect(result[:success]).to be true
        expect(result[:message]).to eq('Loop started successfully')
        expect(ralph_loop.reload.status).to eq('running')
      end

      it 'returns loop summary' do
        result = service.start_loop
        expect(result[:loop]).to be_present
      end
    end

    context 'when loop is not pending' do
      before { ralph_loop.update!(status: 'running', started_at: Time.current) }

      it 'returns error' do
        result = service.start_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include('not in pending status')
      end
    end

    context 'when loop has no tasks' do
      it 'returns error' do
        result = service.start_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include('No tasks defined')
      end
    end
  end

  describe '#pause_loop' do
    context 'when loop is running' do
      before do
        ralph_loop.update!(status: 'running', started_at: Time.current)
      end

      it 'pauses the loop' do
        result = service.pause_loop

        expect(result[:success]).to be true
        expect(result[:message]).to eq('Loop paused successfully')
        expect(ralph_loop.reload.status).to eq('paused')
      end
    end

    context 'when loop is not running' do
      it 'returns error' do
        result = service.pause_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include('not running')
      end
    end
  end

  describe '#resume_loop' do
    context 'when loop is paused' do
      before do
        ralph_loop.update!(status: 'paused', started_at: 1.hour.ago)
      end

      it 'resumes the loop' do
        result = service.resume_loop

        expect(result[:success]).to be true
        expect(result[:message]).to eq('Loop resumed successfully')
        expect(ralph_loop.reload.status).to eq('running')
      end
    end

    context 'when loop is not paused' do
      it 'returns error' do
        result = service.resume_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include('not paused')
      end
    end
  end

  describe '#cancel_loop' do
    context 'when loop can be cancelled' do
      before do
        ralph_loop.update!(status: 'running', started_at: Time.current)
      end

      it 'cancels the loop' do
        result = service.cancel_loop(reason: 'User requested')

        expect(result[:success]).to be true
        expect(result[:message]).to eq('Loop cancelled')
        expect(ralph_loop.reload.status).to eq('cancelled')
      end
    end

    context 'when loop is already completed' do
      before do
        ralph_loop.update!(status: 'completed', started_at: 2.hours.ago, completed_at: Time.current)
      end

      it 'returns error' do
        result = service.cancel_loop

        expect(result[:success]).to be false
        expect(result[:error]).to include('cannot be cancelled')
      end
    end
  end

  describe '#select_next_task' do
    context 'with pending tasks' do
      let!(:task1) { create(:ai_ralph_task, ralph_loop: ralph_loop, priority: 10, status: 'pending') }
      let!(:task2) { create(:ai_ralph_task, ralph_loop: ralph_loop, priority: 5, status: 'pending') }

      it 'selects highest priority pending task' do
        allow_any_instance_of(Ai::RalphTask).to receive(:dependencies_satisfied?).and_return(true)

        next_task = service.select_next_task
        expect(next_task).to be_present
      end
    end

    context 'with in-progress task' do
      let!(:in_progress_task) { create(:ai_ralph_task, :in_progress, ralph_loop: ralph_loop) }
      let!(:pending_task) { create(:ai_ralph_task, ralph_loop: ralph_loop, priority: 10) }

      it 'returns in-progress task first' do
        next_task = service.select_next_task
        expect(next_task).to eq(in_progress_task)
      end
    end

    context 'with blocked tasks only' do
      let!(:blocked_task) { create(:ai_ralph_task, :blocked, ralph_loop: ralph_loop) }

      it 'returns nil when all tasks are blocked' do
        allow_any_instance_of(Ai::RalphTask).to receive(:dependencies_satisfied?).and_return(false)

        next_task = service.select_next_task
        expect(next_task).to be_nil
      end
    end
  end

  describe '#run_iteration' do
    context 'when loop is not running' do
      it 'returns error' do
        result = service.run_iteration

        expect(result[:success]).to be false
        expect(result[:error]).to include('not running')
      end
    end

    context 'when all tasks are completed' do
      before do
        ralph_loop.update!(status: 'running', started_at: Time.current)
        create(:ai_ralph_task, :passed, ralph_loop: ralph_loop)
        ralph_loop.update!(total_tasks: 1, completed_tasks: 1)
      end

      it 'completes the loop' do
        allow(ralph_loop).to receive(:all_tasks_completed?).and_return(true)

        result = service.run_iteration

        expect(result[:success]).to be true
        expect(result[:completed]).to be true
      end
    end

    context 'when max iterations reached' do
      before do
        ralph_loop.update!(
          status: 'running',
          started_at: Time.current,
          current_iteration: 10,
          max_iterations: 10
        )
        create(:ai_ralph_task, ralph_loop: ralph_loop)
        ralph_loop.update!(total_tasks: 1)
      end

      it 'fails the loop' do
        allow(ralph_loop).to receive(:all_tasks_completed?).and_return(false)
        allow(ralph_loop).to receive(:max_iterations_reached?).and_return(true)

        result = service.run_iteration

        expect(result[:success]).to be false
        expect(result[:error]).to include('Maximum iterations')
      end
    end
  end

  describe '#parse_prd' do
    context 'with valid PRD data' do
      let(:prd_data) do
        {
          'tasks' => [
            { 'key' => 'setup', 'description' => 'Set up the project', 'priority' => 1 },
            { 'key' => 'implement', 'description' => 'Implement the feature', 'priority' => 2, 'dependencies' => ['setup'] },
            { 'key' => 'test', 'description' => 'Write tests', 'priority' => 3, 'dependencies' => ['implement'] }
          ]
        }
      end

      it 'creates tasks from PRD' do
        result = service.parse_prd(prd_data)

        expect(result[:success]).to be true
        expect(result[:tasks_created]).to eq(3)
        expect(ralph_loop.reload.total_tasks).to eq(3)
      end

      it 'creates tasks with correct keys' do
        result = service.parse_prd(prd_data)

        tasks = ralph_loop.ralph_tasks.order(:position)
        expect(tasks.first.task_key).to eq('setup')
        expect(tasks.second.task_key).to eq('implement')
        expect(tasks.third.task_key).to eq('test')
      end

      it 'preserves dependencies' do
        service.parse_prd(prd_data)

        implement_task = ralph_loop.ralph_tasks.find_by(task_key: 'implement')
        expect(implement_task.dependencies).to include('setup')
      end
    end

    context 'with array format PRD' do
      let(:prd_data) do
        [
          { 'key' => 'task_1', 'description' => 'First task' },
          { 'key' => 'task_2', 'description' => 'Second task' }
        ]
      end

      it 'handles array format' do
        result = service.parse_prd(prd_data)

        expect(result[:success]).to be true
        expect(result[:tasks_created]).to eq(2)
      end
    end

    context 'with blank PRD data' do
      it 'returns error' do
        result = service.parse_prd(nil)

        expect(result[:success]).to be false
        expect(result[:error]).to include('PRD data is required')
      end
    end

    context 'when reparsing' do
      before do
        create_list(:ai_ralph_task, 2, ralph_loop: ralph_loop)
      end

      it 'clears existing tasks and creates new ones' do
        prd_data = { 'tasks' => [{ 'key' => 'new_task', 'description' => 'New task' }] }

        result = service.parse_prd(prd_data)

        expect(result[:success]).to be true
        expect(result[:tasks_created]).to eq(1)
        expect(ralph_loop.ralph_tasks.count).to eq(1)
      end
    end
  end

  describe '#status' do
    before do
      create_list(:ai_ralph_task, 2, ralph_loop: ralph_loop)
    end

    it 'returns current loop status' do
      allow_any_instance_of(Ai::RalphTask).to receive(:dependencies_satisfied?).and_return(true)

      result = service.status

      expect(result).to include(:loop, :tasks, :recent_iterations)
      expect(result[:tasks]).to be_an(Array)
    end
  end

  describe '#learnings' do
    context 'with no learnings' do
      it 'returns empty learnings' do
        result = service.learnings

        expect(result[:total_count]).to eq(0)
        expect(result[:learnings]).to be_empty
      end
    end

    context 'with learnings' do
      let(:ralph_loop_with_learnings) do
        create(:ai_ralph_loop, :with_learnings, account: account)
      end

      it 'returns accumulated learnings' do
        svc = described_class.new(ralph_loop: ralph_loop_with_learnings)
        result = svc.learnings

        expect(result[:total_count]).to eq(2)
        expect(result[:learnings]).to be_an(Array)
        expect(result[:by_iteration]).to be_a(Hash)
      end
    end
  end

  describe '#update_progress' do
    it 'updates progress text' do
      result = service.update_progress('Processing task 3 of 5')

      expect(result[:success]).to be true
      expect(ralph_loop.reload.progress_text).to eq('Processing task 3 of 5')
    end
  end
end
