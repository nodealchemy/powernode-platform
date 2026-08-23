# frozen_string_literal: true

require "rails_helper"

# TRUTHFULNESS of the routing oracle, not its verdict.
#
# `grade!` runs from `drive!` — long before this run's `restore_gate!` — so a
# concurrent run can have reaped this run's gate claim by the time grading
# happens (HOLDER_GRACE_SECONDS is one-sided BY DESIGN; never reaping latches
# the gate on forever, which is strictly worse). When the claim is gone the run
# observed routing under NO guarantee that the gate was on: the dimension is
# UNMEASURED, not degraded.
#
# The old grading said `routing / :low / "…no RoutingDecision despite the gate"`
# for exactly that case, which tells an operator the gate was ON and the routing
# subsystem failed anyway — the opposite diagnosis — and grades an unmeasured
# dimension as a minor blemish, against the charter rule INC-5 already applied
# to `unavailable` project metrics ("not measured ≠ pass" ⇒ :medium).
#
# NOTE ON THE DETECTOR: re-reading `Ai::Routing::TaskTierResolver.enabled_for?`
# at grade time does NOT work, and the last example here pins that. The run that
# reaps a stale claim does so inside `enable_gate!`, which writes
# `GATE_SETTING = true` in the same locked write — so the gate reads ON through
# most of the window the check targets. The CLAIM is the observable.
RSpec.describe Ai::Provisioning::DryrunHarness do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:run_id)  { "gcx#{SecureRandom.hex(3)}" }

  def build_harness
    described_class.new(account: account, user: user,
                        objective: "dryrun-#{run_id}: grade the routing oracle",
                        run_id: run_id, cleanup: false)
  end

  # Parked at `adapting` — a DRIVE_COMPLETE_PHASES phase, so the M2 "never
  # reached adapting/completed" finding stays out of the way of what is under
  # test. custom_phases carries the provisioning phase list the real mission
  # template supplies live.
  def dryrun_mission
    create(:ai_mission, account: account, created_by: user,
                        name: "dryrun-#{run_id}", mission_type: "infrastructure",
                        status: "active", current_phase: "adapting", configuration: {},
                        custom_phases: [
                          { "key" => "capture_intent", "order" => 0 },
                          { "key" => "compose_plan", "order" => 1 },
                          { "key" => "review_plan", "order" => 2 },
                          { "key" => "execute", "order" => 3 },
                          { "key" => "verify", "order" => 4 },
                          { "key" => "handoff", "order" => 5 },
                          { "key" => "adapting", "order" => 6 }
                        ])
  end

  # The input condition the routing oracle fires on: LLM calls happened and no
  # RoutingDecision was recorded. Stubbed at the COUNT seam because neither
  # ai_agent_executions nor ai_routing_decisions carries a mission link — the
  # very reason those counts are account-wide (see the caveat example).
  def grade_with_executions(harness, mission)
    allow(harness).to receive(:execution_count).and_return(2)
    allow(harness).to receive(:routing_count).and_return(0)
    harness.send(:grade!, mission)
    harness.send(:build_result, mission)
  end

  def finding_for(result, dimension)
    result.findings.find { |f| f.dimension == dimension }
  end

  # What a CONCURRENT run's enable_gate! leaves behind when it reaps this run's
  # claim: our run_id dropped from the holder list, the gate itself still ON
  # because the reaper just claimed it.
  #
  # Written through a SEPARATE AR instance on purpose. Live, the reaper is
  # another process, so the harness's own `@account` still holds the settings it
  # wrote in enable_gate! — a detector that reads that in-memory hash sees its
  # own claim forever and detects nothing. Mutating the spec's `account` object
  # directly would hide that.
  def simulate_concurrent_reap!
    Account.find(account.id).update!(settings: account.reload.settings.merge(
      described_class::GATE_SETTING => true,
      described_class::GATE_HOLDERS_SETTING => { "otherrun" => Time.current.utc.iso8601 }
    ))
  end

  describe "the routing oracle when this run's gate claim was reaped" do
    it "names the REAP on its own dimension, at a 'not measured' severity" do
      harness = build_harness
      mission = dryrun_mission
      harness.send(:enable_gate!)
      simulate_concurrent_reap!

      result = grade_with_executions(harness, mission)
      observation = finding_for(result, "observation")

      expect(observation).to be_present,
        "a reaped gate claim left the routing dimension UNMEASURED and produced no finding for it"
      expect(observation.severity).to eq(:medium)
      expect(observation.detail).to match(/reap/i)
      expect(observation.detail).to match(/not measured|unmeasured/i)
    end

    it "does not tell the operator the gate was on and routing failed anyway" do
      harness = build_harness
      mission = dryrun_mission
      harness.send(:enable_gate!)
      simulate_concurrent_reap!

      result = grade_with_executions(harness, mission)

      expect(result.findings.map(&:detail).join(" ")).not_to match(/despite the gate/i),
        "the reaped case still asserts the gate was held — the opposite of what happened"
      expect(finding_for(result, "routing")).to be_nil,
        "an unmeasured dimension must not also be graded as a routing-subsystem defect"
    end

    it "detects the reap through the CLAIM, which a grade-time gate read cannot" do
      harness = build_harness
      mission = dryrun_mission
      harness.send(:enable_gate!)
      simulate_concurrent_reap!

      # The trap, pinned: the reaper's own enable_gate! left the gate ON, so a
      # grade-time `enabled_for?` read reports a healthy gate and detects nothing.
      expect(Ai::Routing::TaskTierResolver.enabled_for?(Account.find(account.id))).to be(true)

      expect(finding_for(grade_with_executions(harness, mission), "observation")).to be_present
    end

    it "keeps exit_code / passed? a pure function of the finding list" do
      harness = build_harness
      mission = dryrun_mission
      harness.send(:enable_gate!)
      simulate_concurrent_reap!

      result = grade_with_executions(harness, mission)

      expect(result.exit_code).to eq(result.findings.size)
      expect(result.passed?).to be(result.findings.empty?)
    end
  end

  describe "the routing oracle when this run still holds its gate claim" do
    it "still grades a genuinely missing RoutingDecision as a routing finding" do
      harness = build_harness
      mission = dryrun_mission
      harness.send(:enable_gate!)

      result = grade_with_executions(harness, mission)
      routing = finding_for(result, "routing")

      expect(routing).to be_present
      expect(routing.severity).to eq(:low)
      expect(routing.detail).to match(/2 LLM execution\(s\) but no RoutingDecision/)
      expect(finding_for(result, "observation")).to be_nil
    end

    it "declares that both counts are account-wide, not mission-scoped" do
      # Neither ai_agent_executions nor ai_routing_decisions carries a mission
      # link, so the S2 mission-scoping used for skill usage is unavailable here.
      # The alternative to scoping is saying so, the way the soak budget finding
      # already does.
      harness = build_harness
      mission = dryrun_mission
      harness.send(:enable_gate!)

      detail = finding_for(grade_with_executions(harness, mission), "routing").detail

      expect(detail).to match(/account-wide/i)
    end

    it "stays quiet when no LLM execution happened at all" do
      harness = build_harness
      mission = dryrun_mission
      harness.send(:enable_gate!)

      allow(harness).to receive(:execution_count).and_return(0)
      allow(harness).to receive(:routing_count).and_return(0)
      harness.send(:grade!, mission)
      result = harness.send(:build_result, mission)

      expect(finding_for(result, "routing")).to be_nil
      expect(finding_for(result, "observation")).to be_nil
    end
  end
end
