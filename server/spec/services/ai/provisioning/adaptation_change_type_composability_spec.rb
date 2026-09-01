# frozen_string_literal: true

require "rails_helper"

# IMP-3f9bf5594e9c — settle, BY EXECUTION, whether `schema_change` and
# `security_change` can compose a bindable step.
#
# The reported finding was that they cannot, and that `UNSUPPORTED_CHANGE_TYPES`
# being empty is therefore a false advertisement. The constant carries a long
# comment answering that against the finding — but a comment asserting a
# mechanism the code lacks is exactly the shape that hides a defect, so nothing
# here reads it. Every claim below is produced by driving #build_steps_for, the
# single exit through which every composer's output passes #reject_unbindable,
# and observing what survives.
#
# The claim under test is CONDITIONAL ("composes when the LLM is reachable and
# the executor inputs are available"), so both conditions are exercised:
# reachable-with-inputs, and unreachable. A conditional claim confirmed under
# only its favourable condition is not confirmed.
#
# The oracle is an EQUALITY, not a per-entry check: the set of requestable
# change types that compose NOTHING under their own favourable condition must
# EQUAL UNSUPPORTED_CHANGE_TYPES.keys. An existence check over the constant's
# entries cannot see a MISSING one — a change type that stopped composing would
# just fall through to "no plan could be composed" — and it cannot see a stale
# one either, which is how `cost_control` outlived its cause once.
#
# WHAT THIS FILE DOES AND DOES NOT ESTABLISH. It establishes that these change
# types are not STRUCTURALLY unsupported — there is a live composer path, the
# bindability guard is what decides, and an empty UNSUPPORTED_CHANGE_TYPES is
# therefore the correct advertisement. It does NOT establish that a production
# model reliably SUPPLIES those inputs: condition 1's stub derives its inputs
# from the same #required_inputs_for that #bindable? consults, so it proves
# "satisfy the contract and the step survives", not "the contract gets
# satisfied in the field". Note too that #bindable? checks only `.present?`
# (adaptation_proposer_service.rb:758), so a String standing in for an
# array-typed required input binds here and would still fail on dispatch by
# type — bindability is a weaker property than executability.
RSpec.describe Ai::Provisioning::AdaptationProposerService, "change-type composability" do
  # WHOLE-FILE GUARD, deliberately at the outermost scope.
  #
  # Every skill this file drives (attach_storage, configure_sdwan_for_project,
  # scale_project, relocate_workload) has its executor in the system extension.
  # With the extension absent, #required_inputs_for returns nil
  # (skill_composition_runner.rb:348-350), #bindable? returns true unconditionally
  # (adaptation_proposer_service.rb:754-756), and EVERY step survives
  # #reject_unbindable — so the equality passes, the anti-vacuity example passes,
  # and condition 1 "composes" with an empty inputs hash. The whole verdict
  # degrades to a tautology while reporting green.
  #
  # A per-example skip on the inner group was not enough: a skip is not a
  # failure, and the file would still report every other example as a pass. The
  # guard therefore governs the file, so in core mode this reports PENDING —
  # "not verified here" — rather than a green that means nothing.
  before do
    unless defined?(::System::Ai::Skills::AttachStorageExecutor)
      skip "system extension not loaded — the executors this verdict depends on are absent, " \
           "and #bindable? waves everything through without them"
    end
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }

  let(:footprint) do
    { "template_id" => "tmpl-aaa", "provider_region_id" => "region-bbb",
      "provider_instance_type_id" => "itype-ccc", "network_id" => "net-ddd",
      "with_storage_gb" => 50 }
  end

  # A fresh agent per mission: Ai::AgentGoal caps an agent at 5 active goals,
  # and the equality oracle below drives every requestable change type.
  def build_mission!
    agent = create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
    goal = Ai::AgentGoal.create!(
      account: account, agent: agent, title: "Provision", description: "initial",
      goal_type: "improvement", status: "pending", priority: 3, progress: 0.0,
      success_criteria: {}, metadata: {}
    )
    plan = Ai::GoalPlan.create!(
      account: account, goal: goal, agent: agent,
      status: "draft", version: 1, plan_data: { "kind" => "provisioning" }
    )
    plan.steps.create!(
      step_number: 1, step_type: "provisioning_skill", status: "pending",
      description: "Provision full stack",
      execution_config: { "skill" => "provision_full_stack", "inputs" => footprint,
                          "on_failure" => "rollback" },
      dependencies: []
    )

    mission = create(
      :ai_mission,
      account: account, created_by: user, mission_type: "infrastructure",
      custom_phases: [ { "key" => "adapting", "label" => "Adapting", "order" => 0 } ],
      configuration: {
        "brief" => { "intent" => "small web stack",
                     "scale" => { "initial" => 2, "target" => 4 },
                     "regions" => %w[us-east-1 us-west-2] },
        "watch_policies" => { "auto_scale_max_replicas" => 8 },
        "plan" => { "plan_id" => plan.id }
      }
    )
    mission.update_columns(status: "active")
    mission.reload
  end

  # The payload each DETERMINISTIC change type needs to have something to say.
  # Anything else composes off an empty envelope.
  #
  # A `let`, not a constant: a constant assigned inside an RSpec.describe block
  # lands on Object at global scope, which is the duplicate-constant-clobber
  # shape that produces order-dependent flakes in this suite.
  #
  # Only `scale_horizontal` needs one today — `cost_control` composes off an
  # empty envelope because #scale_in_inputs supplies exactly the three inputs
  # ScaleProjectExecutor declares required. If a change type ever starts
  # needing a payload, its absence here shows up as a MISSING FIXTURE reading
  # as a real gap; add the entry rather than an UNSUPPORTED_CHANGE_TYPES entry.
  let(:favourable_details) do
    { "scale_horizontal" => { "drift_type" => "replica_count", "observed" => 1, "target" => 3 } }
  end

  # Drive the real composer for one change type under its own favourable
  # condition, and return the steps that SURVIVED #reject_unbindable.
  #
  # For a deterministic type that means no stub at all — consulting the LLM
  # there would be the defect, not the condition. For an LLM-only type the
  # favourable condition is "model reachable AND the executor's inputs
  # available", so the stub returns the skill the service itself would name,
  # carrying exactly the inputs the executor itself declares required. Both
  # are DERIVED — hardcoding either would test this spec's beliefs about the
  # contract rather than the contract.
  def composed_steps_for(change_type)
    svc = described_class.new(account: account, mission: build_mission!)
    signal = svc.send(:explicit_signal, change_type, metric: nil,
                                        details: favourable_details[change_type] || {})

    unless described_class::DETERMINISTIC_CHANGE_TYPES.include?(change_type)
      skill = described_class::DEFAULT_SKILL_FOR_CHANGE.fetch(change_type)
      required = Ai::Provisioning::SkillCompositionRunner.required_inputs_for(skill) || []
      allow(svc).to receive(:diff_from_llm).and_return(
        [ { "skill" => skill,
            "inputs" => required.index_with { |key| "supplied-#{key}" },
            "on_failure" => "rollback" } ]
      )
    end

    svc.send(:build_steps_for, signal, change_type)
  end

  # The same drive with the model UNREACHABLE. #safe_call swallows the raise,
  # sanitize_steps sees nothing, and composition falls back to the heuristic —
  # whose envelope-only inputs are then dropped by #reject_unbindable.
  def composed_steps_without_llm(change_type)
    svc = described_class.new(account: account, mission: build_mission!)
    signal = svc.send(:explicit_signal, change_type, metric: nil, details: {})
    allow(svc).to receive(:diff_from_llm).and_raise(StandardError, "model unreachable")

    svc.send(:build_steps_for, signal, change_type)
  end

  # ── The verdict ───────────────────────────────────────────────────────────
  describe "condition 1 — the model is reachable and the executor inputs are available" do
    it "composes a bindable step for schema_change" do
      steps = composed_steps_for("schema_change")

      expect(steps.map { |s| s["skill"] }).to eq(%w[attach_storage])
      expect(steps.first["composed_by"]).to eq("llm")
    end

    it "composes a bindable step for security_change" do
      steps = composed_steps_for("security_change")

      expect(steps.map { |s| s["skill"] }).to eq(%w[configure_sdwan_for_project])
      expect(steps.first["composed_by"]).to eq("llm")
    end
  end

  describe "condition 2 — the model is unreachable" do
    # The claim is that this is a RUNTIME outcome, not a property of the change
    # type. What that has to look like: an empty plan, not an exception and not
    # a step that dies later on dispatch.
    it "composes nothing for schema_change, without raising" do
      expect(composed_steps_without_llm("schema_change")).to eq([])
    end

    it "composes nothing for security_change, without raising" do
      expect(composed_steps_without_llm("security_change")).to eq([])
    end

    # An operator asking for one still gets the request accepted and an empty
    # plan — NOT UnsupportedChangeTypeError, which is the refusal an entry in
    # UNSUPPORTED_CHANGE_TYPES would install.
    it "still accepts the request and returns an empty plan" do
      svc = described_class.new(account: account, mission: build_mission!)
      allow(svc).to receive(:diff_from_llm).and_raise(StandardError, "model unreachable")

      result = nil
      expect { result = svc.propose_change(change_type: "schema_change") }.not_to raise_error
      expect(result[:plan]).to be_nil
    end
  end

  # ── The equality oracle ───────────────────────────────────────────────────
  describe "UNSUPPORTED_CHANGE_TYPES equals the set that composes nothing" do
    # Memoized: the message interpolation below reads it a second time, and
    # each drive builds a mission.
    def never_composing_change_types
      @never_composing_change_types ||=
        described_class::REQUESTABLE_CHANGE_TYPES.reject { |type| composed_steps_for(type).any? }
    end

    it "declares exactly the change types no reachable condition can actuate" do
      expect(never_composing_change_types)
        .to match_array(described_class::UNSUPPORTED_CHANGE_TYPES.keys),
        "the set of requestable change types that compose NOTHING under their own favourable " \
        "condition no longer equals UNSUPPORTED_CHANGE_TYPES. A type missing from the constant is " \
        "an operator asking for something and being told 'nothing could be composed'; a type " \
        "present in it that now composes is a stale refusal that disables a working lane.\n" \
        "  derived: #{never_composing_change_types.inspect}\n" \
        "  declared: #{described_class::UNSUPPORTED_CHANGE_TYPES.keys.sort.inspect}"
    end

    # ── Anti-vacuity ────────────────────────────────────────────────────────
    # Both sides are empty today, and an equality between two empty sets is
    # the one result that proves nothing. These pin that the empty LEFT side
    # comes from every type actually composing, not from the drive above
    # silently composing nothing for all of them.
    it "actually composes something for every requestable change type" do
      composed = described_class::REQUESTABLE_CHANGE_TYPES.index_with do |type|
        composed_steps_for(type).map { |s| s["skill"] }
      end

      expect(composed.keys).to match_array(described_class::REQUESTABLE_CHANGE_TYPES)
      expect(composed.values).to all(be_present)
    end

    it "detects a stale entry — the failure mode the equality exists for" do
      stub_const("#{described_class}::UNSUPPORTED_CHANGE_TYPES",
                 { "schema_change" => "no composer available" }.freeze)

      expect(never_composing_change_types)
        .not_to match_array(described_class::UNSUPPORTED_CHANGE_TYPES.keys)
    end
  end

  # The favourable condition for the LLM lane is "the executor's inputs are
  # available", which is only a meaningful condition if the executors declare
  # any. The file-level guard above keeps this file from reporting green
  # without them; these two examples are the positive proof that, when they ARE
  # present, the contract is non-empty and the guard actually drops a step.
  describe "the bindability guard is live, not waved through" do
    it "reads a non-empty required-input contract for the LLM-lane skills" do
      %w[schema_change security_change relocate].each do |type|
        skill = described_class::DEFAULT_SKILL_FOR_CHANGE.fetch(type)
        expect(Ai::Provisioning::SkillCompositionRunner.required_inputs_for(skill))
          .to be_present, "#{skill} declares no required inputs — #bindable? cannot drop anything"
      end
    end

    it "drops a step that names an allowlisted skill but omits a required input" do
      svc = described_class.new(account: account, mission: build_mission!)
      signal = svc.send(:explicit_signal, "schema_change", metric: nil, details: {})
      allow(svc).to receive(:diff_from_llm).and_return(
        [ { "skill" => "attach_storage", "inputs" => { "instance_id" => "inst-1" },
            "on_failure" => "rollback" } ] # size_gb omitted
      )

      expect(svc.send(:build_steps_for, signal, "schema_change")).to eq([])
    end
  end
end
