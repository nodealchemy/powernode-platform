# frozen_string_literal: true

require "rails_helper"

# IMP-cdbb0c06386c — a GET must not be able to destroy persisted execution
# provenance.
#
# The operator-facing read path (`MissionsController#compose_plan` →
# `PlanComposerService#compact_existing_plan!`) ran the step-collapse passes
# against the PERSISTED rows. Two failures compounded:
#
#   1. `mergeable?` ends on a three-key fingerprint
#      (template_id / provider_region_id / provider_instance_type_id). For any
#      skill that declares none of them (`deploy_app_code`, `docker_provision`,
#      the `sdwan_*` steps, `attach_storage`) the comparison was `nil == nil`
#      three times — unconditionally true — so ANY two consecutive
#      linear-chained same-skill steps merged, whatever their real inputs.
#   2. Neither pass was scoped by plan/step state, so a deep-link view of a
#      mission already in execute/verify destroyed completed steps — taking
#      `metadata["last_outputs"]` (the node_instance_ids that verification,
#      rollback and adaptation read back) with them.
#
# The legacy `collapse_redundant_provisioning_clusters!` pass is NOT the
# defect: it self-scopes to `provision_full_stack` and folding already-executed
# duplicate clusters is its stated purpose. It keeps that behaviour; what
# changed is that the READ PATH no longer invokes it on a plan that has
# started executing.
RSpec.describe Ai::Provisioning::PlanComposerService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  let(:brief) do
    { "intent" => "Stand up the workload", "use_case" => "Primary OLTP",
      "scale" => { "initial" => 1, "target" => 1, "growth_profile" => "steady" } }
  end

  let(:mission) do
    create(
      :ai_mission,
      account: account,
      created_by: user,
      mission_type: "infrastructure",
      custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
      configuration: { "brief" => brief }
    )
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  def build_plan(status: "draft")
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Goal", goal_type: "creation",
      status: "pending", priority: 3, progress: 0.0, success_criteria: {}
    )
    Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                         status: status, version: 1, plan_data: {})
  end

  def add_step(plan, number:, skill:, inputs:, dependencies: [], status: "pending", metadata: {})
    plan.steps.create!(
      step_number: number,
      step_type: "provisioning_skill",
      description: "step #{number}",
      status: status,
      dependencies: dependencies,
      metadata: metadata,
      execution_config: { "skill" => skill, "inputs" => inputs, "on_failure" => "rollback" }
    )
  end

  describe "#compact_existing_plan! (operator read path)" do
    # ---- Primary reproduction ------------------------------------------------
    # No legacy fixture, no execution state: two ordinary pending
    # `deploy_app_code` steps that differ in the ONLY input that matters for
    # them. The fingerprint keys are absent on both sides, which is precisely
    # the case the old `mergeable?` answered "yes" to.
    it "keeps two consecutive deploy_app_code steps whose repos differ" do
      plan = build_plan
      add_step(plan, number: 1, skill: "deploy_app_code",
                     inputs: { "repo_url" => "https://git.example/org/repo-a", "branch" => "main" })
      add_step(plan, number: 2, skill: "deploy_app_code", dependencies: [1],
                     inputs: { "repo_url" => "https://git.example/org/repo-b", "branch" => "release" })

      service.compact_existing_plan!(plan)

      steps = plan.steps.reload.order(:step_number).to_a
      expect(steps.size).to eq(2)
      expect(steps.map { |s| s.execution_config["inputs"]["repo_url"] })
        .to eq(["https://git.example/org/repo-a", "https://git.example/org/repo-b"])
      expect(steps.last.execution_config["inputs"]["branch"]).to eq("release")
    end

    # ---- Second oracle -------------------------------------------------------
    # Asserted on the ROWS, never on the rendered response: a read of a plan
    # that is already executing must leave every step — and every step's
    # recorded outputs — exactly where it found them. `provision_full_stack`
    # duplicates are used deliberately: that is the shape the legacy cluster
    # pass would otherwise fold, so this pins the read-path call site rather
    # than only the generic pass.
    it "leaves an executing plan's completed steps and their last_outputs untouched" do
      plan = build_plan(status: "executing")
      fingerprint = { "template_id" => "tpl-1", "provider_region_id" => "reg-1",
                      "provider_instance_type_id" => "it-1", "count" => 1 }
      add_step(plan, number: 1, skill: "provision_full_stack", inputs: fingerprint.dup,
                     status: "completed", metadata: { "last_outputs" => { "node_instance_ids" => ["i-aaa"] } })
      add_step(plan, number: 2, skill: "provision_full_stack", inputs: fingerprint.dup, dependencies: [1],
                     status: "completed", metadata: { "last_outputs" => { "node_instance_ids" => ["i-bbb"] } })
      add_step(plan, number: 3, skill: "provision_full_stack", inputs: fingerprint.dup, dependencies: [1],
                     status: "completed", metadata: { "last_outputs" => { "node_instance_ids" => ["i-ccc"] } })

      before_rows = plan.steps.reload.order(:step_number)
                        .map { |s| [s.id, s.step_number, s.metadata["last_outputs"]] }

      service.compact_existing_plan!(plan)

      after_rows = plan.steps.reload.order(:step_number)
                       .map { |s| [s.id, s.step_number, s.metadata["last_outputs"]] }

      expect(after_rows.size).to eq(3)
      expect(after_rows).to eq(before_rows)
    end

    # Fix (1) on its own: a mid-execution plan whose next steps are still
    # pending and DO share a full fingerprint. Fix (2) cannot catch this one —
    # the fingerprints match — so the plan-state scope has to.
    it "does not merge still-pending same-fingerprint steps once the plan is executing" do
      plan = build_plan(status: "executing")
      shared = { "template_id" => "tpl-1", "provider_region_id" => "reg-1",
                 "provider_instance_type_id" => "it-1", "count" => 1 }
      add_step(plan, number: 1, skill: "scale_project", inputs: shared.dup)
      add_step(plan, number: 2, skill: "scale_project", inputs: shared.dup, dependencies: [1])

      service.compact_existing_plan!(plan)

      expect(plan.steps.reload.count).to eq(2)
    end

    # A merge on a still-editable plan is still allowed when the two steps are
    # genuinely indistinguishable — the pass keeps its original purpose.
    it "still folds a genuinely identical consecutive pair on a draft plan" do
      plan = build_plan
      shared = { "template_id" => "tpl-1", "provider_region_id" => "reg-1",
                 "provider_instance_type_id" => "it-1", "count" => 1 }
      add_step(plan, number: 1, skill: "scale_project", inputs: shared.dup)
      add_step(plan, number: 2, skill: "scale_project", inputs: shared.dup, dependencies: [1])

      service.compact_existing_plan!(plan)

      steps = plan.steps.reload.to_a
      expect(steps.size).to eq(1)
      expect(steps.first.execution_config["inputs"]["count"]).to eq(2)
    end
  end

  # ---- Regression guard for the INTENDED legacy behaviour --------------------
  # `collapse_redundant_provisioning_clusters!` exists to repair already-executed
  # legacy provision_full_stack plans. The scope added for this defect lives on
  # the generic pass and on the read-path call site — never inside this one — so
  # driving it directly must still collapse a completed duplicate cluster.
  describe "#collapse_redundant_provisioning_clusters! (legacy pass)" do
    # NOTE ON REACH: this drives collapse_redundant_provisioning_clusters!
    # DIRECTLY. It is a unit guard that the legacy compaction still functions —
    # not a statement about production. The read path gates the whole of
    # #collapse_consecutive_same_target_steps! on execution_started?, so no
    # production caller reaches this pass with an executed plan any more. Read
    # it as "the method still works if something calls it", never as "this is
    # what a page view does to your completed plan".
    it "still collapses an already-executed duplicate provision_full_stack cluster (direct call; unreachable from the read path)" do
      plan = build_plan(status: "completed")
      [[1, []], [2, [1]], [3, [1]]].each do |number, deps|
        add_step(plan, number: number, skill: "provision_full_stack", dependencies: deps,
                       inputs: { "count" => 1 }, status: "completed",
                       metadata: { "last_outputs" => { "node_instance_ids" => ["i-#{number}"] } })
      end

      service.send(:collapse_redundant_provisioning_clusters!, plan)

      expect(plan.steps.reload.count).to eq(1)
      expect(plan.steps.first.execution_config["inputs"]["count"]).to eq(1)
    end
  end
end
