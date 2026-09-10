# frozen_string_literal: true

require "rails_helper"

# D4 — dev_complete_task hands the finished work to the LLM judge.
#
# The enqueue is EVENT-DRIVEN (no cron) and goes out through the same worker
# HTTP seam every other server-side job dispatch uses; this server runs no
# Sidekiq of its own.
#
# The open half is ATTRIBUTION. Nothing links a RalphTask to an
# Ai::AgentExecution: the task carries executor_id/executor_type (the
# polymorphic AGENT, not a run), the iteration carries no execution id, and a
# Claude Code executor's row is minted by a separate MCP verb
# (record_agent_execution, keyed "cc-"+digest(account, run_key)) with no
# correlation key back to the loop. So the completion path reads ONE named
# metadata key and stays silent when it is absent, rather than guessing from a
# time window — an inferred discriminator here would credit trust and skill
# effectiveness to whichever run happened to be nearby.
#
# Nothing writes that key yet. Both arms are pinned anyway, by writing it on a
# fixture, so the consumer is PROVEN and the producer is the only thing D5 has
# to add.
RSpec.describe Ai::Tools::DevLoopTool, "evaluation enqueue" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "eval-enqueue-loop") }
  let!(:task) { create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "E1-01") }
  let(:execution_id) { SecureRandom.uuid }

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
    allow(WorkerJobService).to receive(:enqueue_job)
    ralph_loop.update!(status: "running", started_at: Time.current)
    tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
  end

  def complete(outcome: "passed", summary: "work reported")
    tool.execute(params: {
      action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "E1-01",
      outcome: outcome, summary: summary
    })
  end

  def attribute_execution!
    Ai::RalphTask.where(id: task.id).update_all(
      ["metadata = COALESCE(metadata, '{}'::jsonb) || ?::jsonb",
       { described_class.const_get(:EVALUABLE_EXECUTION_METADATA_KEY) => execution_id }.to_json]
    )
  end

  context "when the task names the execution that served it" do
    before { attribute_execution! }

    it "enqueues AgentEvaluationJob with the account, execution and task ids" do
      complete

      expect(WorkerJobService).to have_received(:enqueue_job).with(
        "AgentEvaluationJob",
        hash_including(
          args: [ { "account_id" => account.id, "execution_id" => execution_id, "task_id" => task.id } ]
        )
      )
    end

    it "enqueues on a FAILED outcome too" do
      # Scoring only successes would bias the trust quality dimension and skill
      # effectiveness upward by construction.
      complete(outcome: "failed")

      expect(WorkerJobService).to have_received(:enqueue_job).with("AgentEvaluationJob", anything)
    end

    it "does not fail the completion when the worker is unreachable" do
      allow(WorkerJobService).to receive(:enqueue_job)
        .and_raise(WorkerJobService::WorkerServiceError, "worker down")

      result = complete

      expect(result[:success]).not_to be(false)
      expect(task.reload.status).to eq("passed")
    end
  end

  context "when nothing attributes an execution to the task" do
    it "enqueues nothing at all" do
      complete

      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end

    it "still completes the task normally" do
      expect(complete[:success]).not_to be(false)
      expect(task.reload.status).to eq("passed")
    end
  end
end
