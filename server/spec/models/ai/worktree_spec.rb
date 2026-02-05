# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Worktree, type: :model do
  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:worktree_session).class_name('Ai::WorktreeSession') }
    it { should belong_to(:account) }
    it { should belong_to(:ai_agent).class_name('Ai::Agent').optional }
    it { should belong_to(:assignee).optional }
    it { should have_many(:merge_operations).dependent(:destroy) }
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject { build(:ai_worktree) }

    it { should validate_presence_of(:branch_name) }
    it { should validate_uniqueness_of(:branch_name) }
    it { should validate_presence_of(:worktree_path) }
    it { should validate_uniqueness_of(:worktree_path) }
    it { should validate_inclusion_of(:status).in_array(Ai::Worktree::STATUSES) }
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let!(:session) { create(:ai_worktree_session) }
    let!(:pending_worktree) { create(:ai_worktree, worktree_session: session, account: session.account) }
    let!(:ready_worktree) { create(:ai_worktree, :ready, worktree_session: session, account: session.account) }
    let!(:completed_worktree) { create(:ai_worktree, :completed, worktree_session: session, account: session.account) }
    let!(:merged_worktree) { create(:ai_worktree, :merged, worktree_session: session, account: session.account) }
    let!(:failed_worktree) { create(:ai_worktree, :failed, worktree_session: session, account: session.account) }

    describe '.active' do
      it 'returns pending, creating, ready, and in_use worktrees' do
        expect(described_class.active).to include(pending_worktree, ready_worktree)
        expect(described_class.active).not_to include(completed_worktree, merged_worktree, failed_worktree)
      end
    end

    describe '.completed_or_merged' do
      it 'returns completed and merged worktrees' do
        expect(described_class.completed_or_merged).to include(completed_worktree, merged_worktree)
        expect(described_class.completed_or_merged).not_to include(pending_worktree, failed_worktree)
      end
    end

    describe '.by_session' do
      let!(:other_session) { create(:ai_worktree_session) }
      let!(:other_worktree) { create(:ai_worktree, worktree_session: other_session, account: other_session.account) }

      it 'filters worktrees by session' do
        expect(described_class.by_session(session.id)).to include(pending_worktree, ready_worktree)
        expect(described_class.by_session(session.id)).not_to include(other_worktree)
      end
    end
  end

  # ==========================================
  # State Machine
  # ==========================================
  describe 'state machine' do
    describe '#mark_creating!' do
      it 'transitions from pending to creating' do
        worktree = create(:ai_worktree)
        worktree.mark_creating!
        expect(worktree.status).to eq('creating')
      end

      it 'raises error when not in pending status' do
        worktree = create(:ai_worktree, :ready)
        expect { worktree.mark_creating! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot mark_creating/)
      end
    end

    describe '#mark_ready!' do
      it 'transitions from creating to ready' do
        worktree = create(:ai_worktree, :creating)
        worktree.mark_ready!
        expect(worktree.status).to eq('ready')
        expect(worktree.ready_at).to be_present
      end

      it 'raises error when not in creating status' do
        worktree = create(:ai_worktree)
        expect { worktree.mark_ready! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot mark_ready/)
      end
    end

    describe '#mark_in_use!' do
      it 'transitions from ready to in_use' do
        worktree = create(:ai_worktree, :ready)
        worktree.mark_in_use!
        expect(worktree.status).to eq('in_use')
      end

      it 'raises error when not in ready status' do
        worktree = create(:ai_worktree)
        expect { worktree.mark_in_use! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot mark_in_use/)
      end
    end

    describe '#complete!' do
      it 'transitions from in_use to completed' do
        worktree = create(:ai_worktree, :in_use)
        worktree.complete!
        expect(worktree.status).to eq('completed')
        expect(worktree.completed_at).to be_present
        expect(worktree.duration_ms).to be_present
      end

      it 'accepts head_sha and stats' do
        worktree = create(:ai_worktree, :in_use)
        sha = SecureRandom.hex(20)
        worktree.complete!(head_sha: sha, stats: { files_changed: 10, lines_added: 200, lines_removed: 50 })
        expect(worktree.head_commit_sha).to eq(sha)
        expect(worktree.files_changed).to eq(10)
        expect(worktree.lines_added).to eq(200)
        expect(worktree.lines_removed).to eq(50)
      end

      it 'raises error when not in in_use status' do
        worktree = create(:ai_worktree, :ready)
        expect { worktree.complete! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot complete/)
      end
    end

    describe '#fail!' do
      it 'transitions to failed with error details' do
        worktree = create(:ai_worktree, :in_use)
        worktree.fail!(error_message: 'Something broke', error_code: 'BROKEN')
        expect(worktree.status).to eq('failed')
        expect(worktree.error_message).to eq('Something broke')
        expect(worktree.error_code).to eq('BROKEN')
        expect(worktree.completed_at).to be_present
      end

      it 'can fail from any status' do
        worktree = create(:ai_worktree)
        worktree.fail!(error_message: 'Error')
        expect(worktree.status).to eq('failed')
      end
    end

    describe '#mark_merged!' do
      it 'transitions from completed to merged' do
        worktree = create(:ai_worktree, :completed)
        worktree.mark_merged!
        expect(worktree.status).to eq('merged')
      end

      it 'raises error when not in completed status' do
        worktree = create(:ai_worktree, :in_use)
        expect { worktree.mark_merged! }.to raise_error(ActiveRecord::RecordInvalid, /Cannot mark_merged/)
      end
    end

    describe '#mark_cleaned_up!' do
      it 'transitions to cleaned_up' do
        worktree = create(:ai_worktree, :merged)
        worktree.mark_cleaned_up!
        expect(worktree.status).to eq('cleaned_up')
      end
    end
  end

  # ==========================================
  # Lock Management
  # ==========================================
  describe 'lock management' do
    describe '#lock!' do
      it 'locks the worktree with a reason' do
        worktree = create(:ai_worktree)
        worktree.lock!(reason: 'provisioning')
        expect(worktree.locked).to be true
        expect(worktree.lock_reason).to eq('provisioning')
        expect(worktree.locked_at).to be_present
      end
    end

    describe '#unlock!' do
      it 'unlocks the worktree' do
        worktree = create(:ai_worktree, :locked)
        worktree.unlock!
        expect(worktree.locked).to be false
        expect(worktree.lock_reason).to be_nil
        expect(worktree.locked_at).to be_nil
      end
    end
  end

  # ==========================================
  # Callbacks
  # ==========================================
  describe 'callbacks' do
    describe 'update_session_counts' do
      it 'updates session completed_worktrees when worktree completes' do
        session = create(:ai_worktree_session)
        worktree = create(:ai_worktree, :in_use, worktree_session: session, account: session.account)

        worktree.complete!
        session.reload

        expect(session.completed_worktrees).to eq(1)
      end

      it 'updates session failed_worktrees when worktree fails' do
        session = create(:ai_worktree_session)
        worktree = create(:ai_worktree, :in_use, worktree_session: session, account: session.account)

        worktree.fail!(error_message: 'Error')
        session.reload

        expect(session.failed_worktrees).to eq(1)
      end

      it 'counts merged and cleaned_up worktrees as completed' do
        session = create(:ai_worktree_session)
        worktree = create(:ai_worktree, :completed, worktree_session: session, account: session.account)

        worktree.mark_merged!
        session.reload

        expect(session.completed_worktrees).to eq(1)
      end
    end
  end

  # ==========================================
  # Helpers
  # ==========================================
  describe '#worktree_summary' do
    it 'returns worktree summary hash' do
      worktree = create(:ai_worktree, :ready)
      summary = worktree.worktree_summary

      expect(summary[:id]).to eq(worktree.id)
      expect(summary[:worktree_session_id]).to eq(worktree.worktree_session_id)
      expect(summary[:branch_name]).to eq(worktree.branch_name)
      expect(summary[:worktree_path]).to eq(worktree.worktree_path)
      expect(summary[:status]).to eq('ready')
      expect(summary[:locked]).to be false
      expect(summary[:healthy]).to be true
      expect(summary[:ready_at]).to be_present
      expect(summary[:created_at]).to be_present
    end
  end

  # ==========================================
  # Factories
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_worktree)).to be_valid
    end

    it 'creates creating worktree' do
      worktree = create(:ai_worktree, :creating)
      expect(worktree.status).to eq('creating')
    end

    it 'creates ready worktree' do
      worktree = create(:ai_worktree, :ready)
      expect(worktree.status).to eq('ready')
      expect(worktree.ready_at).to be_present
      expect(worktree.base_commit_sha).to be_present
    end

    it 'creates in_use worktree' do
      worktree = create(:ai_worktree, :in_use)
      expect(worktree.status).to eq('in_use')
    end

    it 'creates completed worktree' do
      worktree = create(:ai_worktree, :completed)
      expect(worktree.status).to eq('completed')
      expect(worktree.completed_at).to be_present
      expect(worktree.duration_ms).to eq(1800000)
      expect(worktree.files_changed).to eq(5)
    end

    it 'creates failed worktree' do
      worktree = create(:ai_worktree, :failed)
      expect(worktree.status).to eq('failed')
      expect(worktree.error_message).to be_present
    end

    it 'creates merged worktree' do
      worktree = create(:ai_worktree, :merged)
      expect(worktree.status).to eq('merged')
    end

    it 'creates cleaned_up worktree' do
      worktree = create(:ai_worktree, :cleaned_up)
      expect(worktree.status).to eq('cleaned_up')
    end

    it 'creates locked worktree' do
      worktree = create(:ai_worktree, :locked)
      expect(worktree.locked).to be true
      expect(worktree.lock_reason).to eq('provisioning')
      expect(worktree.locked_at).to be_present
    end

    it 'creates worktree with agent' do
      worktree = create(:ai_worktree, :with_agent)
      expect(worktree.ai_agent).to be_present
    end
  end

  # ==========================================
  # File Locks Association
  # ==========================================
  describe 'file_locks association' do
    it { should have_many(:file_locks).dependent(:destroy) }
  end

  # ==========================================
  # Test Status Validation
  # ==========================================
  describe 'test_status validation' do
    it { should validate_inclusion_of(:test_status).in_array(Ai::Worktree::TEST_STATUSES).allow_nil }
  end

  # ==========================================
  # Testing State Transitions
  # ==========================================
  describe '#mark_testing!' do
    let(:session) { create(:ai_worktree_session) }

    it 'transitions from in_use to testing' do
      worktree = create(:ai_worktree, :in_use, worktree_session: session, account: session.account)
      worktree.mark_testing!
      expect(worktree.status).to eq('testing')
      expect(worktree.test_status).to eq('pending')
    end

    it 'raises error from non-in_use state' do
      worktree = create(:ai_worktree, :ready, worktree_session: session, account: session.account)
      expect { worktree.mark_testing! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '#mark_test_passed!' do
    let(:session) { create(:ai_worktree_session) }

    it 'updates test_status and completes if testing' do
      worktree = create(:ai_worktree, worktree_session: session, account: session.account, status: 'testing', test_status: 'running', ready_at: 1.hour.ago)
      worktree.mark_test_passed!
      expect(worktree.test_status).to eq('passed')
      expect(worktree.status).to eq('completed')
    end
  end

  describe '#mark_test_failed!' do
    let(:session) { create(:ai_worktree_session) }

    it 'updates test_status and fails if testing' do
      worktree = create(:ai_worktree, worktree_session: session, account: session.account, status: 'testing', test_status: 'running', ready_at: 1.hour.ago)
      worktree.mark_test_failed!(error: 'Tests failed')
      expect(worktree.test_status).to eq('failed')
      expect(worktree.status).to eq('failed')
    end
  end

  # ==========================================
  # Cost Tracking
  # ==========================================
  describe '#update_cost!' do
    let(:session) { create(:ai_worktree_session) }

    it 'increments tokens_used and estimated_cost_cents' do
      worktree = create(:ai_worktree, :in_use, worktree_session: session, account: session.account, tokens_used: 100, estimated_cost_cents: 5)
      worktree.update_cost!(tokens: 200, cost_cents: 10)
      expect(worktree.tokens_used).to eq(300)
      expect(worktree.estimated_cost_cents).to eq(15)
    end
  end

  # ==========================================
  # Timeout
  # ==========================================
  describe '#timed_out?' do
    let(:session) { create(:ai_worktree_session) }

    it 'returns true when timeout_at is in the past' do
      worktree = create(:ai_worktree, worktree_session: session, account: session.account, timeout_at: 1.hour.ago)
      expect(worktree.timed_out?).to be true
    end

    it 'returns false when timeout_at is in the future' do
      worktree = create(:ai_worktree, worktree_session: session, account: session.account, timeout_at: 1.hour.from_now)
      expect(worktree.timed_out?).to be false
    end

    it 'returns false when timeout_at is nil' do
      worktree = create(:ai_worktree, worktree_session: session, account: session.account, timeout_at: nil)
      expect(worktree.timed_out?).to be false
    end
  end

  # ==========================================
  # Agent Name
  # ==========================================
  describe '#agent_name' do
    let(:session) { create(:ai_worktree_session) }

    it 'returns agent name when agent is assigned' do
      worktree = create(:ai_worktree, :with_agent, worktree_session: session, account: session.account)
      expect(worktree.agent_name).to eq(worktree.ai_agent.name)
    end

    it 'returns nil when no agent assigned' do
      worktree = create(:ai_worktree, worktree_session: session, account: session.account)
      expect(worktree.agent_name).to be_nil
    end
  end

  # ==========================================
  # Updated Complete! (accepts testing state)
  # ==========================================
  describe '#complete! from testing state' do
    let(:session) { create(:ai_worktree_session) }

    it 'transitions from testing to completed' do
      worktree = create(:ai_worktree, worktree_session: session, account: session.account, status: 'testing', ready_at: 1.hour.ago)
      worktree.complete!
      expect(worktree.status).to eq('completed')
      expect(worktree.completed_at).to be_present
    end
  end

  # ==========================================
  # Updated Active Scope (includes testing)
  # ==========================================
  describe '.active scope includes testing' do
    let(:session) { create(:ai_worktree_session) }

    it 'includes worktrees in testing state' do
      testing_worktree = create(:ai_worktree, worktree_session: session, account: session.account, status: 'testing', ready_at: 1.hour.ago)
      expect(described_class.active).to include(testing_worktree)
    end
  end
end
