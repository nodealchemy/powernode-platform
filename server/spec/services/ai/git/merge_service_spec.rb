# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Git::MergeService, type: :service do
  let(:account) { create(:account) }
  let(:repository_path) { '/tmp/test_repo' }

  # Helper to build a successful status double
  def success_status
    instance_double(Process::Status, success?: true)
  end

  def failure_status
    instance_double(Process::Status, success?: false)
  end

  describe '#execute' do
    context 'with sequential strategy' do
      let!(:session) do
        create(:ai_worktree_session, :merging,
               account: account,
               repository_path: repository_path,
               base_branch: 'main',
               merge_strategy: 'sequential',
               total_worktrees: 2)
      end
      let!(:worktree1) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/abcd1234/task-1',
               completed_at: 10.minutes.ago)
      end
      let!(:worktree2) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/abcd1234/task-2',
               completed_at: 5.minutes.ago)
      end

      subject(:merge_service) { described_class.new(session: session) }

      context 'when all merges succeed' do
        let(:merge_sha1) { SecureRandom.hex(20) }
        let(:merge_sha2) { SecureRandom.hex(20) }

        before do
          # Merge worktree1
          allow(Open3).to receive(:capture3)
            .with('git', 'merge', '--no-ff', worktree1.branch_name, chdir: repository_path)
            .and_return(['', '', success_status])

          # Merge worktree2
          allow(Open3).to receive(:capture3)
            .with('git', 'merge', '--no-ff', worktree2.branch_name, chdir: repository_path)
            .and_return(['', '', success_status])

          # rev-parse after each merge
          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', 'HEAD', chdir: repository_path)
            .and_return(["#{merge_sha1}\n", '', success_status],
                        ["#{merge_sha2}\n", '', success_status])
        end

        it 'returns success' do
          result = merge_service.execute

          expect(result[:success]).to be true
          expect(result[:results].size).to eq(2)
          expect(result[:results].all? { |r| r[:status] == 'completed' }).to be true
        end

        it 'creates merge operations' do
          expect { merge_service.execute }.to change(Ai::MergeOperation, :count).by(2)
        end

        it 'marks worktrees as merged' do
          merge_service.execute

          expect(worktree1.reload.status).to eq('merged')
          expect(worktree2.reload.status).to eq('merged')
        end
      end

      context 'when a merge has a conflict' do
        before do
          # First merge conflicts
          allow(Open3).to receive(:capture3)
            .with('git', 'merge', '--no-ff', worktree1.branch_name, chdir: repository_path)
            .and_return(['', 'CONFLICT (content): Merge conflict in src/file.rb', failure_status])

          # diff --name-only for conflict files
          allow(Open3).to receive(:capture3)
            .with('git', 'diff', '--name-only', '--diff-filter=U', chdir: repository_path)
            .and_return(["src/file.rb\n", '', success_status])
        end

        it 'stops at the first conflict' do
          result = merge_service.execute

          expect(result[:success]).to be false
          expect(result[:results].size).to eq(1)
          expect(result[:results].first[:status]).to eq('conflict')
        end

        it 'does not attempt subsequent merges' do
          merge_service.execute

          # worktree2 should not have a merge operation
          expect(Ai::MergeOperation.where(worktree: worktree2).count).to eq(0)
        end
      end

      context 'when a merge fails with a non-conflict error' do
        before do
          # The first worktree by completed_at will be merged first
          allow(Open3).to receive(:capture3)
            .with('git', 'merge', '--no-ff', anything, chdir: repository_path)
            .and_return(['', 'fatal: unable to merge', failure_status])
        end

        it 'records the failure and stops' do
          result = merge_service.execute

          expect(result[:success]).to be false
          expect(result[:results].size).to eq(1)
          expect(result[:results].first[:status]).to eq('failed')
          expect(result[:results].first[:error]).to include('unable to merge')
        end
      end
    end

    context 'with integration_branch strategy' do
      let!(:session) do
        create(:ai_worktree_session, :merging,
               account: account,
               repository_path: repository_path,
               base_branch: 'main',
               merge_strategy: 'integration_branch',
               total_worktrees: 2)
      end
      let!(:worktree1) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/integ123/task-1',
               completed_at: 10.minutes.ago)
      end
      let!(:worktree2) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/integ123/task-2',
               completed_at: 5.minutes.ago)
      end

      subject(:merge_service) { described_class.new(session: session) }

      let(:integration_branch) { "integration/#{session.id.to_s[0..7]}" }
      let(:merge_sha) { SecureRandom.hex(20) }

      context 'when all merges succeed' do
        before do
          # Create integration branch
          allow(Open3).to receive(:capture3)
            .with('git', 'checkout', '-b', integration_branch, 'main', chdir: repository_path)
            .and_return(['', '', success_status])

          # Merge worktrees
          allow(Open3).to receive(:capture3)
            .with('git', 'merge', '--no-ff', worktree1.branch_name, chdir: repository_path)
            .and_return(['', '', success_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'merge', '--no-ff', worktree2.branch_name, chdir: repository_path)
            .and_return(['', '', success_status])

          # rev-parse HEAD
          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', 'HEAD', chdir: repository_path)
            .and_return(["#{merge_sha}\n", '', success_status])

          # Checkout back to base branch
          allow(Open3).to receive(:capture3)
            .with('git', 'checkout', 'main', chdir: repository_path)
            .and_return(['', '', success_status])
        end

        it 'returns success with integration branch' do
          result = merge_service.execute

          expect(result[:success]).to be true
          expect(result[:integration_branch]).to eq(integration_branch)
        end

        it 'updates the session integration_branch' do
          merge_service.execute

          expect(session.reload.integration_branch).to eq(integration_branch)
        end

        it 'marks worktrees as merged' do
          merge_service.execute

          expect(worktree1.reload.status).to eq('merged')
          expect(worktree2.reload.status).to eq('merged')
        end
      end

      context 'when a merge conflicts in integration mode' do
        before do
          allow(Open3).to receive(:capture3)
            .with('git', 'checkout', '-b', integration_branch, 'main', chdir: repository_path)
            .and_return(['', '', success_status])

          # First merge conflicts
          allow(Open3).to receive(:capture3)
            .with('git', 'merge', '--no-ff', worktree1.branch_name, chdir: repository_path)
            .and_return(['', 'CONFLICT (content): Merge conflict', failure_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'diff', '--name-only', '--diff-filter=U', chdir: repository_path)
            .and_return(["src/conflict.rb\n", '', success_status])

          # Abort this merge
          allow(Open3).to receive(:capture3)
            .with('git', 'merge', '--abort', chdir: repository_path)
            .and_return(['', '', success_status])

          # Continue to second merge
          allow(Open3).to receive(:capture3)
            .with('git', 'merge', '--no-ff', worktree2.branch_name, chdir: repository_path)
            .and_return(['', '', success_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', 'HEAD', chdir: repository_path)
            .and_return(["#{merge_sha}\n", '', success_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'checkout', 'main', chdir: repository_path)
            .and_return(['', '', success_status])
        end

        it 'continues past conflicts to merge other worktrees' do
          result = merge_service.execute

          expect(result[:results].size).to eq(2)
          expect(result[:results][0][:status]).to eq('conflict')
          expect(result[:results][1][:status]).to eq('completed')
        end

        it 'only marks non-conflicting worktrees as merged' do
          merge_service.execute

          expect(worktree1.reload.status).to eq('completed') # not merged due to conflict
          expect(worktree2.reload.status).to eq('merged')
        end
      end
    end

    context 'with manual strategy' do
      let!(:session) do
        create(:ai_worktree_session, :merging,
               account: account,
               repository_path: repository_path,
               base_branch: 'main',
               merge_strategy: 'manual',
               total_worktrees: 2)
      end
      let!(:worktree1) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/manual123/task-1',
               completed_at: 10.minutes.ago)
      end
      let!(:worktree2) do
        create(:ai_worktree, :completed,
               worktree_session: session,
               account: account,
               branch_name: 'worktree/manual123/task-2',
               completed_at: 5.minutes.ago)
      end

      subject(:merge_service) { described_class.new(session: session) }

      it 'creates pending merge operations without executing' do
        result = merge_service.execute

        expect(result[:success]).to be true
        expect(result[:manual]).to be true
        expect(result[:results].size).to eq(2)
        expect(result[:results].all? { |r| r[:status] == 'pending' }).to be true
      end

      it 'creates merge operation records' do
        expect { merge_service.execute }.to change(Ai::MergeOperation, :count).by(2)
      end

      it 'leaves merge operations in pending status' do
        merge_service.execute

        operations = session.merge_operations.reload
        expect(operations.all? { |op| op.status == 'pending' }).to be true
      end
    end

    context 'with unknown strategy' do
      let!(:session) do
        # Use build to bypass validation, then stub merge_strategy
        create(:ai_worktree_session, :merging,
               account: account,
               repository_path: repository_path,
               base_branch: 'main',
               total_worktrees: 1)
      end

      subject(:merge_service) { described_class.new(session: session) }

      it 'returns an error' do
        allow(session).to receive(:merge_strategy).and_return('unknown')

        result = merge_service.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include('Unknown merge strategy')
      end
    end
  end

  describe '#rollback' do
    let!(:session) do
      create(:ai_worktree_session, :merging,
             account: account,
             repository_path: repository_path,
             base_branch: 'main',
             total_worktrees: 1)
    end
    let!(:worktree) do
      create(:ai_worktree, :completed,
             worktree_session: session,
             account: account)
    end

    subject(:merge_service) { described_class.new(session: session) }

    context 'when rollback succeeds' do
      let(:merge_commit_sha) { SecureRandom.hex(20) }
      let(:revert_sha) { SecureRandom.hex(20) }
      let!(:operation) do
        create(:ai_merge_operation, :completed,
               worktree_session: session,
               worktree: worktree,
               account: account,
               merge_commit_sha: merge_commit_sha)
      end

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'revert', '-m', '1', '--no-edit', merge_commit_sha, chdir: repository_path)
          .and_return(['', '', success_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'HEAD', chdir: repository_path)
          .and_return(["#{revert_sha}\n", '', success_status])
      end

      it 'returns success with rollback SHA' do
        result = merge_service.rollback(merge_operation_id: operation.id)

        expect(result[:success]).to be true
        expect(result[:rollback_sha]).to eq(revert_sha)
      end

      it 'marks the operation as rolled back' do
        merge_service.rollback(merge_operation_id: operation.id)

        expect(operation.reload.status).to eq('rolled_back')
        expect(operation.rollback_commit_sha).to eq(revert_sha)
      end
    end

    context 'when rollback fails' do
      let(:merge_commit_sha) { SecureRandom.hex(20) }
      let!(:operation) do
        create(:ai_merge_operation, :completed,
               worktree_session: session,
               worktree: worktree,
               account: account,
               merge_commit_sha: merge_commit_sha)
      end

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'revert', '-m', '1', '--no-edit', merge_commit_sha, chdir: repository_path)
          .and_return(['', 'error: could not revert', failure_status])
      end

      it 'returns failure' do
        result = merge_service.rollback(merge_operation_id: operation.id)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Rollback failed')
      end
    end

    context 'when operation cannot be rolled back' do
      let!(:operation) do
        create(:ai_merge_operation,
               worktree_session: session,
               worktree: worktree,
               account: account,
               status: 'pending')
      end

      it 'returns an error' do
        result = merge_service.rollback(merge_operation_id: operation.id)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Cannot rollback')
      end
    end
  end

  describe '#execute with competitive mode' do
    let(:repository_path) { '/tmp/test_repo_competitive' }
    let!(:session) do
      create(:ai_worktree_session, :merging,
             account: account,
             repository_path: repository_path,
             base_branch: 'main',
             merge_strategy: 'sequential',
             execution_mode: 'competitive',
             total_worktrees: 3)
    end
    let!(:worktree1) do
      create(:ai_worktree, :completed,
             worktree_session: session,
             account: account,
             branch_name: 'worktree/comp1234/task-1',
             worktree_path: '/tmp/worktrees/comp/task-1',
             completed_at: 10.minutes.ago,
             duration_ms: 120_000,
             tokens_used: 5000,
             commit_count: 3,
             test_status: 'passed')
    end
    let!(:worktree2) do
      create(:ai_worktree, :completed,
             worktree_session: session,
             account: account,
             branch_name: 'worktree/comp1234/task-2',
             worktree_path: '/tmp/worktrees/comp/task-2',
             completed_at: 5.minutes.ago,
             duration_ms: 300_000,
             tokens_used: 15000,
             commit_count: 8,
             test_status: nil)
    end
    let!(:worktree3) do
      create(:ai_worktree, :completed,
             worktree_session: session,
             account: account,
             branch_name: 'worktree/comp1234/task-3',
             worktree_path: '/tmp/worktrees/comp/task-3',
             completed_at: 2.minutes.ago,
             duration_ms: 60_000,
             tokens_used: 3000,
             commit_count: 2,
             test_status: 'failed')
    end

    let(:manager) { instance_double(Ai::Git::WorktreeManager) }

    subject(:merge_service) { described_class.new(session: session) }

    before do
      allow(Ai::Git::WorktreeManager).to receive(:new).and_return(manager)

      # diff_stats for each worktree
      allow(manager).to receive(:diff_stats)
        .with(worktree_path: worktree1.worktree_path, base_branch: 'main')
        .and_return({ files_changed: 3, lines_added: 80, lines_removed: 10 })

      allow(manager).to receive(:diff_stats)
        .with(worktree_path: worktree2.worktree_path, base_branch: 'main')
        .and_return({ files_changed: 10, lines_added: 500, lines_removed: 200 })

      allow(manager).to receive(:diff_stats)
        .with(worktree_path: worktree3.worktree_path, base_branch: 'main')
        .and_return({ files_changed: 2, lines_added: 40, lines_removed: 5 })

      # health_check for each worktree
      allow(manager).to receive(:health_check)
        .with(worktree_path: worktree1.worktree_path)
        .and_return({ healthy: true, dirty: false })

      allow(manager).to receive(:health_check)
        .with(worktree_path: worktree2.worktree_path)
        .and_return({ healthy: true, dirty: true })

      allow(manager).to receive(:health_check)
        .with(worktree_path: worktree3.worktree_path)
        .and_return({ healthy: true, dirty: false })
    end

    context 'when the winning worktree merges successfully' do
      let(:merge_sha) { SecureRandom.hex(20) }

      before do
        # worktree1 should win (passed tests + healthy + low tokens)
        allow(Open3).to receive(:capture3)
          .with('git', 'merge', '--no-ff', worktree1.branch_name, chdir: repository_path)
          .and_return(['', '', success_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'HEAD', chdir: repository_path)
          .and_return(["#{merge_sha}\n", '', success_status])
      end

      it 'returns success with competitive flag' do
        result = merge_service.execute

        expect(result[:success]).to be true
        expect(result[:competitive]).to be true
      end

      it 'selects the worktree with the best score as winner' do
        result = merge_service.execute

        expect(result[:winner][:worktree_id]).to eq(worktree1.id)
      end

      it 'only merges the winning worktree' do
        result = merge_service.execute

        expect(result[:results].size).to eq(1)
        expect(result[:results].first[:status]).to eq('completed')
      end

      it 'marks only the winner as merged' do
        merge_service.execute

        expect(worktree1.reload.status).to eq('merged')
        expect(worktree2.reload.status).to eq('completed')
        expect(worktree3.reload.status).to eq('completed')
      end

      it 'stores competition evaluations in session metadata' do
        merge_service.execute

        session.reload
        expect(session.metadata['competition_evaluations']).to be_present
        expect(session.metadata['competition_evaluations'].size).to eq(3)
        expect(session.metadata['winner_worktree_id']).to eq(worktree1.id)
      end

      it 'includes evaluations with diff stats and health info' do
        result = merge_service.execute

        evaluations = result[:evaluations]
        expect(evaluations.size).to eq(3)

        wt1_eval = evaluations.find { |e| e[:worktree_id] == worktree1.id }
        expect(wt1_eval[:files_changed]).to eq(3)
        expect(wt1_eval[:lines_added]).to eq(80)
        expect(wt1_eval[:healthy]).to be true
        expect(wt1_eval[:test_status]).to eq('passed')
      end

      it 'creates a single merge operation' do
        expect { merge_service.execute }.to change(Ai::MergeOperation, :count).by(1)
      end
    end

    context 'when the winning worktree merge conflicts' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'merge', '--no-ff', worktree1.branch_name, chdir: repository_path)
          .and_return(['', 'CONFLICT (content): Merge conflict in src/main.rb', failure_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'diff', '--name-only', '--diff-filter=U', chdir: repository_path)
          .and_return(["src/main.rb\n", '', success_status])
      end

      it 'returns failure' do
        result = merge_service.execute

        expect(result[:success]).to be false
        expect(result[:results].first[:status]).to eq('conflict')
      end
    end

    context 'when no completed worktrees exist' do
      before do
        session.worktrees.update_all(status: 'failed')
      end

      it 'returns an error' do
        result = merge_service.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include('No completed worktrees')
      end
    end

    context 'scoring priorities' do
      let(:merge_sha) { SecureRandom.hex(20) }

      it 'prefers passed tests over health and speed' do
        # worktree1 has passed tests, worktree3 has lower tokens but failed tests
        allow(Open3).to receive(:capture3)
          .with('git', 'merge', '--no-ff', worktree1.branch_name, chdir: repository_path)
          .and_return(['', '', success_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'HEAD', chdir: repository_path)
          .and_return(["#{merge_sha}\n", '', success_status])

        result = merge_service.execute

        # worktree1 should still win despite worktree3 using fewer tokens,
        # because passed tests (+100) outweighs the token penalty difference
        expect(result[:winner][:worktree_id]).to eq(worktree1.id)
      end
    end
  end
end
