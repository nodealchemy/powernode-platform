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
# D5 lands the producer: the executor names its run on dev_complete_task
# (`agent_execution_id`, e.g. the `id` record_agent_execution returned), the
# id is checked against this account, and only then is it stamped on the task.
# The fixture-written arms below still pin the consumer on its own.
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

  context "when the executor names its run on completion (the D5 producer)" do
    let(:key) { described_class.const_get(:EVALUABLE_EXECUTION_METADATA_KEY) }
    let(:agent) { create(:ai_agent, account: account) }
    let(:execution) { create(:ai_agent_execution, :completed, account: account, agent: agent) }

    def complete_naming(id, outcome: "passed")
      tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "E1-01",
        outcome: outcome, summary: "work reported", agent_execution_id: id
      })
    end

    it "stamps the task with the run and hands that run to the judge" do
      complete_naming(execution.id)

      expect(task.reload.metadata[key]).to eq(execution.id)
      expect(WorkerJobService).to have_received(:enqueue_job).with(
        "AgentEvaluationJob",
        hash_including(
          args: [ { "account_id" => account.id, "execution_id" => execution.id, "task_id" => task.id } ]
        )
      )
    end

    it "refuses an id that names no execution in this account, before the task moves" do
      result = complete_naming(SecureRandom.uuid)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("agent_execution_id")
      expect(task.reload.status).to eq("in_progress")
      expect(WorkerJobService).not_to have_received(:enqueue_job)
    end

    it "refuses another account's execution" do
      other = create(:account)
      foreign = create(:ai_agent_execution, :completed, account: other, agent: create(:ai_agent, account: other))

      result = complete_naming(foreign.id)

      expect(result[:success]).to be(false)
      expect(task.reload.metadata).not_to have_key(key)
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
