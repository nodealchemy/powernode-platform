# frozen_string_literal: true

require "rails_helper"

# IMP-cdbb0c06386c — the operator read path stopped collapsing the ROWS of a
# plan that has left the review gate (that is where execution provenance
# lives). The cosmetic job it used to do — a legacy plan rendering N identical
# provisioning rows — moves here, to the rendered DAG, where nothing is
# destroyed and the fold is disclosed on the surviving node.
RSpec.describe Ai::Provisioning::PlanSnapshotService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  subject(:service) { described_class.new(account: account) }

  def build_plan(status:)
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Goal", goal_type: "creation",
      status: "pending", priority: 3, progress: 0.0, success_criteria: {}
    )
    Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                         status: status, version: 1, plan_data: {})
  end

  def add_step(plan, number:, skill:, inputs:, dependencies: [], status: "pending")
    plan.steps.create!(
      step_number: number, step_type: "provisioning_skill", description: "step #{number}",
      status: status, dependencies: dependencies,
      execution_config: { "skill" => skill, "inputs" => inputs, "on_failure" => "rollback" }
    )
  end

  describe "#snapshot dag folding" do
    it "renders one node with the summed count for indistinguishable steps of an executing plan" do
      plan = build_plan(status: "executing")
      inputs = { "template_id" => "tpl-1", "provider_region_id" => "reg-1",
                 "provider_instance_type_id" => "it-1", "count" => 1 }
      a = add_step(plan, number: 1, skill: "provision_full_stack", inputs: inputs.dup, status: "completed")
      b = add_step(plan, number: 2, skill: "provision_full_stack", inputs: inputs.dup,
                         dependencies: [1], status: "completed")
      c = add_step(plan, number: 3, skill: "provision_full_stack", inputs: inputs.dup,
                         dependencies: [1], status: "completed")

      dag = service.snapshot(plan: plan)[:dag]

      # Rows are untouched — only the view folded.
      expect(plan.steps.reload.count).to eq(3)
      expect(dag[:nodes].size).to eq(1)
      node = dag[:nodes].first
      expect(node[:id]).to eq(a.id.to_s)
      expect(node[:name]).to include("3×")
      expect(node[:folded_step_ids]).to match_array([b.id.to_s, c.id.to_s])
      # The only edges were 2→1 and 3→1, both collapsed onto the kept node.
      expect(dag[:edges]).to eq([])
    end

    it "never folds steps whose inputs differ" do
      plan = build_plan(status: "executing")
      add_step(plan, number: 1, skill: "deploy_app_code", status: "completed",
                     inputs: { "repo_url" => "https://git.example/org/a" })
      add_step(plan, number: 2, skill: "deploy_app_code", status: "completed", dependencies: [1],
                     inputs: { "repo_url" => "https://git.example/org/b" })

      dag = service.snapshot(plan: plan)[:dag]

      expect(dag[:nodes].size).to eq(2)
      expect(dag[:nodes].map { |n| n[:folded_step_ids] }).to all(be_nil)
      expect(dag[:edges].size).to eq(1)
    end

    it "never folds steps at different execution statuses" do
      plan = build_plan(status: "executing")
      inputs = { "template_id" => "tpl-1", "count" => 1 }
      add_step(plan, number: 1, skill: "provision_full_stack", inputs: inputs.dup, status: "completed")
      add_step(plan, number: 2, skill: "provision_full_stack", inputs: inputs.dup,
                     dependencies: [1], status: "pending")

      dag = service.snapshot(plan: plan)[:dag]

      expect(dag[:nodes].size).to eq(2)
    end

    it "leaves a plan still at the review gate rendering its real rows" do
      plan = build_plan(status: "draft")
      inputs = { "template_id" => "tpl-1", "count" => 1 }
      add_step(plan, number: 1, skill: "provision_full_stack", inputs: inputs.dup)
      add_step(plan, number: 2, skill: "provision_full_stack", inputs: inputs.dup, dependencies: [1])

      dag = service.snapshot(plan: plan)[:dag]

      expect(dag[:nodes].size).to eq(2)
      expect(dag[:edges].size).to eq(1)
    end
  end
  # REGRESSION (found in review, not by the original specs): fanned-out
  # per-instance legs are byte-identical in `inputs` and differ ONLY in
  # depends_on_outputs/dependencies. A fold key built from [skill, status,
  # inputs] collapsed every docker leg of a multi-instance plan into ONE node.
  # The frontend derives its denominator from dag.nodes and computes allDone
  # over the DISPLAYED steps, so that showed "0 of 2 steps" for a 1+3 plan and
  # fired onAllComplete when the FIRST leg finished — dropping the operator out
  # of the live view while two legs were still pending.
  describe "steps that differ only in depends_on_outputs" do
    it "does NOT fold a per-instance fan-out into one node" do
      plan = build_plan(status: "executing")
      3.times do |i|
        plan.steps.create!(
          step_number: i + 1, step_type: "provisioning_skill", description: "docker leg #{i}",
          # COMPLETED, deliberately: the in-flight guard returns {} when any
          # step is still moving, so a pending fixture never reaches the fold
          # key and this example would pass against the ORIGINAL weak key —
          # i.e. it would prove nothing. Verified by mutation: with pending
          # steps the weak key passes; with completed steps it fails.
          status: "completed", dependencies: [],
          execution_config: {
            "skill" => "docker_provision",
            "inputs" => { "brief" => { "app" => "web" } },
            "depends_on_outputs" => { "node_instance_id" => { "select" => i } }
          }
        )
      end

      nodes = service.snapshot(plan: plan)[:dag][:nodes]

      expect(nodes.size).to eq(3),
                            "the fan-out folded to #{nodes.size} node(s) — the operator's progress " \
                            "denominator and allDone are both derived from dag.nodes"
    end
  end

end
