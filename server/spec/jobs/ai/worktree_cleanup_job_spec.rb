# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::WorktreeCleanupJob, type: :job do
  let(:account) { create(:account) }
  let(:repository_path) { '/tmp/test_repo' }

  describe 'job configuration' do
    it 'is queued in the ai_execution queue' do
      expect(described_class.new.queue_name).to eq('ai_execution')
    end

    it 'discards on StandardError' do
      rescue_handlers = described_class.rescue_handlers
      discard_handler = rescue_handlers.find { |h| h[0] == 'StandardError' }

      expect(discard_handler).to be_present
    end
  end

  describe '#perform' do
    let(:manager) { instance_double(Ai::Git::WorktreeManager) }

    before do
      allow(Ai::Git::WorktreeManager).to receive(:new)
        .with(repository_path: repository_path)
        .and_return(manager)

      allow(manager).to receive(:remove_worktree).and_return(true)
      allow(manager).to receive(:prune)
    end

    context 'with worktrees to clean up' do
      let!(:session) do
        create(:ai_worktree_session, :completed,
               account: account,
               repository_path: repository_path,
               merge_config: { 'delete_on_merge' => true })
      end
      let!(:worktree1) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/cleanup/task-1',
               worktree_path: '/tmp/test_repo/tmp/worktrees/cleanup/task-1')
      end
      let!(:worktree2) do
        create(:ai_worktree, :merged,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/cleanup/task-2',
               worktree_path: '/tmp/test_repo/tmp/worktrees/cleanup/task-2')
      end

      it 'removes each worktree' do
        described_class.new.perform(session.id)

        expect(manager).to have_received(:remove_worktree).with(
          worktree_path: worktree1.worktree_path,
          branch_name: worktree1.branch_name,
          force: true
        )
        expect(manager).to have_received(:remove_worktree).with(
          worktree_path: worktree2.worktree_path,
          branch_name: worktree2.branch_name,
          force: true
        )
      end

      it 'prunes stale worktree references' do
        described_class.new.perform(session.id)

        expect(manager).to have_received(:prune)
      end

      it 'marks worktrees as cleaned_up' do
        described_class.new.perform(session.id)

        expect(worktree1.reload.status).to eq('cleaned_up')
        expect(worktree2.reload.status).to eq('cleaned_up')
      end
    end

    context 'when delete_on_merge is false' do
      let!(:session) do
        create(:ai_worktree_session, :completed,
               account: account,
               repository_path: repository_path,
               merge_config: { 'delete_on_merge' => false })
      end
      let!(:worktree) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/keep/task-1',
               worktree_path: '/tmp/test_repo/tmp/worktrees/keep/task-1')
      end

      it 'does not pass branch_name for deletion' do
        described_class.new.perform(session.id)

        expect(manager).to have_received(:remove_worktree).with(
          worktree_path: worktree.worktree_path,
          branch_name: nil,
          force: true
        )
      end
    end

    context 'when individual worktree cleanup fails' do
      let!(:session) do
        create(:ai_worktree_session, :completed,
               account: account,
               repository_path: repository_path)
      end
      let!(:worktree1) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/fail/task-1',
               worktree_path: '/tmp/test_repo/tmp/worktrees/fail/task-1')
      end
      let!(:worktree2) do
        create(:ai_worktree, :merged,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/fail/task-2',
               worktree_path: '/tmp/test_repo/tmp/worktrees/fail/task-2')
      end

      before do
        call_count = 0
        allow(manager).to receive(:remove_worktree) do
          call_count += 1
          raise StandardError, 'Cannot remove' if call_count == 1

          true
        end
      end

      it 'continues cleaning up other worktrees' do
        described_class.new.perform(session.id)

        expect(manager).to have_received(:remove_worktree).twice
      end

      it 'still prunes after partial failure' do
        described_class.new.perform(session.id)

        expect(manager).to have_received(:prune)
      end

      it 'marks successfully cleaned worktrees' do
        described_class.new.perform(session.id)

        # Second worktree should be cleaned up, first should remain as-is
        expect(worktree2.reload.status).to eq('cleaned_up')
      end
    end

    context 'when worktrees are already cleaned up' do
      let!(:session) do
        create(:ai_worktree_session, :completed,
               account: account,
               repository_path: repository_path)
      end
      let!(:worktree) do
        create(:ai_worktree, :cleaned_up,
               worktree_session: session,
               account: account)
      end

      it 'skips already cleaned up worktrees' do
        described_class.new.perform(session.id)

        expect(manager).not_to have_received(:remove_worktree)
      end

      it 'still prunes' do
        described_class.new.perform(session.id)

        expect(manager).to have_received(:prune)
      end
    end
  end
end
