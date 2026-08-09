# frozen_string_literal: true

require "rails_helper"

# P2 — the headless dry-run harness. These specs prove the harness DRIVES a
# recognized provisioning brief end-to-end through the real pipeline
# (capture → synthesize → approve → execute → verify → grade) and, crucially,
# that its grading detects both a clean PASS and specific failure modes —
# because a harness that can't fail is worthless.
RSpec.describe Ai::Provisioning::DryrunHarness, type: :service do
  include PermissionTestHelpers

  let(:account)   { create(:account) }
  let(:user)      { user_with_permissions("ai.workflows.create", "ai.workflows.execute", account: account) }
  let(:arch)      { create(:system_node_architecture, :with_checksums) }
  let(:platform)  { create(:system_node_platform, account: account, node_architecture: arch) }
  let!(:template) { create(:system_node_template, account: account, node_platform: platform) }
  let!(:provider) { create(:system_provider, account: account, provider_type: "local_qemu") }
  let!(:region)   { create(:system_provider_region, account: account, provider: provider) }
  let!(:itype)    { create(:system_provider_instance_type, account: account, provider: provider) }
  let!(:agent)    { create(:ai_agent, account: account) }
  # The F5 skills oracle resolves by slug (system-<dashed>); seed the two the
  # synthesized plan uses so usage rows record.
  let!(:pfs_skill) { create(:ai_skill, account: account, name: "Provision Full Stack", slug: "system-provision-full-stack") }

  let(:run_id)    { "spec#{SecureRandom.hex(3)}" }
  let(:objective) { "dryrun-#{run_id}: provision a 3-node stack" }

  let(:brief) do
    {
      "intent" => "provision a 3-node stack", "use_case" => "validation smoke",
      "scale" => { "initial" => 3, "target" => 3, "growth_profile" => "steady" },
      "regions" => [ region.region_code ], "budget_cap_usd_monthly" => 5.0,
      "preferred_provider" => "local_qemu", "preferred_template" => template.name
    }
  end

  before do
    account
    load Rails.root.join("../extensions/system/server/db/seeds/system_provisioning_mission_template.rb")

    # Capture → the fixed brief (real extraction is exercised elsewhere).
    allow_any_instance_of(Ai::Provisioning::IntentCaptureService).to receive(:capture)
      .and_return(brief: brief, missing_fields: [])

    # Execute → the step jobs run in-process (mirror the m0 smoke).
    allow(WorkerJobService).to receive(:enqueue_job) do |job, payload|
      if job == "AiProvisioningStepJob"
        sid = payload.dig(:args, :step_id) || payload.dig("args", "step_id")
        @runner&.execute_step!(@runner.plan.steps.find { |s| s.id == sid })
      end
    end

    # provision_instance → a dryrun-prefixed running NodeInstance per node.
    allow(System::ProvisioningService).to receive(:provision_instance) do |**kwargs|
      node = kwargs[:node]
      ni = System::NodeInstance.create!(
        name: "#{node.name}-inst-#{SecureRandom.hex(2)}", node: node, variety: "cloud",
        status: "running", cloud_instance_id: "ci-#{SecureRandom.hex(4)}",
        provider_region_id: kwargs[:provider_region_id],
        provider_instance_type_id: kwargs[:provider_instance_type_id]
      )
      System::Runtime::Result.ok(data: { instance: ni, cloud_instance_id: ni.cloud_instance_id })
    end

    # Capture the runner instance so the WorkerJobService stub can reach it.
    allow(Ai::Provisioning::SkillCompositionRunner).to receive(:new).and_wrap_original do |orig, **kw|
      @runner = orig.call(**kw)
    end

    # Live verifier seam → healthy (real reconciliation is exercised elsewhere).
    verifier = double("verifier")
    allow(verifier).to receive(:reconcile_instances) do |expectations:, **|
      expectations.map { |e| { node_instance_id: e[:node_instance_id], ok: true, detail: "running" } }
    end
    allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
    allow(Powernode::ExtensionRegistry).to receive(:provider).with(:provision_verifier).and_return(verifier)
  end

  def harness(**opts)
    described_class.new(account: account, user: user, objective: objective, run_id: run_id,
                        cleanup: false, **opts)
  end

  describe "a clean run" do
    it "drives the mission to a PASS with exit code 0 and no findings" do
      result = harness.run

      expect(result.passed?).to be(true), "unexpected findings: #{result.findings.map(&:to_h)}"
      expect(result.exit_code).to eq(0)
      expect(result.oracles["instances"]).to eq(3)
      expect(result.oracles["skill_usage"]).to be > 0
      expect(result.oracles["verify_healthy"]).to be(true)
      expect(result.reached_phase).to eq("handoff").or eq("adapting")
    end

    it "names every instance under the dryrun-<runId> prefix (blast-radius rail)" do
      harness.run
      names = System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%").pluck(:name)
      expect(names.size).to eq(3)
    end

    it "enables the routing gate for the run and restores it afterward" do
      expect(account.settings[described_class::GATE_SETTING]).to be_nil
      harness.run
      expect(account.reload.settings[described_class::GATE_SETTING]).to be_nil
    end

    it "renders a markdown report" do
      md = harness.run.to_markdown
      expect(md).to include("PASS")
      expect(md).to include("instances")
    end
  end

  describe "failure detection" do
    it "flags an instance-count mismatch (the run-f class: plan != brief scale)" do
      # expected_count forces the grader to expect 5 while the brief yields 3.
      result = harness(expected_count: 5).run
      outcome = result.findings.select { |f| f.dimension == "outcome" }
      expect(outcome).not_to be_empty
      expect(outcome.first.detail).to match(%r{3 instances.*5})
      expect(result.exit_code).to be >= 1
    end

    it "flags an unhealthy verification and does not silently pass" do
      allow_any_instance_of(Ai::Provisioning::VerificationService).to receive(:verify)
        .and_return(healthy: false, checks: [ { name: "instance_x", ok: false, detail: "provider has no record" } ])

      result = harness.run
      expect(result.passed?).to be(false)
      expect(result.findings.map(&:dimension)).to include("verify")
    end

    it "flags a compose failure loudly instead of proceeding" do
      allow_any_instance_of(Ai::Provisioning::PlanComposerService).to receive(:compose!).and_return(nil)

      result = harness.run
      expect(result.findings.map(&:dimension)).to include("compose")
      expect(result.reached_phase).not_to eq("adapting")
    end
  end

  describe "safety" do
    it "refuses to approve a mission it did not mark dryrun" do
      # Rename the mission mid-flight to a non-dryrun name to prove the guard.
      allow_any_instance_of(Ai::Mission).to receive(:name).and_return("prod-mission")
      expect { harness.run }.to raise_error(/refusing to approve a non-dryrun/)
    end
  end
end
