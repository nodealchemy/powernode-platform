# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::WorktreeProvisioningJob, type: :job do
  let(:account) { create(:account) }
  let(:repository_path) { '/tmp/test_repo' }

  describe 'job configuration' do
    it 'is queued in the ai_execution queue' do
      expect(described_class.new.queue_name).to eq('ai_execution')
    end
  end

  describe '#perform' do
    context 'with a valid pending session' do
      let!(:session) do
        create(:ai_worktree_session,
               account: account,
               repository_path: repository_path,
               total_worktrees: 2)
      end
      let!(:worktree1) do
        create(:ai_worktree,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/abcd1234/task-1',
               worktree_path: '/tmp/test_repo/tmp/worktrees/abcd1234/task-1')
      end
      let!(:worktree2) do
        create(:ai_worktree,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/abcd1234/task-2',
               worktree_path: '/tmp/test_repo/tmp/worktrees/abcd1234/task-2')
      end

      let(:manager) { instance_double(Ai::Git::WorktreeManager) }
      let(:base_sha) { SecureRandom.hex(20) }

      before do
        allow(Ai::Git::WorktreeManager).to receive(:new)
          .with(repository_path: repository_path)
          .and_return(manager)

        allow(manager).to receive(:create_worktree) do |args|
          suffix = args[:branch_suffix]
          {
            branch_name: "worktree/abcd1234/#{suffix}",
            worktree_path: "/tmp/worktrees/#{suffix}",
            base_commit_sha: base_sha,
            copied_config_files: ['.env']
          }
        end

        allow(manager).to receive(:health_check).and_return({ healthy: true, health_message: nil })
        allow(Ai::ConflictDetectionJob).to receive(:perform_later)
      end

      it 'transitions session from pending to provisioning then active' do
        described_class.new.perform(session.id)

        expect(session.reload.status).to eq('active')
      end

      it 'provisions each pending worktree' do
        described_class.new.perform(session.id)

        expect(manager).to have_received(:create_worktree).twice
      end

      it 'updates worktree records with provisioning results' do
        described_class.new.perform(session.id)

        worktree1.reload
        expect(worktree1.status).to eq('ready')
        expect(worktree1.base_commit_sha).to eq(base_sha)
        expect(worktree1.copied_config_files).to eq(['.env'])
      end
    end

    context 'when all worktree provisioning fails' do
      let!(:session) do
        create(:ai_worktree_session,
               account: account,
               repository_path: repository_path,
               total_worktrees: 2)
      end
      let!(:worktree1) do
        create(:ai_worktree,
               worktree_session: session,
               account: account)
      end
      let!(:worktree2) do
        create(:ai_worktree,
               worktree_session: session,
               account: account)
      end

      let(:manager) { instance_double(Ai::Git::WorktreeManager) }

      before do
        allow(Ai::Git::WorktreeManager).to receive(:new)
          .with(repository_path: repository_path)
          .and_return(manager)

        allow(manager).to receive(:create_worktree)
          .and_raise(Ai::Git::WorktreeManager::WorktreeError, 'Cannot create worktree')
      end

      it 'transitions session to failed' do
        described_class.new.perform(session.id)

        expect(session.reload.status).to eq('failed')
        expect(session.error_message).to include('All worktrees failed')
      end

      it 'marks all worktrees as failed' do
        described_class.new.perform(session.id)

        expect(worktree1.reload.status).to eq('failed')
        expect(worktree2.reload.status).to eq('failed')
      end
    end

    context 'when some worktree provisioning fails' do
      let!(:session) do
        create(:ai_worktree_session,
               account: account,
               repository_path: repository_path,
               total_worktrees: 2)
      end
      let!(:worktree1) do
        create(:ai_worktree,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/partial/task-1',
               worktree_path: '/tmp/test_repo/tmp/worktrees/partial/task-1')
      end
      let!(:worktree2) do
        create(:ai_worktree,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/partial/task-2',
               worktree_path: '/tmp/test_repo/tmp/worktrees/partial/task-2')
      end

      let(:manager) { instance_double(Ai::Git::WorktreeManager) }
      let(:base_sha) { SecureRandom.hex(20) }

      before do
        allow(Ai::Git::WorktreeManager).to receive(:new)
          .with(repository_path: repository_path)
          .and_return(manager)

        call_count = 0
        allow(manager).to receive(:create_worktree) do
          call_count += 1
          if call_count == 1
            { branch_name: 'worktree/partial/provisioned', worktree_path: '/tmp/provisioned', base_commit_sha: base_sha, copied_config_files: [] }
          else
            raise Ai::Git::WorktreeManager::WorktreeError, 'Failed'
          end
        end

        allow(manager).to receive(:health_check).and_return({ healthy: true, health_message: nil })
        allow(Ai::ConflictDetectionJob).to receive(:perform_later)
      end

      it 'activates the session (at least one succeeded)' do
        described_class.new.perform(session.id)

        expect(session.reload.status).to eq('active')
      end
    end

    context 'when session is already terminal' do
      let!(:session) do
        create(:ai_worktree_session, :completed, account: account, repository_path: repository_path)
      end

      it 'returns early without provisioning' do
        expect(Ai::Git::WorktreeManager).not_to receive(:new)

        described_class.new.perform(session.id)
      end

      it 'does not change session status' do
        described_class.new.perform(session.id)

        expect(session.reload.status).to eq('completed')
      end
    end
  end
end
