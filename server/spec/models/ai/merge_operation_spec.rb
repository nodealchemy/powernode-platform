# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::MergeOperation, type: :model do
  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:worktree_session).class_name('Ai::WorktreeSession') }
    it { should belong_to(:worktree).class_name('Ai::Worktree') }
    it { should belong_to(:account) }
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject { build(:ai_merge_operation) }

    it { should validate_presence_of(:source_branch) }
    it { should validate_presence_of(:target_branch) }
    it { should validate_inclusion_of(:status).in_array(Ai::MergeOperation::STATUSES) }
    it { should validate_inclusion_of(:strategy).in_array(Ai::MergeOperation::STRATEGIES) }
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let!(:session) { create(:ai_worktree_session) }
    let!(:worktree1) { create(:ai_worktree, :completed, worktree_session: session, account: session.account) }
    let!(:worktree2) { create(:ai_worktree, :completed, worktree_session: session, account: session.account) }

    let!(:pending_op) do
      create(:ai_merge_operation,
             worktree_session: session,
             worktree: worktree1,
             account: session.account,
             merge_order: 0)
    end
    let!(:completed_op) do
      create(:ai_merge_operation, :completed,
             worktree_session: session,
             worktree: worktree2,
             account: session.account,
             merge_order: 1)
    end
    let!(:conflict_op) do
      create(:ai_merge_operation, :conflict,
             worktree_session: session,
             worktree: worktree1,
             account: session.account,
             merge_order: 2)
    end

    describe '.by_order' do
      it 'orders operations by merge_order' do
        ordered = described_class.by_order
        orders = ordered.where(worktree_session: session).pluck(:merge_order)
        expect(orders).to eq(orders.sort)
      end
    end

    describe '.pending_merges' do
      it 'returns only pending operations' do
        expect(described_class.pending_merges).to include(pending_op)
        expect(described_class.pending_merges).not_to include(completed_op, conflict_op)
      end
    end

    describe '.with_conflicts' do
      it 'returns only operations with conflicts' do
        expect(described_class.with_conflicts).to include(conflict_op)
        expect(described_class.with_conflicts).not_to include(pending_op, completed_op)
      end
    end
  end

  # ==========================================
  # State Machine
  # ==========================================
  describe 'state machine' do
    describe '#start!' do
      it 'transitions from pending to in_progress' do
        operation = create(:ai_merge_operation)
        operation.start!
        expect(operation.status).to eq('in_progress')
        expect(operation.started_at).to be_present
      end

      it 'raises error when not in pending status' do
        operation = create(:ai_merge_operation, :completed)
        expect { operation.start! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot start/)
      end
    end

    describe '#complete!' do
      it 'transitions from in_progress to completed with merge commit sha' do
        operation = create(:ai_merge_operation, :in_progress)
        sha = SecureRandom.hex(20)
        operation.complete!(merge_commit_sha: sha)
        expect(operation.status).to eq('completed')
        expect(operation.merge_commit_sha).to eq(sha)
        expect(operation.completed_at).to be_present
        expect(operation.duration_ms).to be_present
      end

      it 'raises error when not in in_progress status' do
        operation = create(:ai_merge_operation)
        expect { operation.complete!(merge_commit_sha: SecureRandom.hex(20)) }.to raise_error(ActiveRecord::RecordInvalid, /Cannot complete/)
      end
    end

    describe '#mark_conflict!' do
      it 'transitions to conflict with details' do
        operation = create(:ai_merge_operation, :in_progress)
        files = ['src/file1.rb', 'src/file2.rb']
        operation.mark_conflict!(conflict_files: files, conflict_details: 'CONFLICT in file1.rb')
        expect(operation.status).to eq('conflict')
        expect(operation.has_conflicts).to be true
        expect(operation.conflict_files).to eq(files)
        expect(operation.conflict_details).to eq('CONFLICT in file1.rb')
        expect(operation.completed_at).to be_present
      end
    end

    describe '#fail!' do
      it 'transitions to failed with error details' do
        operation = create(:ai_merge_operation, :in_progress)
        operation.fail!(error_message: 'Fatal error', error_code: 'MERGE_FAILED')
        expect(operation.status).to eq('failed')
        expect(operation.error_message).to eq('Fatal error')
        expect(operation.error_code).to eq('MERGE_FAILED')
        expect(operation.completed_at).to be_present
      end
    end

    describe '#rollback!' do
      it 'transitions to rolled_back with rollback sha' do
        operation = create(:ai_merge_operation, :completed)
        rollback_sha = SecureRandom.hex(20)
        operation.rollback!(rollback_sha: rollback_sha)
        expect(operation.status).to eq('rolled_back')
        expect(operation.rollback_commit_sha).to eq(rollback_sha)
        expect(operation.rolled_back).to be true
        expect(operation.rolled_back_at).to be_present
      end
    end
  end

  # ==========================================
  # Helpers
  # ==========================================
  describe '#conflicted?' do
    it 'returns true when has_conflicts is true' do
      operation = build(:ai_merge_operation, :conflict)
      expect(operation.conflicted?).to be true
    end

    it 'returns false when has_conflicts is false' do
      operation = build(:ai_merge_operation)
      expect(operation.conflicted?).to be false
    end
  end

  describe '#conflict_count' do
    it 'returns the number of conflict files' do
      operation = build(:ai_merge_operation, :conflict)
      expect(operation.conflict_count).to eq(2)
    end

    it 'returns 0 when no conflicts' do
      operation = build(:ai_merge_operation)
      expect(operation.conflict_count).to eq(0)
    end
  end

  describe '#can_rollback?' do
    it 'returns true when completed with merge_commit_sha' do
      operation = build(:ai_merge_operation, :completed)
      expect(operation.can_rollback?).to be true
    end

    it 'returns false when pending' do
      operation = build(:ai_merge_operation)
      expect(operation.can_rollback?).to be false
    end

    it 'returns false when already rolled back' do
      operation = build(:ai_merge_operation, :rolled_back)
      expect(operation.can_rollback?).to be false
    end
  end

  describe '#operation_summary' do
    it 'returns operation summary hash' do
      operation = create(:ai_merge_operation, :completed)
      summary = operation.operation_summary

      expect(summary[:id]).to eq(operation.id)
      expect(summary[:worktree_id]).to eq(operation.worktree_id)
      expect(summary[:source_branch]).to eq(operation.source_branch)
      expect(summary[:target_branch]).to eq('main')
      expect(summary[:strategy]).to eq('merge')
      expect(summary[:status]).to eq('completed')
      expect(summary[:merge_order]).to eq(0)
      expect(summary[:merge_commit_sha]).to be_present
      expect(summary[:has_conflicts]).to be false
      expect(summary[:rolled_back]).to be false
      expect(summary[:started_at]).to be_present
      expect(summary[:completed_at]).to be_present
      expect(summary[:duration_ms]).to be_present
    end
  end

  # ==========================================
  # Factories
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_merge_operation)).to be_valid
    end

    it 'creates in_progress operation' do
      operation = create(:ai_merge_operation, :in_progress)
      expect(operation.status).to eq('in_progress')
      expect(operation.started_at).to be_present
    end

    it 'creates completed operation' do
      operation = create(:ai_merge_operation, :completed)
      expect(operation.status).to eq('completed')
      expect(operation.merge_commit_sha).to be_present
      expect(operation.completed_at).to be_present
      expect(operation.duration_ms).to eq(5000)
    end

    it 'creates conflict operation' do
      operation = create(:ai_merge_operation, :conflict)
      expect(operation.status).to eq('conflict')
      expect(operation.has_conflicts).to be true
      expect(operation.conflict_files).to eq(['src/file1.rb', 'src/file2.rb'])
      expect(operation.conflict_details).to be_present
    end

    it 'creates failed operation' do
      operation = create(:ai_merge_operation, :failed)
      expect(operation.status).to eq('failed')
      expect(operation.error_message).to be_present
      expect(operation.error_code).to eq('MERGE_FAILED')
    end

    it 'creates rolled_back operation' do
      operation = create(:ai_merge_operation, :rolled_back)
      expect(operation.status).to eq('rolled_back')
      expect(operation.rolled_back).to be true
      expect(operation.rollback_commit_sha).to be_present
      expect(operation.rolled_back_at).to be_present
    end

    it 'creates squash operation' do
      operation = create(:ai_merge_operation, :squash)
      expect(operation.strategy).to eq('squash')
    end
  end
end
