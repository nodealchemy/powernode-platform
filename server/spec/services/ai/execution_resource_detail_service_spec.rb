# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ExecutionResourceDetailService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  describe '#fetch' do
    context 'with unknown resource type' do
      it 'returns nil' do
        expect(service.fetch("unknown_type", SecureRandom.uuid)).to be_nil
      end
    end

    context 'artifact resource type' do
      let(:task) do
        double('a2a_task',
          id: SecureRandom.uuid,
          task_id: "task-123",
          status: "completed",
          created_at: Time.current,
          artifacts: [{ "name" => "output.txt", "parts" => [{ "text" => "content here" }], "mime_type" => "text/plain" }],
          input: { "text" => "input" },
          output: { "text" => "output" },
          history: [],
          cost: 0.05,
          tokens_used: 500,
          duration_ms: 1200,
          error_message: nil,
          error_code: nil,
          error_details: nil,
          started_at: 1.minute.ago,
          completed_at: Time.current,
          from_agent: double('from_agent', name: "Agent A"),
          to_agent: double('to_agent', name: "Agent B"),
          subtasks: double('subtasks', count: 2),
          retry_count: 0,
          max_retries: 3,
          sequence_number: 1,
          is_external: false,
          metadata: {}
        )
      end

      before do
        relation = double('relation')
        allow(Ai::A2aTask).to receive(:where).with(account: account).and_return(relation)
        allow(relation).to receive(:find).with(task.id).and_return(task)
      end

      it 'serializes artifact details' do
        result = service.fetch("artifact", task.id)

        expect(result[:resource_type]).to eq("artifact")
        expect(result[:name]).to eq("output.txt")
        expect(result[:status]).to eq("completed")
        expect(result[:from_agent_name]).to eq("Agent A")
        expect(result[:to_agent_name]).to eq("Agent B")
        expect(result[:subtasks_count]).to eq(2)
      end
    end

    context 'execution_output resource type' do
      let(:team) { create(:ai_agent_team, account: account) }
      let(:execution) do
        create(:ai_team_execution, account: account, agent_team: team,
               status: "completed", objective: "Test objective")
      end

      it 'serializes team execution details' do
        result = service.fetch("execution_output", execution.id)

        expect(result[:resource_type]).to eq("execution_output")
        expect(result[:status]).to eq("completed")
        expect(result[:objective]).to eq("Test objective")
        expect(result[:team_name]).to eq(team.name)
      end
    end

    context 'trajectory resource type' do
      let(:trajectory) do
        create(:ai_trajectory, account: account, title: "Test Trajectory",
               trajectory_type: "task_completion", status: "completed")
      end

      it 'serializes trajectory details with chapters' do
        result = service.fetch("trajectory", trajectory.id)

        expect(result[:resource_type]).to eq("trajectory")
        expect(result[:name]).to eq("Test Trajectory")
        expect(result[:trajectory_type]).to eq("task_completion")
        expect(result[:chapters]).to be_an(Array)
      end
    end

    context 'review resource type' do
      let(:task_review) do
        create(:ai_task_review, account: account, review_mode: "blocking",
               status: "approved", quality_score: 0.9)
      end

      it 'serializes review details' do
        result = service.fetch("review", task_review.id)

        expect(result[:resource_type]).to eq("review")
        expect(result[:review_mode]).to eq("blocking")
        expect(result[:quality_score]).to eq(0.9)
      end
    end

    context 'shared_memory resource type' do
      let(:memory_pool) do
        create(:ai_memory_pool, account: account, name: "Test Pool",
               pool_type: "shared", scope: "persistent")
      end

      it 'serializes memory pool details' do
        result = service.fetch("shared_memory", memory_pool.id)

        expect(result[:resource_type]).to eq("shared_memory")
        expect(result[:name]).to eq("Test Pool")
        expect(result[:pool_type]).to eq("shared")
        expect(result[:scope]).to eq("persistent")
      end
    end

    context 'git_branch resource type' do
      let(:worktree) do
        double('worktree',
          id: SecureRandom.uuid,
          branch_name: "feature/test",
          status: "active",
          created_at: Time.current,
          head_commit_sha: "abc123",
          files_changed: 5,
          lines_added: 100,
          lines_removed: 20,
          agent_name: "Test Agent",
          base_commit_sha: "def456",
          commit_count: 3,
          disk_usage_bytes: 1024,
          healthy: true,
          health_message: nil,
          locked: false,
          lock_reason: nil,
          worktree_path: "/tmp/worktree",
          ready_at: Time.current,
          completed_at: nil,
          duration_ms: nil,
          error_message: nil,
          error_code: nil,
          metadata: {}
        )
      end

      before do
        allow(worktree).to receive(:respond_to?).and_return(true)
        allow(worktree).to receive(:respond_to?).with(:test_status).and_return(false)
        allow(worktree).to receive(:respond_to?).with(:tokens_used).and_return(false)
        allow(worktree).to receive(:respond_to?).with(:estimated_cost_cents).and_return(false)
        allow(worktree).to receive(:respond_to?).with(:timeout_at).and_return(false)

        join_relation = double('join_relation')
        allow(Ai::Worktree).to receive(:joins).with(:worktree_session).and_return(join_relation)
        allow(join_relation).to receive(:where).and_return(join_relation)
        allow(join_relation).to receive(:find).with(worktree.id).and_return(worktree)
      end

      it 'serializes git branch details' do
        result = service.fetch("git_branch", worktree.id)

        expect(result[:resource_type]).to eq("git_branch")
        expect(result[:branch_name]).to eq("feature/test")
        expect(result[:commit_sha]).to eq("abc123")
        expect(result[:files_changed]).to eq(5)
      end
    end

    context 'git_merge resource type' do
      let(:merge_op) do
        double('merge_operation',
          id: SecureRandom.uuid,
          source_branch: "feature/test",
          target_branch: "main",
          strategy: "merge",
          status: "completed",
          created_at: Time.current,
          merge_commit_sha: "abc123",
          merge_order: 1,
          has_conflicts: false,
          conflict_files: [],
          conflict_details: nil,
          conflict_resolution: nil,
          pull_request_url: "https://github.com/repo/pull/1",
          pull_request_id: 1,
          pull_request_status: "merged",
          rollback_commit_sha: nil,
          rolled_back: false,
          rolled_back_at: nil,
          started_at: 1.minute.ago,
          completed_at: Time.current,
          duration_ms: 5000,
          error_message: nil,
          error_code: nil,
          metadata: {}
        )
      end

      before do
        join_relation = double('join_relation')
        allow(Ai::MergeOperation).to receive(:joins).with(:worktree_session).and_return(join_relation)
        allow(join_relation).to receive(:where).and_return(join_relation)
        allow(join_relation).to receive(:find).with(merge_op.id).and_return(merge_op)
      end

      it 'serializes git merge details' do
        result = service.fetch("git_merge", merge_op.id)

        expect(result[:resource_type]).to eq("git_merge")
        expect(result[:name]).to eq("feature/test \u2192 main")
        expect(result[:strategy]).to eq("merge")
      end
    end

    context 'runner_job resource type' do
      let(:dispatch) do
        double('runner_dispatch',
          id: SecureRandom.uuid,
          status: "completed",
          created_at: Time.current,
          git_runner: double('runner', name: "Runner 1"),
          git_repository: double('repo', name: "my-repo"),
          worktree: double('worktree', branch_name: "feature/x"),
          workflow_run_id: "run-123",
          workflow_url: "https://github.com/repo/actions/runs/123",
          input_params: {},
          output_result: {},
          logs: "Build succeeded",
          runner_labels: ["ubuntu"],
          dispatched_at: 2.minutes.ago,
          completed_at: Time.current,
          duration_ms: 60000
        )
      end

      before do
        relation = double('relation')
        allow(Ai::RunnerDispatch).to receive(:where).with(account: account).and_return(relation)
        allow(relation).to receive(:find).with(dispatch.id).and_return(dispatch)
      end

      it 'serializes runner job details' do
        result = service.fetch("runner_job", dispatch.id)

        expect(result[:resource_type]).to eq("runner_job")
        expect(result[:runner_name]).to eq("Runner 1")
        expect(result[:repository_name]).to eq("my-repo")
        expect(result[:worktree_branch]).to eq("feature/x")
      end
    end
  end
end
