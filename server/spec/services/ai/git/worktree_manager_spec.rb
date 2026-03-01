# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Git::WorktreeManager, type: :service do
  let(:repository_path) { '/tmp/test_repo' }

  subject(:manager) { described_class.new(repository_path: repository_path) }

  # Helper to build a successful status double
  def success_status
    instance_double(Process::Status, success?: true)
  end

  def failure_status
    instance_double(Process::Status, success?: false)
  end

  describe '#initialize' do
    it 'sets the repository_path' do
      expect(manager.repository_path).to eq(repository_path)
    end
  end

  describe '#create_worktree' do
    let(:session_id) { SecureRandom.uuid }
    let(:short_id) { session_id[0..7] }
    let(:branch_suffix) { 'feature-auth' }
    let(:expected_branch) { "worktree/#{short_id}/#{branch_suffix}" }
    let(:expected_path) { File.join(repository_path, 'tmp/worktrees', short_id, branch_suffix) }
    let(:base_sha) { SecureRandom.hex(20) }

    before do
      allow(File).to receive(:exist?).and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
      allow(FileUtils).to receive(:cp)
    end

    context 'when creation succeeds' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'add', '-b', expected_branch, expected_path, 'main', chdir: repository_path)
          .and_return(['', '', success_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'main', chdir: repository_path)
          .and_return(["#{base_sha}\n", '', success_status])
      end

      it 'returns worktree details' do
        result = manager.create_worktree(session_id: session_id, branch_suffix: branch_suffix)

        expect(result[:branch_name]).to eq(expected_branch)
        expect(result[:worktree_path]).to eq(expected_path)
        expect(result[:base_commit_sha]).to eq(base_sha)
        expect(result[:copied_config_files]).to be_an(Array)
      end

      it 'creates the parent directory' do
        manager.create_worktree(session_id: session_id, branch_suffix: branch_suffix)

        expect(FileUtils).to have_received(:mkdir_p).with(File.dirname(expected_path))
      end
    end

    context 'when using a base_commit instead of base_branch' do
      let(:commit_sha) { SecureRandom.hex(20) }

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'add', '-b', expected_branch, expected_path, commit_sha, chdir: repository_path)
          .and_return(['', '', success_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', commit_sha, chdir: repository_path)
          .and_return(["#{commit_sha}\n", '', success_status])
      end

      it 'uses base_commit as start point' do
        result = manager.create_worktree(
          session_id: session_id, branch_suffix: branch_suffix, base_commit: commit_sha
        )

        expect(result[:base_commit_sha]).to eq(commit_sha)
      end
    end

    context 'when the branch already exists' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'add', '-b', expected_branch, expected_path, 'main', chdir: repository_path)
          .and_return(['', "fatal: a branch named '#{expected_branch}' already exists", failure_status])
      end

      it 'raises BranchExistsError' do
        expect {
          manager.create_worktree(session_id: session_id, branch_suffix: branch_suffix)
        }.to raise_error(Ai::Git::WorktreeManager::BranchExistsError, /already exists/)
      end
    end

    context 'when the path already exists' do
      before do
        allow(File).to receive(:exist?).with(expected_path).and_return(true)
      end

      it 'raises PathExistsError' do
        expect {
          manager.create_worktree(session_id: session_id, branch_suffix: branch_suffix)
        }.to raise_error(Ai::Git::WorktreeManager::PathExistsError, /already exists/)
      end
    end

    context 'when git command fails with a generic error' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'add', '-b', expected_branch, expected_path, 'main', chdir: repository_path)
          .and_return(['', 'fatal: some other error', failure_status])
      end

      it 'raises WorktreeError' do
        expect {
          manager.create_worktree(session_id: session_id, branch_suffix: branch_suffix)
        }.to raise_error(Ai::Git::WorktreeManager::WorktreeError, /Failed to create worktree/)
      end
    end

    context 'when config files exist' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'add', '-b', expected_branch, expected_path, 'main', chdir: repository_path)
          .and_return(['', '', success_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'main', chdir: repository_path)
          .and_return(["#{base_sha}\n", '', success_status])

        # Only .env exists in the source repo
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(expected_path).and_return(false)
        allow(File).to receive(:exist?).with(File.join(repository_path, '.env')).and_return(true)
        allow(File).to receive(:exist?).with(File.join(repository_path, '.env.local')).and_return(false)
        allow(File).to receive(:exist?).with(File.join(repository_path, '.tool-versions')).and_return(false)
        allow(File).to receive(:exist?).with(File.join(repository_path, '.ruby-version')).and_return(true)
        allow(File).to receive(:exist?).with(File.join(repository_path, '.node-version')).and_return(false)
      end

      it 'copies existing config files' do
        result = manager.create_worktree(session_id: session_id, branch_suffix: branch_suffix)

        expect(result[:copied_config_files]).to contain_exactly('.env', '.ruby-version')
        expect(FileUtils).to have_received(:cp).twice
      end
    end
  end

  describe '#remove_worktree' do
    let(:worktree_path) { '/tmp/test_repo/tmp/worktrees/abcd1234/task-1' }
    let(:branch_name) { 'worktree/abcd1234/task-1' }

    context 'when removal succeeds' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'remove', worktree_path, chdir: repository_path)
          .and_return(['', '', success_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'branch', '-D', branch_name, chdir: repository_path)
          .and_return(['', '', success_status])
      end

      it 'returns true' do
        result = manager.remove_worktree(worktree_path: worktree_path, branch_name: branch_name)
        expect(result).to be true
      end

      it 'deletes the branch when branch_name is provided' do
        manager.remove_worktree(worktree_path: worktree_path, branch_name: branch_name)

        expect(Open3).to have_received(:capture3)
          .with('git', 'branch', '-D', branch_name, chdir: repository_path)
      end
    end

    context 'when removal succeeds without branch deletion' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'remove', worktree_path, chdir: repository_path)
          .and_return(['', '', success_status])
      end

      it 'does not delete any branch' do
        manager.remove_worktree(worktree_path: worktree_path)

        expect(Open3).not_to have_received(:capture3)
          .with('git', 'branch', '-D', anything, chdir: repository_path)
      end
    end

    context 'when removal fails without force' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'remove', worktree_path, chdir: repository_path)
          .and_return(['', 'error: dirty worktree', failure_status])
      end

      it 'raises WorktreeError' do
        expect {
          manager.remove_worktree(worktree_path: worktree_path)
        }.to raise_error(Ai::Git::WorktreeManager::WorktreeError, /Failed to remove worktree/)
      end
    end

    context 'when force removal fails and falls back to rm_rf' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'remove', '--force', worktree_path, chdir: repository_path)
          .and_return(['', 'error: cannot remove', failure_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'prune', chdir: repository_path)
          .and_return(['', '', success_status])

        allow(File).to receive(:exist?).with(worktree_path).and_return(true)
        allow(FileUtils).to receive(:rm_rf)
      end

      it 'removes the directory and prunes' do
        manager.remove_worktree(worktree_path: worktree_path, force: true)

        expect(FileUtils).to have_received(:rm_rf).with(worktree_path)
        expect(Open3).to have_received(:capture3)
          .with('git', 'worktree', 'prune', chdir: repository_path)
      end
    end
  end

  describe '#lock_worktree' do
    let(:worktree_path) { '/tmp/test_repo/tmp/worktrees/abcd1234/task-1' }

    context 'when locking succeeds' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'lock', worktree_path, chdir: repository_path)
          .and_return(['', '', success_status])
      end

      it 'returns true' do
        result = manager.lock_worktree(worktree_path: worktree_path)
        expect(result).to be true
      end
    end

    context 'when locking with a reason' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'lock', worktree_path, '--reason', 'provisioning', chdir: repository_path)
          .and_return(['', '', success_status])
      end

      it 'passes the reason to git' do
        manager.lock_worktree(worktree_path: worktree_path, reason: 'provisioning')

        expect(Open3).to have_received(:capture3)
          .with('git', 'worktree', 'lock', worktree_path, '--reason', 'provisioning', chdir: repository_path)
      end
    end

    context 'when locking fails' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'lock', worktree_path, chdir: repository_path)
          .and_return(['', 'error: already locked', failure_status])
      end

      it 'raises WorktreeError' do
        expect {
          manager.lock_worktree(worktree_path: worktree_path)
        }.to raise_error(Ai::Git::WorktreeManager::WorktreeError, /Failed to lock worktree/)
      end
    end
  end

  describe '#unlock_worktree' do
    let(:worktree_path) { '/tmp/test_repo/tmp/worktrees/abcd1234/task-1' }

    context 'when unlocking succeeds' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'unlock', worktree_path, chdir: repository_path)
          .and_return(['', '', success_status])
      end

      it 'returns true' do
        result = manager.unlock_worktree(worktree_path: worktree_path)
        expect(result).to be true
      end
    end

    context 'when unlocking fails' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'unlock', worktree_path, chdir: repository_path)
          .and_return(['', 'error: not locked', failure_status])
      end

      it 'raises WorktreeError' do
        expect {
          manager.unlock_worktree(worktree_path: worktree_path)
        }.to raise_error(Ai::Git::WorktreeManager::WorktreeError, /Failed to unlock worktree/)
      end
    end
  end

  describe '#health_check' do
    let(:worktree_path) { '/tmp/test_repo/tmp/worktrees/abcd1234/task-1' }
    let(:head_sha) { SecureRandom.hex(20) }

    context 'when worktree is healthy with no dirty files' do
      before do
        allow(File).to receive(:exist?).with(worktree_path).and_return(true)

        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'HEAD', chdir: worktree_path)
          .and_return(["#{head_sha}\n", '', success_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'status', '--porcelain', chdir: worktree_path)
          .and_return(['', '', success_status])
      end

      it 'returns healthy status' do
        result = manager.health_check(worktree_path: worktree_path)

        expect(result[:healthy]).to be true
        expect(result[:head_sha]).to eq(head_sha)
        expect(result[:dirty]).to be false
        expect(result[:dirty_files]).to be_empty
      end
    end

    context 'when worktree has dirty files' do
      before do
        allow(File).to receive(:exist?).with(worktree_path).and_return(true)

        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'HEAD', chdir: worktree_path)
          .and_return(["#{head_sha}\n", '', success_status])

        allow(Open3).to receive(:capture3)
          .with('git', 'status', '--porcelain', chdir: worktree_path)
          .and_return([" M src/file.rb\n?? new_file.rb\n", '', success_status])
      end

      it 'returns dirty status' do
        result = manager.health_check(worktree_path: worktree_path)

        expect(result[:healthy]).to be true
        expect(result[:dirty]).to be true
        expect(result[:dirty_files]).to contain_exactly('M src/file.rb', '?? new_file.rb')
      end
    end

    context 'when worktree path does not exist' do
      before do
        allow(File).to receive(:exist?).with(worktree_path).and_return(false)
      end

      it 'returns unhealthy status' do
        result = manager.health_check(worktree_path: worktree_path)

        expect(result[:healthy]).to be false
        expect(result[:health_message]).to eq('Path does not exist')
      end
    end

    context 'when git command fails' do
      before do
        allow(File).to receive(:exist?).with(worktree_path).and_return(true)

        allow(Open3).to receive(:capture3)
          .with('git', 'rev-parse', 'HEAD', chdir: worktree_path)
          .and_return(['', 'fatal: not a git repository', failure_status])
      end

      it 'returns unhealthy with error message' do
        result = manager.health_check(worktree_path: worktree_path)

        expect(result[:healthy]).to be false
        expect(result[:health_message]).to be_present
      end
    end
  end

  describe '#diff_stats' do
    let(:worktree_path) { '/tmp/test_repo/tmp/worktrees/abcd1234/task-1' }
    let(:base_branch) { 'main' }

    context 'with changes' do
      let(:diff_output) do
        <<~OUTPUT
           src/models/user.rb | 15 +++++++--------
           src/routes.rb      | 22 ++++++++++++++++------
           2 files changed, 17 insertions(+), 14 deletions(-)
        OUTPUT
      end

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'diff', '--stat', "#{base_branch}...HEAD", chdir: worktree_path)
          .and_return([diff_output, '', success_status])
      end

      it 'parses the stat output' do
        result = manager.diff_stats(worktree_path: worktree_path, base_branch: base_branch)

        expect(result[:files_changed]).to eq(2)
        expect(result[:lines_added]).to eq(17)
        expect(result[:lines_removed]).to eq(14)
      end
    end

    context 'with insertions only' do
      let(:diff_output) { " 1 file changed, 10 insertions(+)\n" }

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'diff', '--stat', "#{base_branch}...HEAD", chdir: worktree_path)
          .and_return([diff_output, '', success_status])
      end

      it 'parses insertions only' do
        result = manager.diff_stats(worktree_path: worktree_path, base_branch: base_branch)

        expect(result[:files_changed]).to eq(1)
        expect(result[:lines_added]).to eq(10)
        expect(result[:lines_removed]).to eq(0)
      end
    end

    context 'with no changes' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'diff', '--stat', "#{base_branch}...HEAD", chdir: worktree_path)
          .and_return(['', '', success_status])
      end

      it 'returns zeros' do
        result = manager.diff_stats(worktree_path: worktree_path, base_branch: base_branch)

        expect(result[:files_changed]).to eq(0)
        expect(result[:lines_added]).to eq(0)
        expect(result[:lines_removed]).to eq(0)
      end
    end

    context 'when git command fails' do
      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'diff', '--stat', "#{base_branch}...HEAD", chdir: worktree_path)
          .and_return(['', 'fatal: bad revision', failure_status])
      end

      it 'returns zeros' do
        result = manager.diff_stats(worktree_path: worktree_path, base_branch: base_branch)

        expect(result[:files_changed]).to eq(0)
        expect(result[:lines_added]).to eq(0)
        expect(result[:lines_removed]).to eq(0)
      end
    end
  end

  describe '#list_worktrees' do
    context 'with multiple worktrees' do
      let(:porcelain_output) do
        <<~OUTPUT
          worktree /tmp/test_repo
          HEAD abc123def456
          branch refs/heads/main

          worktree /tmp/test_repo/tmp/worktrees/abcd1234/task-1
          HEAD def456abc789
          branch refs/heads/worktree/abcd1234/task-1

          worktree /tmp/test_repo/tmp/worktrees/abcd1234/task-2
          HEAD 789abc123def
          branch refs/heads/worktree/abcd1234/task-2
          locked provisioning

        OUTPUT
      end

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'list', '--porcelain', chdir: repository_path)
          .and_return([porcelain_output, '', success_status])
      end

      it 'parses all worktrees' do
        result = manager.list_worktrees
        expect(result.size).to eq(3)
      end

      it 'parses worktree paths' do
        result = manager.list_worktrees
        expect(result[0][:worktree]).to eq('/tmp/test_repo')
        expect(result[1][:worktree]).to eq('/tmp/test_repo/tmp/worktrees/abcd1234/task-1')
      end

      it 'parses HEAD and branch' do
        result = manager.list_worktrees
        expect(result[0][:head]).to eq('abc123def456')
        expect(result[0][:branch]).to eq('refs/heads/main')
      end

      it 'parses locked state' do
        result = manager.list_worktrees
        expect(result[2][:locked]).to be true
      end
    end

    context 'with bare and detached worktrees' do
      let(:porcelain_output) do
        <<~OUTPUT
          worktree /tmp/bare_repo
          HEAD abc123
          bare

          worktree /tmp/bare_repo/wt
          HEAD def456
          detached

        OUTPUT
      end

      before do
        allow(Open3).to receive(:capture3)
          .with('git', 'worktree', 'list', '--porcelain', chdir: repository_path)
          .and_return([porcelain_output, '', success_status])
      end

      it 'parses bare flag' do
        result = manager.list_worktrees
        expect(result[0][:bare]).to be true
      end

      it 'parses detached flag' do
        result = manager.list_worktrees
        expect(result[1][:detached]).to be true
      end
    end
  end

  describe '#prune' do
    it 'runs git worktree prune' do
      allow(Open3).to receive(:capture3)
        .with('git', 'worktree', 'prune', chdir: repository_path)
        .and_return(['', '', success_status])

      manager.prune

      expect(Open3).to have_received(:capture3)
        .with('git', 'worktree', 'prune', chdir: repository_path)
    end
  end
end
