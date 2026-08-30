# frozen_string_literal: true

require "rails_helper"

# IMP-f573eb10a99f — claiming a SPECIFIC task, and recording work that was
# finished out of band.
#
# The failure this covers: an executor is handed a task by name (not by queue
# position), does the work, commits it, and then has no way to record it. The
# positional claim (`dev_next_task` with no key) would claim an UNRELATED task
# at the head of the queue and strand it in_progress, and `dev_complete_task`
# refuses anything that is not already in_progress/blocked. Both halves of that
# are exercised here starting from the exact state that produced the finding: a
# task that is `pending`, never claimed, whose work is already done.
RSpec.describe Ai::Tools::DevLoopTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:other_user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "dev-claim-by-key") }

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
  end

  # The head of the queue — whatever a POSITIONAL claim would take. Every
  # example asserts this row is untouched, because silently claiming it is the
  # defect being removed.
  let!(:head_task) do
    create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "HEAD-unrelated", priority: 50, position: 1)
  end

  # The task whose work is already done and committed.
  let!(:target) do
    create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "IMP-target", priority: 1, position: 9)
  end

  let(:declared) do
    { "evidence" => { "framework" => "rspec", "passed" => 121, "failed" => 0,
                      "command" => "bundle exec rspec spec/x_spec.rb" } }
  end

  describe "dev_next_task with task_key (claim by key)" do
    it "claims the NAMED pending task and leaves the queue head pending" do
      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name,
                                      task_key: "IMP-target" })

      expect(result[:success]).to be true
      expect(result[:task][:task_key]).to eq("IMP-target")
      expect(target.reload.status).to eq("in_progress")
      expect(target.execution_attempts).to eq(1)
      expect(target.metadata["claimed_by"]).to eq("user:#{user.id}")
      # STATE oracle on the row the positional path would have taken.
      expect(head_task.reload.status).to eq("pending")
    end

    it "is idempotent for the same claimant: re-claiming by key returns the same task as reclaimed" do
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name, task_key: "IMP-target" })
      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name,
                                      task_key: "IMP-target" })

      expect(result[:success]).to be true
      expect(result[:reclaimed]).to be true
      expect(result[:task][:task_key]).to eq("IMP-target")
      expect(target.reload.execution_attempts).to eq(1) # not re-incremented
    end

    it "REFUSES a task already in_progress under another holder instead of stealing it" do
      other = described_class.new(account: account, user: other_user)
      other.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name, task_key: "IMP-target" })

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name,
                                      task_key: "IMP-target" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/in_progress/)
      # STATE oracle: the other holder's claim survives untouched.
      expect(target.reload.metadata["claimed_by"]).to eq("user:#{other_user.id}")
      expect(target.status).to eq("in_progress")
    end

    it "refuses a key that names a task in a DIFFERENT loop" do
      elsewhere_loop = create(:ai_ralph_loop, account: account, name: "some-other-loop")
      foreign = create(:ai_ralph_task, ralph_loop: elsewhere_loop, task_key: "IMP-foreign")

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name,
                                      task_key: "IMP-foreign" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
      expect(foreign.reload.status).to eq("pending")
      expect(head_task.reload.status).to eq("pending")
    end

    it "refuses a key naming an already-terminal task" do
      target.update!(status: "passed")

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name,
                                      task_key: "IMP-target" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/passed/)
      expect(head_task.reload.status).to eq("pending")
    end

    it "refuses a keyed claim whose dependencies are unsatisfied" do
      target.update!(dependencies: ["HEAD-unrelated"])

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name,
                                      task_key: "IMP-target" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/dependenc/i)
      expect(target.reload.status).to eq("pending")
    end

    it "honors the loop halt (kill switch) before claiming by key" do
      allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true)

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name,
                                      task_key: "IMP-target" })

      expect(result[:halted]).to be true
      expect(result[:reason]).to eq("emergency_halt")
      expect(target.reload.status).to eq("pending")
    end

    it "honors a paused loop before claiming by key" do
      ralph_loop.update!(status: "paused")

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name,
                                      task_key: "IMP-target" })

      expect(result[:halted]).to be true
      expect(result[:reason]).to eq("loop_paused")
      expect(target.reload.status).to eq("pending")
    end

    it "refuses a keyed claim that would exceed the per-claimant concurrency cap" do
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name, task_key: "HEAD-unrelated" })

      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name,
                                      task_key: "IMP-target" })

      expect(result[:halted]).to be true
      expect(result[:reason]).to eq("max_concurrent_claims_reached")
      expect(target.reload.status).to eq("pending")
    end

    it "leaves the positional claim unchanged when no task_key is given" do
      result = tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name })

      expect(result[:task][:task_key]).to eq("HEAD-unrelated")
      expect(target.reload.status).to eq("pending")
    end

    it "advertises task_key on the dev_next_task MCP schema" do
      expect(described_class.action_definitions["dev_next_task"][:parameters]).to have_key(:task_key)
    end
  end

  describe "dev_complete_task with claim_if_pending (atomic claim-and-close)" do
    def complete(extra = {})
      tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.name, task_key: "IMP-target",
        outcome: "passed", summary: "Work finished out of band and committed.",
        check_results: declared, commit_sha: "abc1234", git_branch: "dev-loop/dev-improve"
      }.merge(extra))
    end

    it "claims and closes a never-claimed pending task in one call" do
      result = complete(claim_if_pending: true)

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("passed")
      expect(result[:evidence_source]).to eq("declared")
      expect(result[:verification]).to eq("verified")

      target.reload
      expect(target.status).to eq("passed")
      expect(target.execution_attempts).to eq(1)
      expect(target.metadata["claimed_by"]).to eq("user:#{user.id}")
      expect(target.metadata["claimed_via"]).to eq("dev_complete_task")
      # STATE oracle: the iteration carries the declared evidence, not just a call.
      iteration = ralph_loop.ralph_iterations.where(ralph_task_id: target.id).last
      expect(iteration).to be_present
      expect(iteration.check_results["evidence"]["passed"]).to eq(121)
      # And the head of the queue is still pending — nothing was reordered.
      expect(head_task.reload.status).to eq("pending")
    end

    it "still REFUSES a pending task when claim_if_pending is absent" do
      result = complete

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not in_progress or blocked/)
      expect(target.reload.status).to eq("pending")
    end

    it "names both recovery paths in the refusal" do
      result = complete

      expect(result[:error]).to match(/task_key/)
      expect(result[:error]).to match(/claim_if_pending/)
    end

    it "refuses to claim-and-close a passed outcome without DECLARED evidence" do
      result = complete(claim_if_pending: true, check_results: { "rspec" => "121 examples, 0 failures" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/declared/i)
      expect(target.reload.status).to eq("pending")
    end

    it "refuses to claim-and-close a task held in_progress by another claimant" do
      other = described_class.new(account: account, user: other_user)
      other.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name, task_key: "IMP-target" })

      result = complete(claim_if_pending: true)

      expect(result[:success]).to be false
      expect(result[:error]).to match(/another/i)
      expect(target.reload.status).to eq("in_progress")
      expect(target.metadata["claimed_by"]).to eq("user:#{other_user.id}")
    end

    it "refuses to claim-and-close a pending task with unsatisfied dependencies" do
      target.update!(dependencies: ["HEAD-unrelated"])

      result = complete(claim_if_pending: true)

      expect(result[:success]).to be false
      expect(target.reload.status).to eq("pending")
    end

    it "does not claim-and-close while the kill switch is engaged" do
      allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true)

      result = complete(claim_if_pending: true)

      expect(result[:halted]).to be true
      expect(result[:reason]).to eq("emergency_halt")
      expect(target.reload.status).to eq("pending")
    end

    it "records an out-of-band FAILED outcome without requiring declared evidence" do
      result = complete(claim_if_pending: true, outcome: "failed", check_results: {})

      expect(result[:success]).to be true
      expect(target.reload.status).to eq("failed")
    end

    # `skipped` is legal from pending but ILLEGAL from in_progress, so a
    # claim-then-check ordering would claim the task and then bail, stranding it
    # in_progress. The state oracle here is the task's status, not the message.
    it "does not strand the task when the outcome is illegal for a claimed task" do
      result = complete(claim_if_pending: true, outcome: "skipped")

      expect(result[:success]).to be false
      expect(target.reload.status).to eq("pending")
      expect(target.execution_attempts).to eq(0)
      expect(target.metadata["claimed_by"]).to be_nil
    end

    it "does not enable the claim on a non-affirmative flag value" do
      result = complete(claim_if_pending: "no")

      expect(result[:success]).to be false
      expect(target.reload.status).to eq("pending")
    end

    it "leaves the ordinary in_progress report path unchanged" do
      tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.name, task_key: "IMP-target" })
      result = complete

      expect(result[:success]).to be true
      expect(target.reload.status).to eq("passed")
    end

    it "advertises claim_if_pending on the dev_complete_task MCP schema and the flat definition" do
      expect(described_class.action_definitions["dev_complete_task"][:parameters]).to have_key(:claim_if_pending)
      expect(described_class.definition[:parameters]).to have_key(:claim_if_pending)
    end
  end
end
