# frozen_string_literal: true

require "rails_helper"

# #check_network_declaration — the compose-time guard that refuses to silently
# compose bare compute for a plan that asked for the fabric (IMP-cdc1d0703e5a,
# extended to the account arm by IMP-94728a788498).
#
# IMP-5a7aa42515d6 narrows what counts as "asked for the fabric and got a
# broken answer": a numeric ZERO is a builder emitting an unset id, not an
# operator decision, so it must resolve like null/"" — inherit the next arm —
# rather than fail the compose. A NON-zero number stays loud, because a number
# where a UUID belongs is a real decision wrongly made.
RSpec.describe Ai::Provisioning::PlanComposerService, "network declaration check", type: :service do
  before { skip "system extension not loaded" unless defined?(::System::NodeTemplate) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:ai_provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: ai_provider, creator: user, status: "active")
  end
  let(:brief) do
    {
      "intent" => "provision a stack", "use_case" => "validation",
      "scale" => { "initial" => 1, "target" => 1 }, "regions" => [],
      "preferred_template" => "declaring-template"
    }
  end
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        configuration: { "brief" => brief })
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  def template_with(config)
    create(:system_node_template, account: account, name: "declaring-template", config: config)
  end

  # The check is plan-scoped (IMP-883a1f6f89d0), so a probe of it needs a plan
  # that actually stamps a network — otherwise these examples would go green
  # for the narrowing rather than for the bucketing they are pinning.
  def plan_with_skills(*skills)
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Provisioning goal", description: "test",
      goal_type: "creation", status: "pending", priority: 3, progress: 0.0,
      success_criteria: { "mission_id" => mission.id },
      metadata: { "provisioning_mission_id" => mission.id }
    )
    plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent,
                                status: "draft", version: 1)
    skills.each_with_index do |skill, idx|
      Ai::GoalPlanStep.create!(
        plan: plan, step_number: idx + 1, step_type: "provisioning_skill",
        status: "pending", dependencies: [],
        execution_config: { "skill" => skill, "inputs" => {} }
      )
    end
    plan
  end

  let(:provisioning_plan) { plan_with_skills("provision_full_stack") }

  describe "the template arm" do
    it "does NOT fail the compose for a numeric zero — it is an unset id, not a misconfiguration" do
      template_with("sdwan_network_id" => 0)

      expect(service.send(:check_network_declaration, brief, provisioning_plan)).to be_nil
    end

    it "resolves a numeric zero to no network at all, exactly as a null would" do
      template = template_with("sdwan_network_id" => 0)

      expect(service.send(:template_network_declaration, template)).to eq([ :absent, nil ])
      expect(service.send(:resolved_network_id, template)).to be_nil
    end

    # The over-widening guard. If this ever goes green-by-accident the fix has
    # stopped failing loud where failing loud was correct.
    it "still fails the compose for a NON-zero number" do
      template = template_with("sdwan_network_id" => 12_345)

      result = service.send(:check_network_declaration, brief, provisioning_plan)
      expect(result).to include(clarification_needed: true)
      expect(result[:network_declaration_issue]).to include(template_id: template.id,
                                                            key: "sdwan_network_id")
    end
  end

  describe "the account-default arm" do
    # The classifier is shared by BOTH arms, so the same narrowing reaches the
    # account default — and should: a settings form writing 0 for "unset" means
    # "no default", which is what :absent already means on this arm.
    it "does NOT fail the compose for a zero account default" do
      template_with("boot_mode" => "uefi_disk")
      account.update!(settings: (account.settings || {}).merge(
        ::Account::DEFAULT_SDWAN_NETWORK_SETTING => 0
      ))

      expect(service.send(:check_network_declaration, brief, provisioning_plan)).to be_nil
    end

    it "still fails the compose for a NON-zero account default" do
      template_with("boot_mode" => "uefi_disk")
      account.update!(settings: (account.settings || {}).merge(
        ::Account::DEFAULT_SDWAN_NETWORK_SETTING => 12_345
      ))

      result = service.send(:check_network_declaration, brief, provisioning_plan)
      expect(result).to include(clarification_needed: true)
      expect(result[:network_declaration_issue]).to include(scope: "account")
    end
  end

  # IMP-883a1f6f89d0. The check ran unconditionally against a FALLBACK-resolved
  # template, so ONE template carrying a broken declaration blocked EVERY
  # compose on the account — including plans that provision nothing and would
  # never consult a network declaration at all.
  #
  # The property: a template's malformed network declaration blocks composes
  # that would actually provision against that template, and nothing else.
  describe "the plan-scope narrowing (IMP-883a1f6f89d0)" do
    # The predicate itself, against a broken template that WOULD fail a
    # provisioning plan (the example above pins that it still does).
    it "is silent for a plan whose steps never resolve inputs from the template" do
      template_with("sdwan_network_id" => 12_345)
      advisory_plan = plan_with_skills("runbook_generate", "cve_response", "attribute_failure")

      expect(service.send(:check_network_declaration, brief, advisory_plan)).to be_nil
    end

    it "fires as soon as ONE step in the plan resolves inputs from the template" do
      template_with("sdwan_network_id" => 12_345)
      mixed_plan = plan_with_skills("runbook_generate", "provision_full_stack")

      expect(service.send(:check_network_declaration, brief, mixed_plan))
        .to include(clarification_needed: true)
    end

    # provision_cluster creates its nodes FROM the template and takes their
    # fabric membership from the template's own declaration at provision time
    # (System::ProvisioningService#sdwan_declaration_for reads
    # node.node_template.config), so it never carries a stamped network_id.
    # Scoping the check to "what the composer stamps" would therefore go silent
    # on the one plan shape nothing else catches: the prerequisite seam's
    # OVERLAY_REQUIRING_SKILLS is docker_provision only, and the extension's
    # provision-time resolver logs to nobody the operator reads.
    it "fires for a cluster plan, which provisions from the template without a stamped network_id" do
      template_with("sdwan_network_id" => 12_345)
      cluster_plan = plan_with_skills("provision_cluster")

      expect(service.send(:check_network_declaration, brief, cluster_plan))
        .to include(clarification_needed: true)
    end

    # …and the narrowing still holds for the skills that genuinely provision
    # nothing, which is what separates this from reverting the fix.
    it "stays silent for a plan of purely advisory skills" do
      template_with("sdwan_network_id" => 12_345)
      advisory = plan_with_skills("docker_provision", "module_compose", "capacity_recommend")

      expect(service.send(:check_network_declaration, brief, advisory)).to be_nil
    end

    # Deliberately NOT provisioning-shaped, so ComposerRouter#deterministic_provisioning?
    # is false and compose! takes the decompose + rewrite pipeline whose steps
    # the stub below controls. `preferred_template` is not part of that
    # predicate, so the broken template is still the one that resolves.
    let(:brief) do
      { "intent" => "Write up the fleet's CVE exposure",
        "use_case" => "Primary OLTP",
        "preferred_template" => "declaring-template" }
    end

    # Steps that map to NON-provisioning executors: nothing here ever reaches
    # #merge_resolved_inputs!, so nothing consults the template's network.
    let(:advisory_steps) do
      [ { description: "Generate the CVE runbook", config: { "action" => "cve runbook" }, dependencies: [] },
        { description: "Generate the remediation runbook", config: { "action" => "generate runbook" }, dependencies: [] } ]
    end

    def stub_decomposition(steps)
      allow_any_instance_of(Ai::Autonomy::GoalDecompositionService)
        .to receive(:decompose) do |_inst, goal|
          version = (Ai::GoalPlan.where(goal_id: goal.id).maximum(:version) || 0) + 1
          plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: goal.agent,
                                      status: "draft", version: version,
                                      plan_data: { "stub" => true })
          steps.each_with_index do |s, i|
            plan.steps.create!(step_number: i + 1, step_type: "agent_execution",
                               description: s[:description], execution_config: s[:config],
                               dependencies: s[:dependencies])
          end
          plan
        end
    end

    it "composes a plan that provisions nothing, despite the broken template" do
      template_with("sdwan_network_id" => 12_345)
      stub_decomposition(advisory_steps)

      result = service.compose!

      expect(result).to be_a(Ai::GoalPlan)
      # Self-validating: if the mapping ever routes these to a provisioning
      # executor the example would be asserting the wrong thing.
      skills = result.steps.reload.map { |s| s.execution_config["skill"] }
      expect(skills).not_to include("provision_full_stack", "scale_project")
    end

    # The other half of the property, and the over-narrowing guard: the check
    # must still fire for a plan that DOES provision against the template.
    it "still refuses a plan that provisions against the broken template" do
      template_with("sdwan_network_id" => 12_345)
      stub_decomposition(
        [ { description: "Provision the stack", config: { "action" => "provision new stack" },
            dependencies: [] } ]
      )

      result = service.compose!

      expect(result).to be_a(Hash)
      expect(result).to include(clarification_needed: true)
      expect(result[:network_declaration_issue]).to include(key: "sdwan_network_id")
    end

    it "narrows the account-default arm the same way" do
      template_with("boot_mode" => "uefi_disk")
      account.update!(settings: (account.settings || {}).merge(
        ::Account::DEFAULT_SDWAN_NETWORK_SETTING => 12_345
      ))
      stub_decomposition(advisory_steps)

      expect(service.compose!).to be_a(Ai::GoalPlan)
    end
  end
