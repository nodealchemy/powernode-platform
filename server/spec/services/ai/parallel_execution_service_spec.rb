# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ParallelExecutionService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, default_agent: agent) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:repository_path) { Rails.root.join('tmp', "test_repo_#{SecureRandom.hex(4)}").to_s }

  subject(:service) { described_class.new(account: account, user: user) }

  before do
    allow(File).to receive(:directory?).and_call_original
    allow(File).to receive(:directory?).with(repository_path).and_return(true)
    # Stub WorkerJobService dispatch methods (jobs run in worker, not server)
    allow(WorkerJobService).to receive(:enqueue_ai_worktree_provisioning).and_return({ 'status' => 'queued' })
    allow(WorkerJobService).to receive(:enqueue_ai_worktree_cleanup).and_return({ 'status' => 'queued' })
    allow(WorkerJobService).to receive(:enqueue_ai_merge_execution).and_return({ 'status' => 'queued' })
    # Stub Open3 for create_worktree_records base SHA resolution
    allow(Open3).to receive(:capture3)
      .with('git', 'rev-parse', 'main', chdir: repository_path)
      .and_return([SecureRandom.hex(20), '', instance_double(Process::Status, success?: true)])
  end

  describe '#start_session' do
    let(:tasks) do
      [
        { task: ralph_loop, branch_suffix: 'task-1', agent_id: agent.id, metadata: {} },
        { task: ralph_loop, branch_suffix: 'task-2', agent_id: agent.id, metadata: {} }
      ]
    end

    context 'with valid params' do
      it 'creates a session' do
        result = service.start_session(source: ralph_loop, tasks: tasks, repository_path: repository_path)

        expect(result[:success]).to be true
        expect(result[:session]).to be_present
        expect(result[:message]).to include('2 worktrees')
      end

      it 'creates worktree records' do
        expect {
          service.start_session(source: ralph_loop, tasks: tasks, repository_path: repository_path)
        }.to change(Ai::Worktree, :count).by(2)
      end

      it 'dispatches worktree provisioning to worker' do
        allow(WorkerJobService).to receive(:enqueue_ai_worktree_provisioning).and_return({ 'status' => 'queued' })

        service.start_session(source: ralph_loop, tasks: tasks, repository_path: repository_path)

        expect(WorkerJobService).to have_received(:enqueue_ai_worktree_provisioning)
      end

      it 'sets the session as pending' do
        result = service.start_session(source: ralph_loop, tasks: tasks, repository_path: repository_path)
        session = Ai::WorktreeSession.find(result[:session][:id])

        expect(session.status).to eq('pending')
        expect(session.total_worktrees).to eq(2)
      end

      it 'applies options' do
        result = service.start_session(
          source: ralph_loop,
          tasks: tasks,
          repository_path: repository_path,
          options: { merge_strategy: 'integration_branch', max_parallel: 8 }
        )
        session = Ai::WorktreeSession.find(result[:session][:id])

        expect(session.merge_strategy).to eq('integration_branch')
        expect(session.max_parallel).to eq(8)
      end
    end

    context 'with blank tasks' do
      it 'returns an error' do
        result = service.start_session(source: ralph_loop, tasks: [], repository_path: repository_path)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No tasks provided')
      end
    end

    context 'with missing repository_path' do
      it 'returns an error' do
        result = service.start_session(source: ralph_loop, tasks: tasks, repository_path: '')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Repository path is required')
      end
    end

    context 'with non-existent directory' do
      before do
        allow(File).to receive(:directory?).with('/nonexistent/path').and_return(false)
      end

      it 'returns an error' do
        result = service.start_session(source: ralph_loop, tasks: tasks, repository_path: '/nonexistent/path')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Repository path does not exist')
      end
    end
  end

  describe '#cancel_session' do
    context 'when session is active' do
      let!(:session) { create(:ai_worktree_session, :active, account: account, initiated_by: user) }
      let!(:worktree1) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }
      let!(:worktree2) { create(:ai_worktree, :ready, worktree_session: session, account: account) }

      it 'cancels the session' do
        result = service.cancel_session(session_id: session.id, reason: 'User requested')

        expect(result[:success]).to be true
        expect(session.reload.status).to eq('cancelled')
      end

      it 'fails active worktrees' do
        service.cancel_session(session_id: session.id, reason: 'User requested')

        expect(worktree1.reload.status).to eq('failed')
        expect(worktree2.reload.status).to eq('failed')
      end

      it 'enqueues cleanup job when auto_cleanup is enabled' do
        service.cancel_session(session_id: session.id, reason: 'User requested')
        expect(WorkerJobService).to have_received(:enqueue_ai_worktree_cleanup).with(session.id)
      end
    end

    context 'when session is already terminal' do
      let!(:session) { create(:ai_worktree_session, :completed, account: account) }

      it 'returns an error' do
        result = service.cancel_session(session_id: session.id)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Session is already terminal')
      end
    end

    context 'when session does not exist' do
      it 'returns an error' do
        result = service.cancel_session(session_id: SecureRandom.uuid)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Session not found')
      end
    end
  end

  describe '#worktree_completed' do
    let!(:session) { create(:ai_worktree_session, :active, account: account, total_worktrees: 2) }
    let!(:worktree1) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }
    let!(:worktree2) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }
    let(:completion_result) { { head_sha: SecureRandom.hex(20), files_changed: 5, lines_added: 50, lines_removed: 10 } }

    context 'when not all worktrees are done' do
      it 'marks the worktree as completed' do
        result = service.worktree_completed(worktree_id: worktree1.id, result: completion_result)

        expect(result[:success]).to be true
        expect(worktree1.reload.status).to eq('completed')
      end

      it 'does not start merging' do
        service.worktree_completed(worktree_id: worktree1.id, result: completion_result)

        expect(session.reload.status).to eq('active')
      end

      it 'does not enqueue MergeExecutionJob' do
        service.worktree_completed(worktree_id: worktree1.id, result: completion_result)
        expect(WorkerJobService).not_to have_received(:enqueue_ai_merge_execution)
      end
    end

    context 'when all worktrees are done' do
      before do
        # Complete the first worktree outside the service
        worktree2.update!(status: 'completed', completed_at: Time.current, ready_at: 1.hour.ago)
        # Update session count to reflect worktree2 already completed
        session.update_columns(completed_worktrees: 1)
      end

      it 'begins the merge phase' do
        service.worktree_completed(worktree_id: worktree1.id, result: completion_result)

        expect(session.reload.status).to eq('merging')
      end

      it 'enqueues MergeExecutionJob' do
        service.worktree_completed(worktree_id: worktree1.id, result: completion_result)
        expect(WorkerJobService).to have_received(:enqueue_ai_merge_execution).with(session.id)
      end
    end
  end

  describe '#worktree_failed' do
    let!(:session) { create(:ai_worktree_session, :active, account: account, total_worktrees: 3) }
    let!(:worktree1) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }
    let!(:worktree2) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }
    let!(:worktree3) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }

    context 'with continue failure policy' do
      it 'marks the worktree as failed' do
        result = service.worktree_failed(worktree_id: worktree1.id, error: 'Task failed')

        expect(result[:success]).to be true
        expect(worktree1.reload.status).to eq('failed')
      end

      it 'does not cancel remaining worktrees' do
        service.worktree_failed(worktree_id: worktree1.id, error: 'Task failed')

        expect(worktree2.reload.status).to eq('in_use')
        expect(worktree3.reload.status).to eq('in_use')
      end
    end

    context 'with abort failure policy' do
      let!(:session) do
        create(:ai_worktree_session, :active, :abort_policy, account: account, total_worktrees: 3)
      end
      let!(:worktree1) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }
      let!(:worktree2) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }
      let!(:worktree3) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }

      it 'cancels remaining worktrees' do
        service.worktree_failed(worktree_id: worktree1.id, error: 'Critical failure')

        expect(worktree2.reload.status).to eq('failed')
        expect(worktree3.reload.status).to eq('failed')
      end

      it 'fails the session' do
        service.worktree_failed(worktree_id: worktree1.id, error: 'Critical failure')

        expect(session.reload.status).to eq('failed')
        expect(session.error_message).to include('Aborted')
      end
    end

    context 'when all worktrees completed after failure with continue policy and some completed' do
      let!(:session) { create(:ai_worktree_session, :active, account: account, total_worktrees: 2) }
      let!(:worktree1) { create(:ai_worktree, :in_use, worktree_session: session, account: account) }
      let!(:worktree2) { create(:ai_worktree, worktree_session: session, account: account, status: 'completed', completed_at: Time.current, ready_at: 1.hour.ago) }

      before do
        session.update_columns(completed_worktrees: 1)
      end

      it 'begins merge for completed worktrees' do
        service.worktree_failed(worktree_id: worktree1.id, error: 'Task failed')

        # After the failure callback updates counts, completed + failed >= total
        # The session should start merging since there is at least one completed worktree
        expect(session.reload.status).to eq('merging')
      end
    end
  end

  describe '#session_status' do
    let!(:session) { create(:ai_worktree_session, :active, account: account) }
    let!(:worktree) { create(:ai_worktree, :ready, worktree_session: session, account: account) }

    it 'returns full session status' do
      result = service.session_status(session_id: session.id)

      expect(result[:session]).to be_present
      expect(result[:worktrees]).to be_an(Array)
      expect(result[:merge_operations]).to be_an(Array)
    end

    context 'when session does not exist' do
      it 'returns an error' do
        result = service.session_status(session_id: SecureRandom.uuid)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Session not found')
      end
    end
  end
end
