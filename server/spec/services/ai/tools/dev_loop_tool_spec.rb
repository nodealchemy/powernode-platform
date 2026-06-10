# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::DevLoopTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "dev-audit-test") }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("dev_loop")
      expect(defn[:parameters][:action][:required]).to be true
    end

    it "exposes both bridge actions" do
      expect(described_class.action_definitions.keys)
        .to contain_exactly("dev_next_task", "dev_complete_task")
    end
  end

  describe ".permitted?" do
    it "requires ai.agents.update permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.update")
    end
  end

  describe "dev_next_task" do
    it "claims the highest-priority pending task and starts the loop" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "low", priority: 1)
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "high", priority: 20)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name })

      expect(result[:success]).to be true
      expect(result[:task][:task_key]).to eq("high")
      task = ralph_loop.ralph_tasks.find_by(task_key: "high")
      expect(task.status).to eq("in_progress")
      expect(task.execution_attempts).to eq(1)
      expect(task.metadata["claimed_by"]).to eq("user:#{user.id}")
      expect(ralph_loop.reload.status).to eq("running")
    end

    it "is idempotent — re-claiming returns the same in-progress task" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "only")

      first = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
      second = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(first[:reclaimed]).to be false
      expect(second[:reclaimed]).to be true
      expect(second[:task][:task_key]).to eq("only")
      expect(ralph_loop.ralph_tasks.in_progress.count).to eq(1)
    end

    it "never hands out human-decision tasks" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "decision",
                             execution_type: "human", priority: 50)
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "code-fix", priority: 1)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:task][:task_key]).to eq("code-fix")
    end

    it "skips tasks whose dependencies are unsatisfied" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "first", priority: 1)
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "second",
                             priority: 20, dependencies: ["first"])

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:task][:task_key]).to eq("first")
    end

    it "reports an empty queue when nothing is claimable" do
      create(:ai_ralph_task, :passed, ralph_loop: ralph_loop)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:success]).to be true
      expect(result[:queue_empty]).to be true
      expect(result[:task]).to be_nil
    end

    it "includes loop guardrails and spec path from configuration" do
      ralph_loop.update!(configuration: {
        "loop_spec_path" => ".claude/loops/dev-audit/PROMPT.md",
        "guardrails" => ["one task per iteration"]
      })
      create(:ai_ralph_task, ralph_loop: ralph_loop)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:loop][:loop_spec_path]).to eq(".claude/loops/dev-audit/PROMPT.md")
      expect(result[:loop][:guardrails]).to eq(["one task per iteration"])
    end

    context "halt conditions" do
      before { create(:ai_ralph_task, ralph_loop: ralph_loop) }

      it "refuses to hand out tasks during an emergency halt" do
        account.suspend_ai!

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("emergency_halt")
        expect(result[:task]).to be_nil
      end

      it "refuses when the loop schedule is paused" do
        ralph_loop.update!(schedule_paused: true)

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("schedule_paused")
      end

      it "refuses when the loop is in a paused state" do
        ralph_loop.update!(status: "running")
        ralph_loop.pause!

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("loop_paused")
      end

      it "refuses when max iterations are reached" do
        ralph_loop.update!(max_iterations: 2, current_iteration: 2)

        result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

        expect(result[:halted]).to be true
        expect(result[:reason]).to eq("max_iterations_reached")
      end
    end

    it "returns an error for an unknown loop" do
      result = tool.execute(params: { action: "dev_next_task", loop_id: "nope" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/)
    end
  end

  describe "dev_complete_task" do
    let!(:task) do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "F9-99")
    end

    before do
      ralph_loop.update!(status: "running", started_at: Time.current)
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
    end

    it "records a passed outcome with iteration evidence and learning" do
      result = tool.execute(params: {
        action: "dev_complete_task",
        loop_id: ralph_loop.id,
        task_key: "F9-99",
        outcome: "passed",
        summary: "Fixed the gate enum and added a regression spec",
        check_results: { "rspec" => "2 examples, 0 failures" },
        files_changed: ["server/app/models/ai/mission_approval.rb"],
        git_branch: "dev-loop/dev-audit",
        commit_sha: "abc1234",
        learning: "Template-defined gates must be in the parent GATES enum"
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("passed")

      iteration = ralph_loop.ralph_iterations.last
      expect(iteration.status).to eq("completed")
      expect(iteration.checks_passed).to be true
      expect(iteration.git_branch).to eq("dev-loop/dev-audit")
      expect(iteration.git_commit_sha).to eq("abc1234")
      expect(iteration.check_results["rspec"]).to eq("2 examples, 0 failures")
      expect(iteration.check_results["files_changed"]).to include("server/app/models/ai/mission_approval.rb")
      expect(iteration.learning_extracted).to match(/GATES enum/)
      expect(ralph_loop.reload.learnings.last["text"]).to match(/GATES enum/)
      expect(result[:queue][:passed]).to eq(1)
    end

    it "records a failed outcome and still captures the learning" do
      result = tool.execute(params: {
        action: "dev_complete_task",
        loop_id: ralph_loop.id,
        task_key: "F9-99",
        outcome: "failed",
        summary: "Spec still red after 3 attempts",
        learning: "This area needs the worker running to reproduce"
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("failed")
      expect(ralph_loop.ralph_iterations.last.status).to eq("failed")
      expect(ralph_loop.reload.learnings.last["text"]).to match(/worker running/)
    end

    it "records a blocked outcome with a blocked error code" do
      result = tool.execute(params: {
        action: "dev_complete_task",
        loop_id: ralph_loop.id,
        task_key: "F9-99",
        outcome: "blocked",
        summary: "Needs an architecture decision on the act-arc"
      })

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("blocked")
      expect(ralph_loop.ralph_iterations.last.error_code).to eq("blocked")
    end

    it "rejects completion of a task that was never claimed" do
      create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "unclaimed")

      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "unclaimed", outcome: "passed", summary: "nope"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not in_progress/)
    end

    it "rejects an invalid outcome" do
      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "F9-99", outcome: "shipped", summary: "done"
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/Invalid outcome/)
    end

    it "requires a summary" do
      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id,
        task_key: "F9-99", outcome: "passed", summary: ""
      })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/summary/)
    end
  end

  describe "context requirements" do
    it "requires a user or agent claimant" do
      anonymous = described_class.new(account: account)

      result = anonymous.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/context required/)
    end
  end
end
