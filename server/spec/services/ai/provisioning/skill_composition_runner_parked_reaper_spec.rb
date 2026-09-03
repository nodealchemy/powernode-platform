# frozen_string_literal: true

require "rails_helper"

# IMP-842b56d3a5d4 — the MISSED-RESUME half of APO-1f.
#
# A step parked on an approval leaves PARKED_STATUS only when something calls
# .resume_parked_step. Every caller of that is synchronous with the approval
# decision (Ai::DeferredOperation#execute_now! / #on_approval_decision), so a
# process death between the operation settling and the resume call strands the
# step: #dispatch_unblocked_successors only forwards `pending` steps and
# PARKED_STATUS counts as IN FLIGHT, so nothing re-drives it and the whole
# mission stops behind one row. Before this reaper the only exit was a HUMAN
# re-invoking the step.
#
# The reaper is a janitor sweep, so the examples are written against its
# PREDICATE — which rows it will and will not touch — rather than against the
# resume it delegates to (that is covered by the parked-approval spec).
RSpec.describe Ai::Provisioning::SkillCompositionRunner, "parked-step reaper" do
  let(:account)  { create(:account) }
  let(:user)     { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  let(:goal) do
    Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Provision",
      description: "d", goal_type: "improvement", status: "pending",
      priority: 3, progress: 0.0, success_criteria: {}, metadata: {}
    )
  end

  let(:plan) do
    Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                         status: "draft", version: 1, plan_data: { "kind" => "provisioning" })
  end

  let!(:mission) do
    Ai::Mission.create!(account: account, created_by: user, name: "m",
                        mission_type: "infrastructure", status: "active",
                        configuration: { "plan" => { "plan_id" => plan.id } })
  end

  def operation(status:, settled_ago: 1.hour, result: { "success" => true, "data" => { "instance_id" => "i-7" } })
    op = Ai::DeferredOperation.create!(
      account: account, action_category: "system.zz_gated",
      executor_class: "ZzGatedFixtureExecutor", params: { "widget_id" => "w-1" },
      requested_by: user, status: "pending"
    )
    op.update_columns(status: status, result: result, updated_at: settled_ago.ago)
    op
  end

  def parked_step(op, step_number: 1)
    plan.steps.create!(
      step_number: step_number, step_type: "provisioning_skill",
      status: described_class::PARKED_STATUS, description: "gated",
      execution_config: { "skill" => "provision_full_stack", "inputs" => {}, "on_failure" => "continue" },
      dependencies: [],
      metadata: { described_class::PARKED_APPROVAL_KEY => {
        "deferred_operation_id" => op.id,
        "approval_request_id" => nil,
        "action_category" => "system.zz_gated"
      } }
    )
  end

  before do
    allow(MissionChannel).to receive(:broadcast_mission_event)
    allow(WorkerJobService).to receive(:enqueue_job)
  end

  describe ".reapable_parked_steps (the predicate)" do
    it "selects a parked step whose operation settled longer ago than the delay" do
      step = parked_step(operation(status: "completed", settled_ago: 1.hour))

      expect(described_class.reapable_parked_steps(delay_seconds: 900).pluck(:id)).to include(step.id)
    end

    it "leaves a step whose operation settled INSIDE the delay to the normal resume lane" do
      step = parked_step(operation(status: "completed", settled_ago: 60.seconds))

      expect(described_class.reapable_parked_steps(delay_seconds: 900).pluck(:id)).not_to include(step.id)
    end

    it "ignores a parked step whose operation has not settled at all" do
      step = parked_step(operation(status: "approved", settled_ago: 1.hour))

      expect(described_class.reapable_parked_steps(delay_seconds: 900).pluck(:id)).not_to include(step.id)
    end

    it "ignores a step that is not parked" do
      op = operation(status: "completed", settled_ago: 1.hour)
      step = parked_step(op)
      step.update!(status: "completed")

      expect(described_class.reapable_parked_steps(delay_seconds: 900).pluck(:id)).not_to include(step.id)
    end

    it "selects a parked step whose approval was REJECTED — a decision is a settlement" do
      step = parked_step(operation(status: "rejected", settled_ago: 1.hour, result: {}))

      expect(described_class.reapable_parked_steps(delay_seconds: 900).pluck(:id)).to include(step.id)
    end

    # The sweep re-drives a step, and a resumed step DISPATCHES its successors.
    # That is autonomous action, so the account kill switch has to hold here the
    # same way it holds on the escalation and closure-driver janitor lanes —
    # otherwise `emergency_halt` stops new work while a cron keeps advancing
    # every in-flight provisioning DAG.
    it "ignores a parked step on an AI-SUSPENDED account" do
      step = parked_step(operation(status: "completed", settled_ago: 1.hour))
      account.suspend_ai!

      expect(described_class.reapable_parked_steps(delay_seconds: 900).pluck(:id)).not_to include(step.id)
    end

    it "ignores a parked step whose metadata names no deferred operation" do
      step = plan.steps.create!(
        step_number: 9, step_type: "provisioning_skill",
        status: described_class::PARKED_STATUS, description: "gated",
        execution_config: { "skill" => "provision_full_stack" }, dependencies: [], metadata: {}
      )

      expect(described_class.reapable_parked_steps(delay_seconds: 900).pluck(:id)).not_to include(step.id)
    end
  end

  describe ".reap_parked_steps" do
    it "resumes a stranded parked step to completion" do
      step = parked_step(operation(status: "completed", settled_ago: 1.hour))

      described_class.reap_parked_steps(delay_seconds: 900)

      expect(step.reload.status).to eq("completed")
    end

    it "fails a stranded step whose approval was rejected" do
      step = parked_step(operation(status: "rejected", settled_ago: 1.hour, result: {}))

      described_class.reap_parked_steps(delay_seconds: 900)

      expect(step.reload.status).to eq("failed")
    end

    it "reports how many stranded steps it resumed" do
      parked_step(operation(status: "completed", settled_ago: 1.hour))

      expect(described_class.reap_parked_steps(delay_seconds: 900)[:resumed]).to eq(1)
    end

    # REVIEW FINDING (IMP-842b56d3a5d4): #resume_step! returns a NON-NIL
    # `{ skipped: true }` envelope when the resume claim is lost or the row is
    # no longer parked. Counting "not nil" as a resume made the janitor report
    # work it did not do — and a benign lost race is exactly what a concurrent
    # live release produces.
    it "does not count a lost-claim skip as a resume" do
      parked_step(operation(status: "completed", settled_ago: 1.hour))
      allow(described_class).to receive(:resume_parked_step)
        .and_return({ success: false, outputs: {}, error: nil, skipped: true })

      result = described_class.reap_parked_steps(delay_seconds: 900)

      expect(result[:examined]).to eq(1)
      expect(result[:resumed]).to eq(0)
    end

    it "does not count a still-pending resume as a resume" do
      parked_step(operation(status: "completed", settled_ago: 1.hour))
      allow(described_class).to receive(:resume_parked_step)
        .and_return({ success: false, outputs: {}, error: nil, pending: true })

      expect(described_class.reap_parked_steps(delay_seconds: 900)[:resumed]).to eq(0)
    end

    # REVIEW FINDING: an unbounded sweep materialises every stranded row and
    # each resume DISPATCHES successors, so one 15-minute tick could advance a
    # whole backlog of DAGs at once. The batch cap is DB-resolved with a
    # constant fallback, and it is the DEFAULT — every caller is bounded,
    # not just the ones that remember to pass it.
    it "caps one sweep at the configured batch limit" do
      3.times { |i| parked_step(operation(status: "completed", settled_ago: 1.hour), step_number: i + 1) }
      SiteSetting.create!(key: described_class::PARKED_REAP_BATCH_LIMIT_SETTING,
                          value: "1", setting_type: "integer")

      expect(described_class.reap_parked_steps(delay_seconds: 900)[:examined]).to eq(1)
    end

    it "bounds the sweep by default, without the caller passing a limit" do
      expect(described_class).to receive(:parked_step_reap_batch_limit).and_return(1)
      2.times { |i| parked_step(operation(status: "completed", settled_ago: 1.hour), step_number: i + 1) }

      expect(described_class.reap_parked_steps(delay_seconds: 900)[:examined]).to eq(1)
    end

    # REVIEW FINDING: ai_deferred_operations.result is `jsonb default: {}`, and
    # Ai::DeferredOperation#execute_now! writes `{}` for an executor that
    # returned nil. The row-read door then reads a COMPLETED operation with no
    # payload. Pinning the disposition matters now that a cron walks this door
    # rather than only a human re-invocation.
    it "completes a step whose settled operation carries an EMPTY result, with no outputs" do
      step = parked_step(operation(status: "completed", settled_ago: 1.hour, result: {}))

      described_class.reap_parked_steps(delay_seconds: 900)

      expect(step.reload.status).to eq("completed")
      expect(step.metadata["last_outputs"]).to eq({})
    end

    it "leaves a step still inside the delay parked" do
      step = parked_step(operation(status: "completed", settled_ago: 60.seconds))

      described_class.reap_parked_steps(delay_seconds: 900)

      expect(step.reload.status).to eq(described_class::PARKED_STATUS)
    end
  end

  describe "the reap batch limit" do
    it "falls back to the constant when no SiteSetting is configured" do
      expect(described_class.parked_step_reap_batch_limit)
        .to eq(described_class::DEFAULT_PARKED_REAP_BATCH_LIMIT)
    end

    it "resolves the limit from SiteSetting" do
      SiteSetting.create!(key: described_class::PARKED_REAP_BATCH_LIMIT_SETTING,
                          value: "25", setting_type: "integer")

      expect(described_class.parked_step_reap_batch_limit).to eq(25)
    end

    it "ignores a non-positive configured limit rather than sweeping nothing" do
      SiteSetting.create!(key: described_class::PARKED_REAP_BATCH_LIMIT_SETTING,
                          value: "0", setting_type: "integer")

      expect(described_class.parked_step_reap_batch_limit)
        .to eq(described_class::DEFAULT_PARKED_REAP_BATCH_LIMIT)
    end
  end

  describe "the reap delay" do
    it "falls back to the constant when no SiteSetting is configured" do
      expect(described_class.parked_step_reap_delay_seconds)
        .to eq(described_class::DEFAULT_PARKED_REAP_DELAY_SECONDS)
    end

    it "resolves the delay from SiteSetting" do
      SiteSetting.create!(key: described_class::PARKED_REAP_DELAY_SETTING,
                          value: "60", setting_type: "integer")

      expect(described_class.parked_step_reap_delay_seconds).to eq(60)
    end

    it "ignores a non-positive configured delay rather than reaping instantly" do
      SiteSetting.create!(key: described_class::PARKED_REAP_DELAY_SETTING,
                          value: "0", setting_type: "integer")

      expect(described_class.parked_step_reap_delay_seconds)
        .to eq(described_class::DEFAULT_PARKED_REAP_DELAY_SECONDS)
    end
  end
end
