# frozen_string_literal: true

require "rails_helper"

# Goal-plan rulings 1 and 2: a plan concludes when nothing can move it, and a
# failure's class is named in one place.
RSpec.describe Ai::GoalPlan do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:goal) do
    Ai::AgentGoal.create!(account: account, agent: agent, title: "Keep the lint queue empty",
                          goal_type: "improvement", status: "active", priority: 3, progress: 0)
  end
  let(:plan) { described_class.create!(account: account, goal: goal, agent: agent, status: "executing", version: 1) }

  def step(number, status: "pending", type: "observation", dependencies: [])
    Ai::GoalPlanStep.create!(plan: plan, step_number: number, status: status, step_type: type,
                             dependencies: dependencies)
  end

  describe "the failure registry" do
    it "classes the no-dispatcher kind as deterministic" do
      expect(Ai::GoalPlanStep.failure_class_for("no_dispatcher")).to eq("deterministic")
    end

    it "classes a dispatch that raised as transient — the other arm" do
      expect(Ai::GoalPlanStep.failure_class_for("dispatch_raised")).to eq("transient")
    end

    # Q1: no paid replan unless a failure is KNOWN to be transient.
    it "classes a missing or unlisted kind as deterministic" do
      expect(Ai::GoalPlanStep.failure_class_for(nil)).to eq("deterministic")
      expect(Ai::GoalPlanStep.failure_class_for("something_new")).to eq("deterministic")
    end

    it "records the kind and its class on the step it fails" do
      failed = step(1, status: "executing")

      failed.fail!(reason: "enqueue failed", kind: "dispatch_raised")

      expect(failed.reload.metadata).to include("failure_kind" => "dispatch_raised", "failure_class" => "transient")
      expect(failed.failure_class).to eq("transient")
    end

    it "records deterministic for a writer that passes no kind" do
      failed = step(1, status: "executing")

      failed.fail!(reason: "deferred operation failed")

      expect(failed.reload.failure_class).to eq("deterministic")
    end
  end

  describe "#skip_unreachable_steps! and #concludable?" do
    it "skips the whole chain behind a failed step, and the plan can then conclude" do
      step(1, status: "failed")
      second = step(2, dependencies: [ 1 ])
      third = step(3, dependencies: [ 2 ])

      plan.skip_unreachable_steps!

      expect([ second.reload.status, third.reload.status ]).to eq(%w[skipped skipped])
      expect(second.result_summary).to eq("dependency 1 did not complete")
      expect(plan).to be_concludable
    end

    it "leaves a pending step whose dependency can still complete — the other arm" do
      step(1, status: "executing")
      waiting = step(2, dependencies: [ 1 ])

      plan.skip_unreachable_steps!

      expect(waiting.reload.status).to eq("pending")
      expect(plan).not_to be_concludable
    end

    it "does not conclude while a human_review step still waits for a person" do
      step(1, status: "failed")
      step(2, status: "executing", type: "human_review")

      expect(plan).not_to be_concludable
    end

    it "does not conclude a plan with no steps" do
      expect(plan).not_to be_concludable
    end
  end

  describe "#fail!" do
    it "records the reason and the failing step's class" do
      plan.fail!(reason: "enqueue failed", failure_class: "transient")

      expect(plan.reload.validation_result).to include("failure_reason" => "enqueue failed",
                                                       "failure_class" => "transient")
    end

    it "records deterministic when a caller passes no class" do
      plan.fail!(reason: "unhealthy")

      expect(plan.reload.validation_result["failure_class"]).to eq("deterministic")
    end
  end
end
