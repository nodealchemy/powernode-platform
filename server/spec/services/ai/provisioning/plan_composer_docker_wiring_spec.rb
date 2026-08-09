# frozen_string_literal: true

require "rails_helper"

# F-a (IMP 019fe5d6-f429, dryrun 20260809b): the composed plan carried a
# docker_provision step that depended on both provision steps but had NO
# depends_on_outputs mapping — DockerProvisionExecutor requires a single
# node_instance_id and raised 'missing required input' at runtime, which
# (pre-IMP-019fe5d7) also detonated the rollback that destroyed a healthy
# sibling instance. The runner's cross-step mechanism exists precisely for
# this; the composer just never engaged it.
#
# wire_docker_provision_steps! rewrites each unwired docker_provision step
# into ONE STEP PER INSTANCE: for every fan-out provision step with count k it
# emits k docker steps, each wired
#   node_instance_id => { from_step: <provision step>, path:
#   "outputs.node_instance_ids", select: <index> }
# and depending only on its own provision step — so a dna docker failure
# cannot block or (post-IMP-019fe5d7) harm the rna leg.
RSpec.describe Ai::Provisioning::PlanComposerService, "docker_provision wiring", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) { create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure") }
  let(:agent) { create(:ai_agent, account: account, creator: user, status: "active") }
  let(:goal) do
    Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Goal", goal_type: "creation",
      status: "pending", priority: 3, progress: 0.0, success_criteria: {}
    )
  end
  let(:plan) do
    Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                         status: "draft", version: 1, plan_data: {})
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  def provision_step!(number, count)
    plan.steps.create!(
      step_number: number, step_type: "provisioning_skill", description: "provision",
      dependencies: [],
      execution_config: { "skill" => "provision_full_stack", "on_failure" => "rollback",
                          "inputs" => { "count" => count, "provider_region_id" => "r-#{number}" } }
    )
  end

  def docker_step!(number, deps, inputs: {}, config_extra: {})
    plan.steps.create!(
      step_number: number, step_type: "provisioning_skill", description: "Docker provision",
      dependencies: deps,
      execution_config: { "skill" => "docker_provision", "on_failure" => "rollback",
                          "inputs" => inputs }.merge(config_extra)
    )
  end

  def wire!
    service.send(:wire_docker_provision_steps!, plan)
    plan.steps.reload.order(:step_number).to_a
  end

  def docker_steps(steps)
    steps.select { |s| s.execution_config["skill"] == "docker_provision" }
  end

  it "fans one unwired docker step into one wired step per provisioned instance" do
    # The 20260809b shape: provision 2×dna (step 1) + 1×rna (step 3),
    # docker step 2 depending on both, no wiring.
    provision_step!(1, 2)
    docker_step!(2, [1, 3])
    provision_step!(3, 1)

    dockers = docker_steps(wire!)

    expect(dockers.size).to eq(3)
    mappings = dockers.map { |s| s.execution_config.dig("depends_on_outputs", "node_instance_id") }
    expect(mappings).to all(include("path" => "outputs.node_instance_ids"))
    expect(mappings.map { |m| [m["from_step"], m["select"]] })
      .to match_array([[1, 0], [1, 1], [3, 0]])
  end

  it "each fanned docker step depends ONLY on its own provision step" do
    provision_step!(1, 2)
    docker_step!(2, [1, 3])
    provision_step!(3, 1)

    dockers = docker_steps(wire!)
    dockers.each do |s|
      from = s.execution_config.dig("depends_on_outputs", "node_instance_id", "from_step")
      expect(Array(s.dependencies).map(&:to_i)).to eq([from])
    end
  end

  it "repoints downstream dependents onto every fanned sibling" do
    provision_step!(1, 2)
    docker_step!(2, [1, 3])
    provision_step!(3, 1)
    downstream = plan.steps.create!(
      step_number: 4, step_type: "provisioning_skill", description: "after docker",
      dependencies: [2],
      execution_config: { "skill" => "deploy_app_code", "inputs" => {}, "on_failure" => "continue" }
    )

    steps = wire!
    sibling_numbers = docker_steps(steps).map { |s| s.step_number.to_i }
    expect(Array(downstream.reload.dependencies).map(&:to_i)).to match_array(sibling_numbers)
  end

  it "preserves the original step's other inputs and on_failure on every sibling" do
    provision_step!(1, 2)
    docker_step!(2, [1], inputs: { "dry_run" => true })

    dockers = docker_steps(wire!)
    expect(dockers.size).to eq(2)
    dockers.each do |s|
      expect(s.execution_config.dig("inputs", "dry_run")).to be true
      expect(s.execution_config["on_failure"]).to eq("rollback")
    end
  end

  # IMP 019fe7e0 (dryrun-20260809e): the decomposition emitted TWO docker
  # steps and the fan produced N-docker × M-instance duplicates (6 steps for
  # 3 instances, each covered twice). Redundant unwired docker steps collapse
  # to one BEFORE the fan, so N instances get exactly N docker steps.
  it "collapses duplicate unwired docker steps so each instance gets exactly one" do
    provision_step!(1, 2)
    docker_step!(2, [1, 4])
    docker_step!(3, [1, 4])
    provision_step!(4, 1)

    dockers = docker_steps(wire!)
    expect(dockers.size).to eq(3)
    expect(dockers.map { |s| m = s.execution_config.dig("depends_on_outputs", "node_instance_id"); [m["from_step"], m["select"]] })
      .to match_array([[1, 0], [1, 1], [4, 0]])
  end

  it "repoints a dependent of a dropped duplicate onto the survivor" do
    provision_step!(1, 1)
    docker_step!(2, [1])
    docker_step!(3, [1])
    downstream = plan.steps.create!(
      step_number: 4, step_type: "provisioning_skill", description: "after both dockers",
      dependencies: [2, 3],
      execution_config: { "skill" => "deploy_app_code", "inputs" => {}, "on_failure" => "continue" }
    )

    steps = wire!
    docker_numbers = docker_steps(steps).map { |s| s.step_number.to_i }
    deps = Array(downstream.reload.dependencies).map(&:to_i)
    expect(deps).not_to include(3)                 # the dropped duplicate is gone from deps
    expect((deps & docker_numbers)).not_to be_empty # still depends on a real docker step
  end

  it "leaves a docker step alone when it already carries depends_on_outputs" do
    provision_step!(1, 2)
    docker_step!(2, [1], config_extra: {
                   "depends_on_outputs" => {
                     "node_instance_id" => { "from_step" => 1, "path" => "outputs.node_instance_ids",
                                             "select" => "first" }
                   }
                 })

    dockers = docker_steps(wire!)
    expect(dockers.size).to eq(1)
    expect(dockers.first.execution_config.dig("depends_on_outputs", "node_instance_id", "select")).to eq("first")
  end

  it "leaves a docker step alone when node_instance_id was set at compose time" do
    provision_step!(1, 1)
    docker_step!(2, [1], inputs: { "node_instance_id" => "explicit-id" })

    dockers = docker_steps(wire!)
    expect(dockers.size).to eq(1)
    expect(dockers.first.execution_config).not_to have_key("depends_on_outputs")
  end

  it "warns and leaves the step when the plan has no provision steps to wire from" do
    docker_step!(1, [])
    expect(Rails.logger).to receive(:warn).with(/no provision step/i).at_least(:once)
    allow(Rails.logger).to receive(:warn).and_call_original

    dockers = docker_steps(wire!)
    expect(dockers.size).to eq(1)
    expect(dockers.first.execution_config).not_to have_key("depends_on_outputs")
  end

  # F-1 (IMP 019fe76e-6a43): the LLM decomposition NONDETERMINISTICALLY omits
  # the container-runtime leg — run 20260809c's plan had docker steps, run
  # 20260809d's (identical objective, use case naming 'the container-runtime
  # handshake') had none. Whether a stated requirement exists in the plan is
  # not the LLM's decision: when the brief demands runtime work and the
  # decomposition emitted no docker_provision step, append one — the wiring
  # pass then fans and wires it exactly as if the LLM had emitted it.
  describe "#ensure_runtime_leg!" do
    let(:runtime_brief) do
      { "use_case" => "an end-to-end platform-validation test workload exercising " \
                      "provisioning, module assignment, and the container-runtime handshake" }
    end

    def ensure!(brief)
      service.send(:ensure_runtime_leg!, plan, brief)
      plan.steps.reload.order(:step_number).to_a
    end

    it "appends a docker step when the brief demands runtime work and none exists" do
      provision_step!(1, 2)
      provision_step!(2, 1)

      steps = ensure!(runtime_brief)
      dockers = docker_steps(steps)
      expect(dockers.size).to eq(1)
      expect(Array(dockers.first.dependencies).map(&:to_i)).to match_array([1, 2])
      expect(dockers.first.execution_config["on_failure"]).to eq("rollback")
    end

    it "the appended step is then fanned + wired by the wiring pass (the run-d shape)" do
      provision_step!(1, 2)
      provision_step!(2, 1)
      ensure!(runtime_brief)

      dockers = docker_steps(wire!)
      expect(dockers.size).to eq(3)
      expect(dockers.map { |s| m = s.execution_config.dig("depends_on_outputs", "node_instance_id"); [m["from_step"], m["select"]] })
        .to match_array([[1, 0], [1, 1], [2, 0]])
    end

    it "does nothing when the decomposition already emitted a docker step" do
      provision_step!(1, 1)
      docker_step!(2, [1])
      steps = ensure!(runtime_brief)
      expect(docker_steps(steps).size).to eq(1)
    end

    it "does nothing when the brief does not demand runtime work" do
      provision_step!(1, 1)
      steps = ensure!("use_case" => "a plain postgres database", "intent" => "provision a db")
      expect(docker_steps(steps)).to be_empty
    end

    it "honors runtime_hint: docker as the demand signal" do
      provision_step!(1, 1)
      steps = ensure!("use_case" => "run my app", "runtime_hint" => "docker")
      expect(docker_steps(steps).size).to eq(1)
    end

    it "warns and appends nothing when there are no provision steps to hang it on" do
      expect(Rails.logger).to receive(:warn).with(/no provision step/i).at_least(:once)
      allow(Rails.logger).to receive(:warn).and_call_original
      steps = ensure!(runtime_brief)
      expect(docker_steps(steps)).to be_empty
    end
  end
end
