# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::MergeExecutionJob, type: :job do
  let(:account) { create(:account) }
  let(:repository_path) { '/tmp/test_repo' }

  describe 'job configuration' do
    it 'is queued in the ai_execution queue' do
      expect(described_class.new.queue_name).to eq('ai_execution')
    end
  end

  describe '#perform' do
    context 'with a merging session and successful merge' do
      let!(:session) do
        create(:ai_worktree_session, :merging,
               account: account,
               repository_path: repository_path,
               auto_cleanup: true,
               total_worktrees: 1)
      end

      let(:merge_service) { instance_double(Ai::Git::MergeService) }

      before do
        allow(Ai::Git::MergeService).to receive(:new)
          .with(session: session)
          .and_return(merge_service)

        allow(merge_service).to receive(:execute)
          .and_return({ success: true, results: [{ status: 'completed' }] })
      end

      it 'completes the session' do
        described_class.new.perform(session.id)

        expect(session.reload.status).to eq('completed')
      end

      it 'enqueues cleanup job when auto_cleanup is enabled' do
        expect {
          described_class.new.perform(session.id)
        }.to have_enqueued_job(Ai::WorktreeCleanupJob).with(session.id)
      end
    end

    context 'when merge fails' do
      let!(:session) do
        create(:ai_worktree_session, :merging,
               account: account,
               repository_path: repository_path,
               total_worktrees: 1)
      end

      let(:merge_service) { instance_double(Ai::Git::MergeService) }

      before do
        allow(Ai::Git::MergeService).to receive(:new)
          .with(session: session)
          .and_return(merge_service)

        allow(merge_service).to receive(:execute)
          .and_return({ success: false, error: 'Merge conflict', results: [{ status: 'conflict' }] })
      end

      it 'fails the session' do
        described_class.new.perform(session.id)

        session.reload
        expect(session.status).to eq('failed')
        expect(session.error_message).to eq('Merge conflict')
        expect(session.error_code).to eq('MERGE_FAILED')
      end

      it 'does not enqueue cleanup' do
        expect {
          described_class.new.perform(session.id)
        }.not_to have_enqueued_job(Ai::WorktreeCleanupJob)
      end
    end

    context 'with auto_cleanup disabled' do
      let!(:session) do
        create(:ai_worktree_session, :merging,
               account: account,
               repository_path: repository_path,
               auto_cleanup: false,
               total_worktrees: 1)
      end

      let(:merge_service) { instance_double(Ai::Git::MergeService) }

      before do
        allow(Ai::Git::MergeService).to receive(:new)
          .with(session: session)
          .and_return(merge_service)

        allow(merge_service).to receive(:execute)
          .and_return({ success: true, results: [] })
      end

      it 'does not enqueue cleanup job' do
        expect {
          described_class.new.perform(session.id)
        }.not_to have_enqueued_job(Ai::WorktreeCleanupJob)
      end
    end

    context 'with cleanup_delay configured' do
      let!(:session) do
        create(:ai_worktree_session, :merging,
               account: account,
               repository_path: repository_path,
               auto_cleanup: true,
               configuration: { 'cleanup_delay_seconds' => 300 },
               total_worktrees: 1)
      end

      let(:merge_service) { instance_double(Ai::Git::MergeService) }

      before do
        allow(Ai::Git::MergeService).to receive(:new)
          .with(session: session)
          .and_return(merge_service)

        allow(merge_service).to receive(:execute)
          .and_return({ success: true, results: [] })
      end

      it 'enqueues cleanup with delay' do
        expect {
          described_class.new.perform(session.id)
        }.to have_enqueued_job(Ai::WorktreeCleanupJob)
          .with(session.id)
          .at(a_value_within(10.seconds).of(300.seconds.from_now))
      end
    end

    context 'when session is not in merging state' do
      let!(:session) do
        create(:ai_worktree_session, :active,
               account: account,
               repository_path: repository_path)
      end

      it 'returns early without executing merge' do
        expect(Ai::Git::MergeService).not_to receive(:new)

        described_class.new.perform(session.id)
      end

      it 'does not change session status' do
        described_class.new.perform(session.id)

        expect(session.reload.status).to eq('active')
      end
    end

    context 'when an unexpected error occurs' do
      let!(:session) do
        create(:ai_worktree_session, :merging,
               account: account,
               repository_path: repository_path,
               total_worktrees: 1)
      end

      before do
        allow(Ai::Git::MergeService).to receive(:new).and_raise(StandardError, 'Unexpected failure')
      end

      it 'fails the session with the error message' do
        described_class.new.perform(session.id)

        session.reload
        expect(session.status).to eq('failed')
        expect(session.error_message).to eq('Unexpected failure')
        expect(session.error_code).to eq('MERGE_JOB_FAILED')
      end
    end
  end
end
