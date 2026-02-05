# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::FileLockService, type: :service do
  let(:account) { create(:account) }
  let(:session) do
    create(:ai_worktree_session, :active, account: account)
  end
  let(:worktree_a) do
    create(:ai_worktree, :in_use,
           worktree_session: session,
           account: session.account)
  end
  let(:worktree_b) do
    create(:ai_worktree, :in_use,
           worktree_session: session,
           account: session.account)
  end

  subject(:service) { described_class.new(session: session) }

  before do
    allow(AiOrchestrationChannel).to receive(:broadcast_worktree_session_event)
    allow(AiOrchestrationChannel).to receive(:broadcast_worktree_event)
  end

  describe '#acquire' do
    context 'with valid file_paths' do
      it 'creates locks for each file path' do
        result = service.acquire(
          worktree: worktree_a,
          file_paths: ['src/app.rb', 'src/models/user.rb']
        )

        expect(result[:success]).to be true
        expect(result[:locks].size).to eq(2)
        expect(result[:locks].map { |l| l[:file_path] }).to contain_exactly('src/app.rb', 'src/models/user.rb')
      end

      it 'sets lock_type on created locks' do
        result = service.acquire(
          worktree: worktree_a,
          file_paths: ['src/app.rb'],
          lock_type: 'shared'
        )

        expect(result[:success]).to be true
        expect(result[:locks].first[:lock_type]).to eq('shared')
      end

      it 'associates locks with the correct worktree and session' do
        service.acquire(
          worktree: worktree_a,
          file_paths: ['src/app.rb']
        )

        lock = session.file_locks.last
        expect(lock.worktree).to eq(worktree_a)
        expect(lock.worktree_session).to eq(session)
        expect(lock.account).to eq(session.account)
      end

      it 'sets acquired_at timestamp' do
        freeze_time do
          result = service.acquire(
            worktree: worktree_a,
            file_paths: ['src/app.rb']
          )

          expect(result[:locks].first[:acquired_at]).to eq(Time.current.iso8601)
        end
      end
    end

    context 'with blank file_paths' do
      it 'returns success with empty locks for nil' do
        result = service.acquire(worktree: worktree_a, file_paths: nil)

        expect(result[:success]).to be true
        expect(result[:locks]).to eq([])
      end

      it 'returns success with empty locks for empty array' do
        result = service.acquire(worktree: worktree_a, file_paths: [])

        expect(result[:success]).to be true
        expect(result[:locks]).to eq([])
      end
    end

    context 'when conflicts exist with other worktrees' do
      before do
        create(:ai_file_lock,
               worktree_session: session,
               worktree: worktree_b,
               account: session.account,
               file_path: 'src/app.rb',
               lock_type: 'exclusive')
      end

      it 'returns failure with conflict details' do
        result = service.acquire(
          worktree: worktree_a,
          file_paths: ['src/app.rb']
        )

        expect(result[:success]).to be false
        expect(result[:conflicts].size).to eq(1)
        expect(result[:conflicts].first[:file_path]).to eq('src/app.rb')
        expect(result[:conflicts].first[:locked_by_worktree_id]).to eq(worktree_b.id)
        expect(result[:conflicts].first[:locked_by_branch]).to eq(worktree_b.branch_name)
      end

      it 'does not create any locks when conflicts exist' do
        expect {
          service.acquire(worktree: worktree_a, file_paths: ['src/app.rb'])
        }.not_to change(Ai::FileLock, :count)
      end
    end

    context 'with TTL' do
      it 'sets expires_at based on ttl_seconds' do
        freeze_time do
          result = service.acquire(
            worktree: worktree_a,
            file_paths: ['src/app.rb'],
            ttl_seconds: 3600
          )

          expect(result[:success]).to be true
          expected_expiry = (Time.current + 3600.seconds).iso8601
          expect(result[:locks].first[:expires_at]).to eq(expected_expiry)
        end
      end

      it 'leaves expires_at nil when no TTL specified' do
        result = service.acquire(
          worktree: worktree_a,
          file_paths: ['src/app.rb']
        )

        expect(result[:locks].first[:expires_at]).to be_nil
      end
    end

    context 'when the same worktree re-acquires its own lock' do
      before do
        create(:ai_file_lock,
               worktree_session: session,
               worktree: worktree_a,
               account: session.account,
               file_path: 'src/app.rb')
      end

      it 'fails due to uniqueness constraint' do
        result = service.acquire(
          worktree: worktree_a,
          file_paths: ['src/app.rb']
        )

        expect(result[:success]).to be false
      end
    end
  end

  describe '#release' do
    before do
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/app.rb')
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/models/user.rb')
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree_b,
             account: session.account,
             file_path: 'src/config.rb')
    end

    it 'deletes all locks for the specified worktree' do
      result = service.release(worktree: worktree_a)

      expect(result[:success]).to be true
      expect(result[:released]).to eq(2)
      expect(session.file_locks.where(worktree: worktree_a).count).to eq(0)
    end

    it 'does not delete locks belonging to other worktrees' do
      service.release(worktree: worktree_a)

      expect(session.file_locks.where(worktree: worktree_b).count).to eq(1)
    end

    it 'returns zero when no locks exist' do
      result = service.release(worktree: worktree_b)
      result = service.release(worktree: worktree_b)

      expect(result[:success]).to be true
      expect(result[:released]).to eq(0)
    end
  end

  describe '#release_files' do
    before do
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/app.rb')
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/models/user.rb')
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/config.rb')
    end

    it 'deletes only specified file locks' do
      result = service.release_files(
        worktree: worktree_a,
        file_paths: ['src/app.rb', 'src/models/user.rb']
      )

      expect(result[:success]).to be true
      expect(result[:released]).to eq(2)
    end

    it 'keeps locks for other files' do
      service.release_files(
        worktree: worktree_a,
        file_paths: ['src/app.rb']
      )

      remaining = session.file_locks.where(worktree: worktree_a).pluck(:file_path)
      expect(remaining).to contain_exactly('src/models/user.rb', 'src/config.rb')
    end
  end

  describe '#check_conflicts' do
    context 'with active locks from other worktrees' do
      before do
        create(:ai_file_lock,
               worktree_session: session,
               worktree: worktree_b,
               account: session.account,
               file_path: 'src/app.rb',
               lock_type: 'exclusive')
      end

      it 'finds conflicting locks' do
        conflicts = service.check_conflicts(
          worktree: worktree_a,
          file_paths: ['src/app.rb']
        )

        expect(conflicts.size).to eq(1)
        expect(conflicts.first[:file_path]).to eq('src/app.rb')
        expect(conflicts.first[:locked_by_worktree_id]).to eq(worktree_b.id)
        expect(conflicts.first[:lock_type]).to eq('exclusive')
      end

      it 'does not flag own locks as conflicts' do
        conflicts = service.check_conflicts(
          worktree: worktree_b,
          file_paths: ['src/app.rb']
        )

        expect(conflicts).to be_empty
      end
    end

    context 'with expired locks from other worktrees' do
      before do
        create(:ai_file_lock, :expired,
               worktree_session: session,
               worktree: worktree_b,
               account: session.account,
               file_path: 'src/app.rb')
      end

      it 'ignores expired locks' do
        conflicts = service.check_conflicts(
          worktree: worktree_a,
          file_paths: ['src/app.rb']
        )

        expect(conflicts).to be_empty
      end
    end

    context 'with no conflicting files' do
      before do
        create(:ai_file_lock,
               worktree_session: session,
               worktree: worktree_b,
               account: session.account,
               file_path: 'src/other.rb')
      end

      it 'returns empty array' do
        conflicts = service.check_conflicts(
          worktree: worktree_a,
          file_paths: ['src/app.rb']
        )

        expect(conflicts).to be_empty
      end
    end
  end

  describe '#cleanup_expired' do
    it 'removes expired locks' do
      create(:ai_file_lock, :expired,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/expired.rb')
      create(:ai_file_lock, :expired,
             worktree_session: session,
             worktree: worktree_b,
             account: session.account,
             file_path: 'src/also_expired.rb')

      result = service.cleanup_expired

      expect(result[:cleaned]).to eq(2)
    end

    it 'does not remove active locks' do
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/active.rb',
             expires_at: nil)
      create(:ai_file_lock, :with_ttl,
             worktree_session: session,
             worktree: worktree_b,
             account: session.account,
             file_path: 'src/future.rb')

      result = service.cleanup_expired

      expect(result[:cleaned]).to eq(0)
      expect(session.file_locks.count).to eq(2)
    end

    it 'returns zero when no expired locks exist' do
      result = service.cleanup_expired

      expect(result[:cleaned]).to eq(0)
    end
  end

  describe '#active_locks' do
    it 'returns only non-expired locks' do
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/active.rb')
      create(:ai_file_lock, :expired,
             worktree_session: session,
             worktree: worktree_b,
             account: session.account,
             file_path: 'src/expired.rb')

      result = service.active_locks

      expect(result.size).to eq(1)
      expect(result.first[:file_path]).to eq('src/active.rb')
    end

    it 'includes lock summary fields' do
      lock = create(:ai_file_lock,
                    worktree_session: session,
                    worktree: worktree_a,
                    account: session.account,
                    file_path: 'src/app.rb',
                    lock_type: 'exclusive')

      result = service.active_locks

      expect(result.first).to include(
        id: lock.id,
        file_path: 'src/app.rb',
        worktree_id: worktree_a.id,
        branch_name: worktree_a.branch_name,
        lock_type: 'exclusive'
      )
    end

    it 'returns empty array when no active locks exist' do
      result = service.active_locks

      expect(result).to eq([])
    end

    it 'includes locks with no expiry as active' do
      create(:ai_file_lock,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/no_expiry.rb',
             expires_at: nil)

      result = service.active_locks

      expect(result.size).to eq(1)
    end

    it 'includes locks with future expiry as active' do
      create(:ai_file_lock, :with_ttl,
             worktree_session: session,
             worktree: worktree_a,
             account: session.account,
             file_path: 'src/future.rb')

      result = service.active_locks

      expect(result.size).to eq(1)
    end
  end
end
