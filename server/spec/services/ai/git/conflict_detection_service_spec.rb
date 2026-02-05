# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Git::ConflictDetectionService, type: :service do
  let(:account) { create(:account) }
  let(:repository_path) { '/tmp/test_repo' }
  let(:session) do
    create(:ai_worktree_session, :active,
           account: account,
           repository_path: repository_path,
           base_branch: 'main')
  end

  subject(:service) { described_class.new(session: session) }

  let(:base_sha) { 'a' * 40 }
  let(:success_status) { instance_double(Process::Status, success?: true) }
  let(:failure_status) { instance_double(Process::Status, success?: false) }

  before do
    allow(AiOrchestrationChannel).to receive(:broadcast_worktree_session_event)
    allow(AiOrchestrationChannel).to receive(:broadcast_worktree_event)
  end

  describe '#detect' do
    context 'with fewer than 2 eligible worktrees' do
      it 'returns empty result when no worktrees exist' do
        result = service.detect

        expect(result[:conflicts]).to eq([])
        expect(result[:matrix]).to eq({})
      end

      it 'returns empty result with only 1 eligible worktree' do
        create(:ai_worktree, :in_use,
               worktree_session: session,
               account: session.account)

        result = service.detect

        expect(result[:conflicts]).to eq([])
        expect(result[:matrix]).to eq({})
      end

      it 'ignores worktrees in non-eligible statuses' do
        create(:ai_worktree, :in_use,
               worktree_session: session,
               account: session.account)
        create(:ai_worktree,
               worktree_session: session,
               account: session.account,
               status: 'pending')

        result = service.detect

        expect(result[:conflicts]).to eq([])
        expect(result[:matrix]).to eq({})
      end
    end

    context 'with 2+ eligible worktrees' do
      let!(:worktree_a) do
        create(:ai_worktree, :in_use,
               worktree_session: session,
               account: session.account)
      end
      let!(:worktree_b) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: session.account)
      end

      before do
        allow(Open3).to receive(:capture3).and_call_original
      end

      it 'calls git rev-parse for the base branch' do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'main', chdir: repository_path)
          .and_return([base_sha, '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'merge-tree', anything, anything, anything, chdir: repository_path)
          .and_return(['', '', success_status])

        service.detect

        expect(Open3).to have_received(:capture3)
          .with('git', 'rev-parse', 'main', chdir: repository_path)
      end

      it 'calls git merge-tree for each worktree pair' do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'main', chdir: repository_path)
          .and_return([base_sha, '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'merge-tree', base_sha, anything, anything, chdir: repository_path)
          .and_return(['', '', success_status])

        service.detect

        expect(Open3).to have_received(:capture3)
          .with('git', 'merge-tree', base_sha,
                worktree_a.head_commit_sha, worktree_b.head_commit_sha,
                chdir: repository_path)
      end

      context 'when base SHA cannot be resolved' do
        before do
          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', 'main', chdir: repository_path)
            .and_return(['', 'fatal: bad ref', failure_status])
        end

        it 'returns empty result with error message' do
          result = service.detect

          expect(result[:conflicts]).to eq([])
          expect(result[:matrix]).to eq({})
          expect(result[:error]).to eq('Could not resolve base SHA')
        end
      end

      context 'when merge-tree detects no conflicts' do
        before do
          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', 'main', chdir: repository_path)
            .and_return([base_sha, '', success_status])
          allow(Open3).to receive(:capture3)
            .with('git', 'merge-tree', base_sha, anything, anything, chdir: repository_path)
            .and_return(['', '', success_status])
        end

        it 'returns empty conflicts' do
          result = service.detect

          expect(result[:conflicts]).to eq([])
        end

        it 'populates matrix with no-conflict entries' do
          result = service.detect
          entry = result[:matrix].values.first

          expect(entry).to be_present
          expect(entry[:has_conflicts]).to be false
          expect(entry[:conflict_files]).to eq([])
        end

        it 'stores the conflict matrix on the session' do
          service.detect

          session.reload
          entry = session.conflict_matrix.values.first
          expect(entry).to be_present
          expect(entry['has_conflicts']).to be false
        end

        it 'does not broadcast when no conflicts' do
          service.detect

          expect(AiOrchestrationChannel).not_to have_received(:broadcast_worktree_session_event)
            .with(session, 'conflicts_detected', anything)
        end
      end

      context 'when merge-tree detects conflicts' do
        let(:conflict_output) do
          <<~OUTPUT
            changed in both
              base   100644 abc123 src/app.rb
              our    100644 def456 src/app.rb
              their  100644 ghi789 src/app.rb
          OUTPUT
        end

        before do
          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', 'main', chdir: repository_path)
            .and_return([base_sha, '', success_status])
          allow(Open3).to receive(:capture3)
            .with('git', 'merge-tree', base_sha, anything, anything, chdir: repository_path)
            .and_return([conflict_output, '', failure_status])
        end

        it 'returns conflicts with file information' do
          result = service.detect

          expect(result[:conflicts].size).to eq(1)
          conflict = result[:conflicts].first
          expect(conflict[:worktree_a_id]).to eq(worktree_a.id)
          expect(conflict[:worktree_b_id]).to eq(worktree_b.id)
          expect(conflict[:conflict_files]).to include('src/app.rb')
        end

        it 'marks the matrix entry as having conflicts' do
          result = service.detect
          entry = result[:matrix].values.first

          expect(entry).to be_present
          expect(entry[:has_conflicts]).to be true
        end

        it 'stores the conflict matrix on the session' do
          service.detect

          session.reload
          expect(session.conflict_matrix).to be_present
        end

        it 'broadcasts conflicts via AiOrchestrationChannel' do
          service.detect

          expect(AiOrchestrationChannel).to have_received(:broadcast_worktree_session_event)
            .with(session, 'conflicts_detected', hash_including(:conflicts, :detected_at))
        end

        it 'deduplicates conflict files' do
          duplicate_output = <<~OUTPUT
            changed in both
              our    100644 abc123 src/app.rb
              their  100644 def456 src/app.rb
              our    100644 ghi789 src/app.rb
          OUTPUT

          allow(Open3).to receive(:capture3)
            .with('git', 'merge-tree', base_sha, anything, anything, chdir: repository_path)
            .and_return([duplicate_output, '', failure_status])

          result = service.detect

          conflict_files = result[:conflicts].first[:conflict_files]
          expect(conflict_files.count('src/app.rb')).to eq(1)
        end
      end

      context 'when a worktree has no head_commit_sha' do
        before do
          worktree_a.update_columns(head_commit_sha: nil)

          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', 'main', chdir: repository_path)
            .and_return([base_sha, '', success_status])
        end

        it 'marks the pair as no conflicts' do
          result = service.detect
          key_ab = "#{worktree_a.id}:#{worktree_b.id}"
          key_ba = "#{worktree_b.id}:#{worktree_a.id}"
          entry = result[:matrix][key_ab] || result[:matrix][key_ba]

          expect(entry).to be_present
          expect(entry[:has_conflicts]).to be false
        end
      end

      context 'with 3 eligible worktrees' do
        let!(:worktree_c) do
          create(:ai_worktree, :in_use,
                 worktree_session: session,
                 account: session.account,
                 status: 'testing')
        end

        before do
          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', 'main', chdir: repository_path)
            .and_return([base_sha, '', success_status])
          allow(Open3).to receive(:capture3)
            .with('git', 'merge-tree', base_sha, anything, anything, chdir: repository_path)
            .and_return(['', '', success_status])
        end

        it 'checks all combinations (3 pairs)' do
          service.detect

          expect(Open3).to have_received(:capture3)
            .with('git', 'merge-tree', base_sha, anything, anything, chdir: repository_path)
            .exactly(3).times
        end
      end
    end

    context 'when an unexpected error occurs' do
      let!(:worktree_a) do
        create(:ai_worktree, :in_use,
               worktree_session: session,
               account: session.account)
      end
      let!(:worktree_b) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: session.account)
      end

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'main', chdir: repository_path)
          .and_raise(StandardError, 'Git binary not found')
      end

      it 'returns empty result with error message' do
        result = service.detect

        expect(result[:conflicts]).to eq([])
        expect(result[:matrix]).to eq({})
        expect(result[:error]).to eq('Git binary not found')
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/ConflictDetection.*Git binary not found/)

        service.detect
      end
    end

    context 'when merge-tree fails for a single pair' do
      let!(:worktree_a) do
        create(:ai_worktree, :in_use,
               worktree_session: session,
               account: session.account)
      end
      let!(:worktree_b) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: session.account)
      end

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'main', chdir: repository_path)
          .and_return([base_sha, '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'merge-tree', base_sha, anything, anything, chdir: repository_path)
          .and_raise(Errno::ENOENT, 'No such file or directory')
      end

      it 'handles the pair error gracefully and marks no conflict' do
        result = service.detect

        # The combination order depends on database ordering, so check both possible keys
        key_ab = "#{worktree_a.id}:#{worktree_b.id}"
        key_ba = "#{worktree_b.id}:#{worktree_a.id}"
        entry = result[:matrix][key_ab] || result[:matrix][key_ba]

        expect(entry).to be_present
        expect(entry[:has_conflicts]).to be false
        expect(entry[:error]).to be_present
      end
    end

    context 'when broadcast fails' do
      let!(:worktree_a) do
        create(:ai_worktree, :in_use,
               worktree_session: session,
               account: session.account)
      end
      let!(:worktree_b) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: session.account)
      end

      let(:conflict_output) do
        <<~OUTPUT
          changed in both
            our    100644 abc123 src/app.rb
            their  100644 def456 src/app.rb
        OUTPUT
      end

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'main', chdir: repository_path)
          .and_return([base_sha, '', success_status])
        allow(Open3).to receive(:capture3)
          .with('git', 'merge-tree', base_sha, anything, anything, chdir: repository_path)
          .and_return([conflict_output, '', failure_status])
        allow(AiOrchestrationChannel).to receive(:broadcast_worktree_session_event)
          .with(session, 'conflicts_detected', anything)
          .and_raise(StandardError, 'Redis down')
      end

      it 'still returns the conflict results' do
        result = service.detect

        expect(result[:conflicts].size).to eq(1)
        expect(result[:matrix]).to be_present
      end
    end
  end
end
