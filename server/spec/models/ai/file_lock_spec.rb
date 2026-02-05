# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::FileLock, type: :model do
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
    subject { build(:ai_file_lock) }

    it { should validate_presence_of(:file_path) }
    it { should validate_uniqueness_of(:file_path).scoped_to(:worktree_session_id) }
    it { should validate_inclusion_of(:lock_type).in_array(Ai::FileLock::LOCK_TYPES) }
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let!(:session) { create(:ai_worktree_session) }
    let!(:worktree) { create(:ai_worktree, worktree_session: session, account: session.account) }

    let!(:active_lock) do
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree,
             account: session.account,
             file_path: 'src/active.rb')
    end
    let!(:ttl_lock) do
      create(:ai_file_lock, :with_ttl,
             worktree_session: session,
             worktree: worktree,
             account: session.account,
             file_path: 'src/ttl.rb')
    end
    let!(:expired_lock) do
      create(:ai_file_lock, :expired,
             worktree_session: session,
             worktree: worktree,
             account: session.account,
             file_path: 'src/expired.rb')
    end
    let!(:shared_lock) do
      create(:ai_file_lock, :shared,
             worktree_session: session,
             worktree: worktree,
             account: session.account,
             file_path: 'src/shared.rb')
    end

    describe '.active' do
      it 'includes locks with no expiry' do
        expect(described_class.active).to include(active_lock)
      end

      it 'includes locks with future expiry' do
        expect(described_class.active).to include(ttl_lock)
      end

      it 'excludes expired locks' do
        expect(described_class.active).not_to include(expired_lock)
      end
    end

    describe '.for_session' do
      let!(:other_session) { create(:ai_worktree_session) }
      let!(:other_worktree) { create(:ai_worktree, worktree_session: other_session, account: other_session.account) }
      let!(:other_lock) do
        create(:ai_file_lock,
               worktree_session: other_session,
               worktree: other_worktree,
               account: other_session.account,
               file_path: 'src/other.rb')
      end

      it 'filters locks by session' do
        expect(described_class.for_session(session.id)).to include(active_lock, ttl_lock, expired_lock, shared_lock)
        expect(described_class.for_session(session.id)).not_to include(other_lock)
      end
    end

    describe '.for_file' do
      it 'filters locks by file path' do
        expect(described_class.for_file('src/active.rb')).to include(active_lock)
        expect(described_class.for_file('src/active.rb')).not_to include(ttl_lock, expired_lock, shared_lock)
      end
    end

    describe '.exclusive_locks' do
      it 'returns only exclusive locks' do
        expect(described_class.exclusive_locks).to include(active_lock, ttl_lock, expired_lock)
        expect(described_class.exclusive_locks).not_to include(shared_lock)
      end
    end
  end

  # ==========================================
  # Instance Methods
  # ==========================================
  describe '#expired?' do
    it 'returns false when expires_at is nil' do
      lock = build(:ai_file_lock, expires_at: nil)
      expect(lock.expired?).to be false
    end

    it 'returns false when expires_at is in the future' do
      lock = build(:ai_file_lock, :with_ttl)
      expect(lock.expired?).to be false
    end

    it 'returns true when expires_at is in the past' do
      lock = build(:ai_file_lock, :expired)
      expect(lock.expired?).to be true
    end
  end

  describe '#active?' do
    it 'returns true when not expired' do
      lock = build(:ai_file_lock)
      expect(lock.active?).to be true
    end

    it 'returns true when expires_at is in the future' do
      lock = build(:ai_file_lock, :with_ttl)
      expect(lock.active?).to be true
    end

    it 'returns false when expired' do
      lock = build(:ai_file_lock, :expired)
      expect(lock.active?).to be false
    end
  end

  # ==========================================
  # Factories
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_file_lock)).to be_valid
    end

    it 'creates expired lock' do
      lock = create(:ai_file_lock, :expired)
      expect(lock.expires_at).to be < Time.current
      expect(lock.expired?).to be true
    end

    it 'creates shared lock' do
      lock = create(:ai_file_lock, :shared)
      expect(lock.lock_type).to eq('shared')
    end

    it 'creates lock with TTL' do
      lock = create(:ai_file_lock, :with_ttl)
      expect(lock.expires_at).to be > Time.current
      expect(lock.active?).to be true
    end
  end
end
