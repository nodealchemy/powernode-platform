# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::WorktreeSession, type: :model do
  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:initiated_by).class_name('User').optional }
    it { should belong_to(:source).optional }
    it { should have_many(:worktrees).dependent(:destroy) }
    it { should have_many(:merge_operations).dependent(:destroy) }
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject { build(:ai_worktree_session) }

    it { should validate_presence_of(:repository_path) }
    it { should validate_presence_of(:base_branch) }
    it { should validate_inclusion_of(:status).in_array(Ai::WorktreeSession::STATUSES) }
    it { should validate_inclusion_of(:merge_strategy).in_array(Ai::WorktreeSession::MERGE_STRATEGIES) }

    describe 'max_parallel numericality' do
      it 'requires max_parallel to be greater than 0' do
        session = build(:ai_worktree_session, max_parallel: 0)
        expect(session).not_to be_valid
        expect(session.errors[:max_parallel]).to be_present
      end

      it 'requires max_parallel to be less than or equal to 20' do
        session = build(:ai_worktree_session, max_parallel: 21)
        expect(session).not_to be_valid
        expect(session.errors[:max_parallel]).to be_present
      end

      it 'allows max_parallel within valid range' do
        session = build(:ai_worktree_session, max_parallel: 10)
        session.valid?
        expect(session.errors[:max_parallel]).to be_empty
      end
    end
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let!(:pending_session) { create(:ai_worktree_session) }
    let!(:active_session) { create(:ai_worktree_session, :active) }
    let!(:completed_session) { create(:ai_worktree_session, :completed) }
    let!(:failed_session) { create(:ai_worktree_session, :failed) }
    let!(:cancelled_session) { create(:ai_worktree_session, :cancelled) }

    describe '.active_sessions' do
      it 'returns pending, provisioning, active, and merging sessions' do
        expect(described_class.active_sessions).to include(pending_session, active_session)
        expect(described_class.active_sessions).not_to include(completed_session, failed_session, cancelled_session)
      end
    end

    describe '.terminal' do
      it 'returns completed, failed, and cancelled sessions' do
        expect(described_class.terminal).to include(completed_session, failed_session, cancelled_session)
        expect(described_class.terminal).not_to include(pending_session, active_session)
      end
    end

    describe '.recent' do
      it 'orders sessions by created_at descending' do
        old_session = create(:ai_worktree_session, created_at: 1.day.ago)
        new_session = create(:ai_worktree_session, created_at: 1.hour.ago)

        recent = described_class.recent.limit(10)
        expect(recent.to_a.index(new_session)).to be < recent.to_a.index(old_session)
      end
    end
  end

  # ==========================================
  # State Machine
  # ==========================================
  describe 'state machine' do
    describe '#start!' do
      it 'transitions from pending to provisioning' do
        session = create(:ai_worktree_session)
        session.start!
        expect(session.status).to eq('provisioning')
        expect(session.started_at).to be_present
      end

      it 'raises error when not in pending status' do
        session = create(:ai_worktree_session, :active)
        expect { session.start! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot start/)
      end
    end

    describe '#activate!' do
      it 'transitions from provisioning to active' do
        session = create(:ai_worktree_session, :provisioning)
        session.activate!
        expect(session.status).to eq('active')
      end

      it 'raises error when not in provisioning status' do
        session = create(:ai_worktree_session, :active)
        expect { session.activate! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot activate/)
      end
    end

    describe '#begin_merge!' do
      it 'transitions from active to merging' do
        session = create(:ai_worktree_session, :active)
        session.begin_merge!
        expect(session.status).to eq('merging')
      end

      it 'raises error when not in active status' do
        session = create(:ai_worktree_session)
        expect { session.begin_merge! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot begin_merge/)
      end
    end

    describe '#complete!' do
      it 'transitions from merging to completed' do
        session = create(:ai_worktree_session, :merging)
        session.complete!
        expect(session.status).to eq('completed')
        expect(session.completed_at).to be_present
        expect(session.duration_ms).to be_present
      end

      it 'transitions from active to completed' do
        session = create(:ai_worktree_session, :active)
        session.complete!
        expect(session.status).to eq('completed')
      end

      it 'raises error when not in merging or active status' do
        session = create(:ai_worktree_session)
        expect { session.complete! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot complete/)
      end
    end

    describe '#fail!' do
      it 'transitions to failed with error details' do
        session = create(:ai_worktree_session, :active)
        session.fail!(error_message: 'Something broke', error_code: 'BROKEN')
        expect(session.status).to eq('failed')
        expect(session.error_message).to eq('Something broke')
        expect(session.error_code).to eq('BROKEN')
        expect(session.completed_at).to be_present
      end

      it 'can fail from any non-terminal status' do
        session = create(:ai_worktree_session)
        session.fail!(error_message: 'Error')
        expect(session.status).to eq('failed')
      end
    end

    describe '#cancel!' do
      it 'transitions to cancelled from active status' do
        session = create(:ai_worktree_session, :active)
        session.cancel!
        expect(session.status).to eq('cancelled')
        expect(session.completed_at).to be_present
      end

      it 'raises error when already in terminal status' do
        session = create(:ai_worktree_session, :completed)
        expect { session.cancel! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot cancel/)
      end
    end
  end

  # ==========================================
  # Helpers
  # ==========================================
  describe '#terminal?' do
    it 'returns true for completed status' do
      session = build(:ai_worktree_session, status: 'completed')
      expect(session.terminal?).to be true
    end

    it 'returns true for failed status' do
      session = build(:ai_worktree_session, status: 'failed')
      expect(session.terminal?).to be true
    end

    it 'returns true for cancelled status' do
      session = build(:ai_worktree_session, status: 'cancelled')
      expect(session.terminal?).to be true
    end

    it 'returns false for active status' do
      session = build(:ai_worktree_session, status: 'active')
      expect(session.terminal?).to be false
    end

    it 'returns false for pending status' do
      session = build(:ai_worktree_session, status: 'pending')
      expect(session.terminal?).to be false
    end
  end

  describe '#progress_percentage' do
    it 'returns percentage based on completed worktrees' do
      session = build(:ai_worktree_session, total_worktrees: 10, completed_worktrees: 3)
      expect(session.progress_percentage).to eq(30.0)
    end

    it 'returns 100 when all worktrees completed' do
      session = build(:ai_worktree_session, total_worktrees: 5, completed_worktrees: 5)
      expect(session.progress_percentage).to eq(100.0)
    end

    it 'returns 0 when total_worktrees is zero' do
      session = build(:ai_worktree_session, total_worktrees: 0, completed_worktrees: 0)
      expect(session.progress_percentage).to eq(0)
    end
  end

  describe '#all_worktrees_completed?' do
    it 'returns true when completed equals total' do
      session = build(:ai_worktree_session, total_worktrees: 3, completed_worktrees: 3)
      expect(session.all_worktrees_completed?).to be true
    end

    it 'returns false when completed + failed is less than total' do
      session = build(:ai_worktree_session, total_worktrees: 3, completed_worktrees: 1, failed_worktrees: 0)
      expect(session.all_worktrees_completed?).to be false
    end

    it 'returns true when completed + failed equals total' do
      session = build(:ai_worktree_session, total_worktrees: 3, completed_worktrees: 2, failed_worktrees: 1)
      expect(session.all_worktrees_completed?).to be true
    end

    it 'returns false when total_worktrees is zero' do
      session = build(:ai_worktree_session, total_worktrees: 0, completed_worktrees: 0)
      expect(session.all_worktrees_completed?).to be false
    end
  end

  describe '#failure_policy' do
    it 'returns "continue" by default' do
      session = build(:ai_worktree_session, configuration: {})
      expect(session.failure_policy).to eq('continue')
    end

    it 'returns configured failure policy' do
      session = build(:ai_worktree_session, :abort_policy)
      expect(session.failure_policy).to eq('abort')
    end
  end

  describe '#session_summary' do
    it 'returns session summary hash' do
      session = create(:ai_worktree_session, :active)
      summary = session.session_summary

      expect(summary[:id]).to eq(session.id)
      expect(summary[:status]).to eq('active')
      expect(summary[:repository_path]).to eq(session.repository_path)
      expect(summary[:base_branch]).to eq('main')
      expect(summary[:merge_strategy]).to eq('sequential')
      expect(summary[:max_parallel]).to eq(4)
      expect(summary[:total_worktrees]).to eq(3)
      expect(summary[:completed_worktrees]).to eq(0)
      expect(summary[:failed_worktrees]).to eq(0)
      expect(summary[:progress_percentage]).to eq(0.0)
      expect(summary[:started_at]).to be_present
      expect(summary[:created_at]).to be_present
    end
  end

  # ==========================================
  # Factories
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_worktree_session)).to be_valid
    end

    it 'creates provisioning session' do
      session = create(:ai_worktree_session, :provisioning)
      expect(session.status).to eq('provisioning')
      expect(session.started_at).to be_present
    end

    it 'creates active session' do
      session = create(:ai_worktree_session, :active)
      expect(session.status).to eq('active')
      expect(session.started_at).to be_present
    end

    it 'creates merging session' do
      session = create(:ai_worktree_session, :merging)
      expect(session.status).to eq('merging')
    end

    it 'creates completed session' do
      session = create(:ai_worktree_session, :completed)
      expect(session.status).to eq('completed')
      expect(session.completed_at).to be_present
      expect(session.duration_ms).to eq(3600000)
      expect(session.completed_worktrees).to eq(3)
    end

    it 'creates failed session' do
      session = create(:ai_worktree_session, :failed)
      expect(session.status).to eq('failed')
      expect(session.error_message).to be_present
      expect(session.error_code).to be_present
    end

    it 'creates cancelled session' do
      session = create(:ai_worktree_session, :cancelled)
      expect(session.status).to eq('cancelled')
    end

    it 'creates integration branch strategy session' do
      session = create(:ai_worktree_session, :integration_branch_strategy)
      expect(session.merge_strategy).to eq('integration_branch')
      expect(session.integration_branch).to eq('integration/test')
    end

    it 'creates manual strategy session' do
      session = create(:ai_worktree_session, :manual_strategy)
      expect(session.merge_strategy).to eq('manual')
    end

    it 'creates session with abort policy' do
      session = create(:ai_worktree_session, :abort_policy)
      expect(session.failure_policy).to eq('abort')
    end

    it 'creates session with worktrees' do
      session = create(:ai_worktree_session, :with_worktrees, worktrees_count: 2)
      expect(session.worktrees.count).to eq(2)
    end
  end

  # ==========================================
  # File Locks Association
  # ==========================================
  describe 'file_locks association' do
    it { should have_many(:file_locks).dependent(:destroy) }
  end

  # ==========================================
  # Execution Mode Validation
  # ==========================================
  describe 'execution_mode validation' do
    it { should validate_inclusion_of(:execution_mode).in_array(Ai::WorktreeSession::EXECUTION_MODES) }

    it 'allows complementary mode' do
      session = build(:ai_worktree_session, execution_mode: 'complementary')
      session.valid?
      expect(session.errors[:execution_mode]).to be_empty
    end

    it 'allows competitive mode' do
      session = build(:ai_worktree_session, execution_mode: 'competitive')
      session.valid?
      expect(session.errors[:execution_mode]).to be_empty
    end

    it 'rejects invalid execution modes' do
      session = build(:ai_worktree_session, execution_mode: 'invalid')
      expect(session).not_to be_valid
      expect(session.errors[:execution_mode]).to be_present
    end
  end

  # ==========================================
  # Max Duration Seconds Validation
  # ==========================================
  describe 'max_duration_seconds validation' do
    it 'allows nil max_duration_seconds' do
      session = build(:ai_worktree_session, max_duration_seconds: nil)
      session.valid?
      expect(session.errors[:max_duration_seconds]).to be_empty
    end

    it 'allows positive max_duration_seconds' do
      session = build(:ai_worktree_session, max_duration_seconds: 3600)
      session.valid?
      expect(session.errors[:max_duration_seconds]).to be_empty
    end

    it 'rejects zero max_duration_seconds' do
      session = build(:ai_worktree_session, max_duration_seconds: 0)
      expect(session).not_to be_valid
      expect(session.errors[:max_duration_seconds]).to be_present
    end

    it 'rejects negative max_duration_seconds' do
      session = build(:ai_worktree_session, max_duration_seconds: -100)
      expect(session).not_to be_valid
      expect(session.errors[:max_duration_seconds]).to be_present
    end
  end

  # ==========================================
  # Competitive?
  # ==========================================
  describe '#competitive?' do
    it 'returns true when execution_mode is competitive' do
      session = build(:ai_worktree_session, execution_mode: 'competitive')
      expect(session.competitive?).to be true
    end

    it 'returns false when execution_mode is complementary' do
      session = build(:ai_worktree_session, execution_mode: 'complementary')
      expect(session.competitive?).to be false
    end
  end

  # ==========================================
  # Require Tests?
  # ==========================================
  describe '#require_tests?' do
    it 'returns true when configuration has require_tests set to true' do
      session = build(:ai_worktree_session, configuration: { 'require_tests' => true })
      expect(session.require_tests?).to be true
    end

    it 'returns false when configuration has require_tests set to false' do
      session = build(:ai_worktree_session, configuration: { 'require_tests' => false })
      expect(session.require_tests?).to be false
    end

    it 'returns false when configuration does not have require_tests' do
      session = build(:ai_worktree_session, configuration: {})
      expect(session.require_tests?).to be false
    end
  end

  # ==========================================
  # Update Conflict Matrix
  # ==========================================
  describe '#update_conflict_matrix!' do
    it 'updates the conflict_matrix field' do
      session = create(:ai_worktree_session)
      matrix = { 'file1.rb' => ['worktree-1', 'worktree-2'], 'file2.rb' => ['worktree-3'] }
      session.update_conflict_matrix!(matrix)
      expect(session.reload.conflict_matrix).to eq(matrix)
    end

    it 'replaces existing conflict_matrix data' do
      session = create(:ai_worktree_session)
      session.update_conflict_matrix!({ 'old.rb' => ['wt-1'] })
      new_matrix = { 'new.rb' => ['wt-2', 'wt-3'] }
      session.update_conflict_matrix!(new_matrix)
      expect(session.reload.conflict_matrix).to eq(new_matrix)
    end
  end
end
