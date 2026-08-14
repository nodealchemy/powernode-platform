# frozen_string_literal: true

require "rails_helper"
require "ostruct"

# IMP-1ee509d12a0a — a failed step could not compensate its OWN resources.
#
# The runner recorded step outputs only via mark_completed -> record_outputs,
# so `metadata["last_outputs"]` existed only for steps that SUCCEEDED. On a
# first-run failure handle_failure discarded the failure envelope entirely and
# rollback_step! sourced its kwargs from that (absent) key — so the executor's
# rollback hook fired with EMPTY kwargs, no-opped, and mark_rolled_back then
# stamped `rolled_back` over still-live resources while OVERWRITING the
# result_summary that held the failure diagnosis.
#
# Composers stamp on_failure: "rollback" by default (AdaptationProposerService,
# PlanComposerService), so this is the norm, not the exception.
#
# The fake executor here mirrors a REAL contract that is live today:
# System::Ai::Skills::DeployAppCodeExecutor returns
# `failure(err, deployment_id: deployment.id)` after creating the deployment
# row, and declares `rollback_deploy_app_code(deployment_id:, node_instance_ids:,
# **_extras)`. The id it needs is in the envelope; the runner threw it away.
RSpec.describe Ai::Provisioning::SkillCompositionRunner, "failure-time outputs for rollback" do
  let(:account)      { instance_double("Account", id: "acc-uuid-1") }
  let(:conversation) { instance_double("Ai::Conversation") }
  let(:mission)      { instance_double("Ai::Mission", id: "mission-uuid-1", conversation: conversation) }

  # Real fake class (not an anonymous double) so verify_partial_doubles is
  # honest about the methods we call. Rollback declares the SAME kwargs the
  # live deploy_app_code hook declares.
  let(:fake_executor_class) do
    Class.new do
      class << self
        attr_accessor :execute_result, :rollback_calls, :rollback_result
      end

      def self.descriptor
        { name: "deploy_app_code", rollback: :rollback }
      end

      def initialize(account: nil)
        @account = account
      end

      def execute(**_inputs)
        result = self.class.execute_result
        raise result if result.is_a?(Exception)
        result || { success: true, data: {} }
      end

      def rollback(deployment_id: nil, node_instance_ids: [], **_extras)
        self.class.rollback_calls ||= []
        self.class.rollback_calls << { deployment_id: deployment_id, node_instance_ids: node_instance_ids }
        self.class.rollback_result || { success: true }
      end
    end
  end

  let(:step) { build_step(id: "step-1", step_number: 1, skill: "deploy_app_code", on_failure: "rollback") }
  let(:plan) { OpenStruct.new(id: "plan-1", steps: FailureRollbackPlanSteps.new([step])) }

  subject(:runner) { described_class.new(account: account, mission: mission, plan: plan) }

  before do
    fake_executor_class.execute_result = nil
    fake_executor_class.rollback_calls = []
    fake_executor_class.rollback_result = nil

    allow(MissionChannel).to receive(:broadcast_mission_event)
    allow(conversation).to receive(:add_system_message)
    allow(WorkerJobService).to receive(:enqueue_job)
    allow(runner).to receive(:resolve_executor).with("deploy_app_code").and_return(fake_executor_class)
  end

  # ---------------------------------------------------------------------------
  # 1. The behavioral core: a failure envelope that CARRIES a resource id must
  #    reach the rollback hook.
  # ---------------------------------------------------------------------------
  describe "a first-run failure whose envelope carries its own resource id" do
    before do
      # Byte-for-byte the deploy_app_code failure shape (executor :186).
      fake_executor_class.execute_result = {
        success: false, error: "deploy script exited 1", deployment_id: "dep-77"
      }
    end

    it "hands the failed step's own resource id to its rollback hook" do
      runner.execute_step!(step)

      expect(fake_executor_class.rollback_calls.size).to eq(1)
      expect(fake_executor_class.rollback_calls.last[:deployment_id]).to eq("dep-77")
    end

    it "persists the failure-time outputs on the step so a re-entry can still see them" do
      runner.execute_step!(step)

      expect(step.metadata["failure_outputs"]).to be_present
      # Executor-supplied keys are stored VERBATIM, exactly as record_outputs
      # stores last_outputs: jsonb stringifies them on reload, and every reader
      # goes through symbolize. This double never round-trips, so the symbols
      # the executor returned survive — assert key-agnostically rather than
      # pinning an artifact of the double.
      outputs = step.metadata.dig("failure_outputs", "outputs")
      expect(outputs.transform_keys(&:to_s)).to include("deployment_id" => "dep-77")
    end

    it "still reports the step failed with its error (never-raise contract intact)" do
      result = runner.execute_step!(step)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("deploy script exited 1")
      expect(step.status).to eq("failed")
    end
  end

  describe "a failure envelope carrying a nested outputs sub-hash and a failures array" do
    before do
      fake_executor_class.execute_result = {
        success: false,
        error: "2 of 3 legs failed",
        outputs: { "node_instance_ids" => %w[i-1 i-2] },
        failures: [{ "resource" => "node_instance", "error" => "no capacity" }]
      }
    end

    it "flattens the nested outputs so the hook receives flat kwargs" do
      runner.execute_step!(step)

      expect(fake_executor_class.rollback_calls.last[:node_instance_ids]).to eq(%w[i-1 i-2])
    end

    it "records the failures array alongside the outputs" do
      runner.execute_step!(step)

      expect(step.metadata.dig("failure_outputs", "failures"))
        .to eq([{ "resource" => "node_instance", "error" => "no capacity" }])
    end
  end

  # A payload that merely EXISTS is not a payload that can be acted on. An
  # envelope reporting only why its legs failed carries no ids, so it must
  # neither count as compensation nor displace what a prior run recorded.
  describe "a failure envelope carrying leg failures but NO resource ids" do
    before do
      step.metadata = { "last_outputs" => { "outputs" => { "deployment_id" => "dep-prior" } } }
      fake_executor_class.execute_result = {
        success: false,
        error: "all 3 legs refused",
        failures: [{ "resource" => "node_instance", "error" => "no capacity" }]
      }
    end

    it "does not let the id-less payload shadow the retried step's real outputs" do
      runner.execute_step!(step)

      expect(fake_executor_class.rollback_calls.last[:deployment_id]).to eq("dep-prior")
    end

    it "records the failures for diagnosis even though they are not a rollback source" do
      runner.execute_step!(step)

      expect(step.metadata.dig("failure_outputs", "failures")).to be_present
      expect(step.metadata.dig("failure_outputs", "outputs")).to be_nil
    end
  end

  describe "a failure envelope with leg failures, no ids, and nothing recorded earlier" do
    before do
      fake_executor_class.execute_result = {
        success: false,
        error: "all 3 legs refused",
        failures: [{ "resource" => "node_instance", "error" => "no capacity" }]
      }
    end

    it "is a no-op rollback and keeps the failure diagnosis" do
      runner.execute_step!(step)

      expect(step.result_summary[:noop]).to be true
      expect(step.result_summary[:failure]).to eq("all 3 legs refused")
    end
  end

  # A recorded outputs hash whose resource slots are all empty is also not
  # compensation: composers record their whole `data` hash, so bookkeeping keys
  # (dry_run, count, planned_actions) sit beside the ids and would otherwise
  # make any rollback look like it did work.
  describe "a recorded outputs hash whose resource values are all blank" do
    before do
      step.metadata = { "last_outputs" => {
        "dry_run" => false, "count" => 0,
        "outputs" => { "deployment_id" => nil, "created" => false }
      } }
      fake_executor_class.execute_result = { success: false, error: "provider refused" }
    end

    it "is a no-op rollback and keeps the failure diagnosis" do
      runner.execute_step!(step)

      expect(step.result_summary[:noop]).to be true
      expect(step.result_summary[:failure]).to eq("provider refused")
    end
  end

  # The composers finalize into { dry_run:, count:, planned_actions:, outputs:,
  # failures:, partial: }. The first executor to return that shape on
  # success: false must not read as compensation just because the hash is big.
  describe "a failure envelope declaring a composer-shaped data hash with no ids" do
    before do
      fake_executor_class.execute_result = {
        success: false,
        error: "every leg refused",
        data: {
          "dry_run" => false, "count" => 2,
          "planned_actions" => [{ "step" => "create_node" }],
          "outputs" => { "node_instance_ids" => [], "storage_volume_ids" => [] },
          "failures" => [{ "error" => "no capacity" }], "partial" => false
        }
      }
    end

    it "does not mistake bookkeeping keys for compensable resources" do
      runner.execute_step!(step)

      expect(step.result_summary[:noop]).to be true
      expect(step.result_summary[:failure]).to eq("every leg refused")
    end
  end

  describe "a failure envelope declaring a composer-shaped data hash WITH ids" do
    # Positive twin: the same shape, ids actually present, must compensate.
    before do
      fake_executor_class.execute_result = {
        success: false,
        error: "1 of 2 legs failed",
        data: {
          "dry_run" => false, "count" => 2,
          "outputs" => { "node_instance_ids" => %w[i-1] },
          "failures" => [{ "error" => "no capacity" }], "partial" => true
        }
      }
    end

    it "hands the ids to the hook and does not flag a no-op" do
      runner.execute_step!(step)

      expect(fake_executor_class.rollback_calls.last[:node_instance_ids]).to eq(%w[i-1])
      expect(step.result_summary[:noop]).to be_nil
    end
  end

  describe "a declared data hash carrying an envelope control key beside an empty id" do
    before do
      fake_executor_class.execute_result = {
        success: false, error: "nothing provisioned",
        data: { "partial" => true, "deployment_id" => nil }
      }
    end

    it "does not count an envelope control key as a resource" do
      runner.execute_step!(step)

      expect(step.result_summary[:noop]).to be true
      expect(step.result_summary[:failure]).to eq("nothing provisioned")
    end
  end

  # ---------------------------------------------------------------------------
  # 2. The diagnosis must survive a no-op rollback.
  #
  # NOTE on shape: `result_summary` is a `t.text` column, so in production the
  # marker Hash is coerced by #to_s and the diagnosis survives as TEXT — the
  # structural `result_summary[:failure]` reads below work only because the
  # fake step is an OpenStruct that stores the Hash raw (String#[] with a
  # Symbol would raise TypeError). They are valid discriminators for WHAT is
  # carried; they are not a claim that production returns a Hash. Storing a
  # Hash here is pre-existing mark_rolled_back behavior, deliberately unchanged.
  # ---------------------------------------------------------------------------
  describe "when the rollback compensates NOTHING" do
    before do
      # A bare failure(msg) envelope — validation refused before anything was
      # created. This is also relocate_workload's refusal shape.
      fake_executor_class.execute_result = { success: false, error: "blue_green cutover refused: undersized" }
    end

    it "preserves the failure diagnosis instead of overwriting it with the rolled_back marker" do
      runner.execute_step!(step)

      expect(step.result_summary[:failure]).to eq("blue_green cutover refused: undersized")
    end

    it "still records that a rollback ran, and marks it a no-op" do
      runner.execute_step!(step)

      expect(step.result_summary[:rolled_back]).to be true
      expect(step.result_summary[:noop]).to be true
    end
  end

  describe "when the rollback genuinely compensated resources" do
    # Positive twin for the no-op examples above: the marker shape that
    # existed before this change must be unchanged when work was actually done.
    before do
      fake_executor_class.execute_result = { success: false, error: "boom", deployment_id: "dep-9" }
    end

    it "does NOT flag the rollback as a no-op" do
      runner.execute_step!(step)

      expect(step.result_summary[:rolled_back]).to be true
      expect(step.result_summary[:noop]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Guards against a WRONG fix (these are green pre-change by construction —
  #    they are mutation-verified against deliberate mis-implementations, not
  #    against reverting the change. See the report for the two mutants used).
  # ---------------------------------------------------------------------------
  describe "a bare failure envelope must not shadow a retried step's real outputs" do
    before do
      # The retry shape: a prior run partially succeeded and recorded ids;
      # this run refused during validation and created nothing. The envelope
      # carries ONLY control keys — capturing it verbatim (e.g. via the
      # to_h fallback in result_outputs) would shadow last_outputs and the
      # live resources would survive their own rollback.
      step.metadata = { "last_outputs" => { "outputs" => { "deployment_id" => "dep-prior" } } }
      fake_executor_class.execute_result = { success: false, error: "missing required input: repo_url" }
    end

    it "still rolls back the resources recorded by the earlier partial success" do
      runner.execute_step!(step)

      expect(fake_executor_class.rollback_calls.last[:deployment_id]).to eq("dep-prior")
    end

    it "writes no failure_outputs key when the envelope carries no resource data" do
      runner.execute_step!(step)

      expect(step.metadata).not_to have_key("failure_outputs")
    end
  end

  # The three describes below are NON-REGRESSION guards, not discriminators:
  # they pin invariants this change was required to preserve (never-raise
  # contract, the raise arm's behavior, a byte-identical success path). None of
  # them reds under the three wrong-fix mutants used to verify the guards above
  # — they only red if the change breaks something it was meant to leave alone.
  describe "an executor that RAISES records nothing new" do
    before do
      step.metadata = { "last_outputs" => { "outputs" => { "deployment_id" => "dep-prior" } } }
      fake_executor_class.execute_result = StandardError.new("provider 500")
    end

    it "leaves last_outputs as the rollback source (there is no envelope to read)" do
      runner.execute_step!(step)

      expect(step.metadata).not_to have_key("failure_outputs")
      expect(fake_executor_class.rollback_calls.last[:deployment_id]).to eq("dep-prior")
    end
  end

  describe "the success path" do
    before do
      fake_executor_class.execute_result = { success: true, data: { "deployment_id" => "dep-ok" } }
      allow(runner).to receive(:advance_mission_if_dag_complete!)
    end

    it "records last_outputs and no failure payload" do
      runner.execute_step!(step)

      expect(step.status).to eq("completed")
      expect(step.metadata["last_outputs"]).to eq({ "deployment_id" => "dep-ok" })
      expect(step.metadata).not_to have_key("failure_outputs")
    end

    it "never invokes the rollback hook" do
      runner.execute_step!(step)

      expect(fake_executor_class.rollback_calls).to be_empty
    end
  end

  describe "cross-step data flow" do
    it "does not feed a failed step's failure payload to a successor's depends_on_outputs" do
      # recorded_outputs_for backs BOTH rollback kwargs and upstream_outputs_for.
      # The failure payload must be visible only to the rollback path, or a
      # successor would inherit ids belonging to a step that failed.
      fake_executor_class.execute_result = { success: false, error: "boom", deployment_id: "dep-77" }
      runner.execute_step!(step)

      expect(runner.send(:recorded_outputs_for, step)).to eq({})
    end
  end

  # ---------------------------------------------------------------------------

  def build_step(id:, step_number:, skill:, on_failure:)
    OpenStruct.new(
      id: id,
      step_number: step_number,
      dependencies: [],
      execution_config: { "skill" => skill, "inputs" => {}, "on_failure" => on_failure },
      status: "pending",
      metadata: {},
      result_summary: nil
    ).tap do |s|
      def s.update!(attrs)
        attrs.each { |k, v| public_send("#{k}=", v) }
      end
    end
  end

  # Deliberately NOT named PlanSteps: `class Foo` inside a block binds at
  # top level, so a second definition would reopen the sibling spec's class
  # and leave each file depending on the other's load order for methods it
  # never declared.
  class FailureRollbackPlanSteps
    include Enumerable
    def initialize(steps) = @steps = steps
    def each(&block) = @steps.each(&block)
    def in_order = @steps.sort_by { |s| s.step_number.to_i }
  end
end