end

# IMP-975976497370 — WHICH TEMPLATE'S FABRIC A STEP INHERITS.
#
# #merge_resolved_inputs! preserves an already-authored template_id
# (`inputs["template_id"] ||= template&.id`) but read the fabric declaration
# from `resolve_template(brief)` unconditionally. When those disagree the step
# provisions from template X while carrying an SDWAN network_id declared by
# template Y — an instance placed on a network its own template never declared.
#
# Reachable on the LLM-fallback path only: #rewrite_step! merges the
# decomposition's own `inputs` hash before calling #merge_resolved_inputs!, so a
# decomposition emitting `inputs: { template_id: ... }` reaches this. The
# deterministic path builds `inputs = { "count" => share }` fresh per step, so
# template_id is always nil there and both resolutions agree.
RSpec.describe Ai::Provisioning::PlanComposerService, "step-authored template fabric", type: :service do
  before { skip "system extension not loaded" unless defined?(::System::NodeTemplate) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:ai_provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: ai_provider, creator: user, status: "active")
  end

  let(:net_x) { create(:sdwan_network, account: account) }
  let(:net_y) { create(:sdwan_network, account: account) }

  # The template the STEP pins...
  let!(:template_x) do
    create(:system_node_template, account: account, name: "authored-x",
                                  config: { described_class::NETWORK_CONFIG_KEY => net_x.id })
  end
  # ...and the one the BRIEF names.
  let!(:template_y) do
    create(:system_node_template, account: account, name: "brief-y",
                                  config: { described_class::NETWORK_CONFIG_KEY => net_y.id })
  end

  let(:brief) do
    { "intent" => "provision a stack", "use_case" => "validation",
      "scale" => { "initial" => 1, "target" => 1 }, "regions" => [],
      "preferred_template" => "brief-y" }
  end
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        configuration: { "brief" => brief })
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  # A step as the LLM decompose pass leaves it: its own inputs already pin a
  # template, which #rewrite_step! merges in before resolution runs.
  def authored_step(template_id:)
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Provisioning goal", description: "test",
      goal_type: "creation", status: "pending", priority: 3, progress: 0.0,
      success_criteria: { "mission_id" => mission.id },
      metadata: { "provisioning_mission_id" => mission.id }
    )
    plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "draft", version: 1)
    Ai::GoalPlanStep.create!(
      plan: plan, step_number: 1, step_type: "provisioning_skill", status: "pending",
      dependencies: [],
      execution_config: { "skill" => "provision_full_stack",
                          "inputs" => { "template_id" => template_id } }
    )
  end

  def rewritten_inputs(step)
    service.send(:rewrite_step!, step, brief)
    step.reload.execution_config["inputs"]
  end

  # The compose-time gate has to read the same record the stamp does. Both
  # directions are asserted, because a gate keyed on the wrong template fails
  # BOTH ways: it stays quiet about a broken template a step will really use,
  # and it blocks a perfectly good plan over a template nothing provisions from.
  describe "the compose-time gate" do
    # A NON-ZERO NUMBER is what :unusable means here — any non-blank String is
    # :usable (the composer deliberately does not existence-check an id), and a
    # numeric zero resolves as unset per IMP-5a7aa42515d6. A number where a UUID
    # belongs is "a real decision wrongly made", which is the loud arm.
    let(:broken) do
      create(:system_node_template, account: account, name: "broken-decl",
                                    config: { described_class::NETWORK_CONFIG_KEY => 42 })
    end

    def plan_pinning(template_id)
      goal = Ai::AgentGoal.create!(
        account: account, agent: agent, title: "g", description: "t",
        goal_type: "creation", status: "pending", priority: 3, progress: 0.0
      )
      plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "draft", version: 1)
      Ai::GoalPlanStep.create!(
        plan: plan, step_number: 1, step_type: "provisioning_skill", status: "pending",
        dependencies: [],
        execution_config: { "skill" => "provision_full_stack",
                            "inputs" => { "template_id" => template_id } }
      )
      plan.reload
    end

    it "fails loud when the template a STEP pins carries a broken declaration" do
      issue = service.send(:check_network_declaration, brief, plan_pinning(broken.id))

      expect(issue).to be_present, "a step provisioning from a broken template composed silently"
      expect(issue[:network_declaration_issue][:template_id]).to eq(broken.id)
    end

    it "stays quiet when only the BRIEF's template is broken and no step uses it" do
      allow(service).to receive(:resolve_template).and_return(broken)

      issue = service.send(:check_network_declaration, brief, plan_pinning(template_x.id))

      expect(issue).to be_nil,
                       "the compose was blocked over a template no step will provision from"
    end
  end

  it "takes the network from the template the STEP pins, not the brief's" do
    inputs = rewritten_inputs(authored_step(template_id: template_x.id))

    expect(inputs["template_id"]).to eq(template_x.id), "the authored template_id was not preserved"
    expect(inputs["network_id"]).to eq(net_x.id),
                                    "the step provisions from X but was placed on the brief template's network"
  end

  # Positive control: with no authored template_id the brief still governs, so
  # the fix narrows nothing that was working.
  it "falls back to the brief's template when the step pins none" do
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent, title: "g", description: "t",
      goal_type: "creation", status: "pending", priority: 3, progress: 0.0
    )
    plan = Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "draft", version: 1)
    step = Ai::GoalPlanStep.create!(
      plan: plan, step_number: 1, step_type: "provisioning_skill", status: "pending",
      dependencies: [], execution_config: { "skill" => "provision_full_stack", "inputs" => {} }
    )

    inputs = rewritten_inputs(step)

    expect(inputs["template_id"]).to eq(template_y.id)
    expect(inputs["network_id"]).to eq(net_y.id)
  end
end
