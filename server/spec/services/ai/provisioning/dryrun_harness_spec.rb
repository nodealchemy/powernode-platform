# frozen_string_literal: true

require "rails_helper"

# P2 — the headless dry-run harness, OBSERVER MODE.
#
# The harness is a supervisor: it creates a dryrun mission, then lets the REAL
# pipeline self-drive while it approves its own gates and grades the outcome.
# These specs prove that by driving the pipeline exactly as the standalone
# worker does in production — each AiProvisioning*Job is dispatched to the real
# internal ProvisioningController endpoints (`worker_pump`), so a regression in
# the controllers, the runner, or F6 auto-advance surfaces here instead of
# hiding behind a parallel in-process reimplementation.
#
# The only seam that differs from live is WHO pumps the async work: live it's
# the standalone worker over HTTP; here it's `worker_pump`, which drains the
# enqueued jobs by POSTing to the same endpoints, synchronously, one at a time.
RSpec.describe Ai::Provisioning::DryrunHarness, type: :request do
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
  # The F5 skills oracle resolves by slug (system-<dashed>); seed the one the
  # synthesized plan uses so usage rows record.
  let!(:pfs_skill) { create(:ai_skill, account: account, name: "Provision Full Stack", slug: "system-provision-full-stack") }

  # mTLS worker identity so the pump can reach the internal endpoints.
  let!(:worker) { create(:worker, account: account) }
  let(:service_headers) do
    {
      "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")),
      "Content-Type" => "application/json"
    }
  end

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

  # The enqueue queue the worker_pump drains. The harness never touches it — it
  # only calls the pump between phase polls.
  let(:pump_queue) { [] }

  # Faithful stand-in for the standalone worker: POST each enqueued
  # AiProvisioning*Job to its real internal endpoint, FIFO, until drained.
  # Returns the count processed so the harness can detect a stall.
  let(:worker_pump) do
    lambda do
      processed = 0
      until pump_queue.empty?
        job = pump_queue.shift
        url, body = endpoint_for(job)
        next if url == :ignore

        post url, params: body.to_json, headers: service_headers
        # S2: fail loudly on a BROKEN pump — auth (401/403), routing (404), or a
        # server crash (5xx) — so a wiring regression can't hide as an
        # inscrutable downstream "parked at X". A 422 is NOT pump breakage: it is
        # the pipeline legitimately reporting a domain failure (composer nil,
        # unhealthy verify), which the harness is meant to observe via mission
        # state, so it is allowed through.
        expect([ 401, 403, 404 ]).not_to include(response.status),
          "pump POST #{url} → #{response.status}: #{response.body}"
        expect(response.status).to be < 500,
          "pump POST #{url} → #{response.status}: #{response.body}"
        processed += 1
      end
      processed
    end
  end

  # S2: raise on an unmapped job rather than silently dropping it — a new phase
  # job must force a decision here, not vanish.
  def endpoint_for(job)
    mid = job[:args]["mission_id"]
    base = "/api/v1/internal/ai/provisioning/missions/#{mid}"
    case job[:klass]
    when "AiProvisioningCaptureIntentJob" then [ "#{base}/capture_intent", {} ]
    when "AiProvisioningComposePlanJob"   then [ "#{base}/compose_plan", {} ]
    when "AiProvisioningExecuteJob"       then [ "#{base}/execute", {} ]
    when "AiProvisioningVerifyJob"        then [ "#{base}/verify", {} ]
    when "AiProvisioningHandoffJob"       then [ "#{base}/handoff", {} ]
    when "AiProvisioningStepJob"
      [ "#{base}/steps/#{job[:args]['step_id']}/execute", { runner_id: job[:args]["runner_id"] } ]
    when "AiMissionCleanupJob" then [ :ignore, nil ] # dispatched by cancel! on teardown
    else raise "worker_pump: unmapped job #{job[:klass].inspect} — map it or the coverage claim is false"
    end
  end

  before do
    account
    load Rails.root.join("../extensions/system/server/db/seeds/system_provisioning_mission_template.rb")

    # Capture → the fixed brief (real extraction is exercised elsewhere). The
    # capture CONTROLLER calls this and persists the brief itself.
    allow_any_instance_of(Ai::Provisioning::IntentCaptureService).to receive(:capture)
      .and_return(brief: brief, missing_fields: [])

    # Worker dispatch → enqueue into the pump queue (drained by worker_pump).
    allow(WorkerJobService).to receive(:enqueue_job) do |*positional, **kwargs|
      args = kwargs[:args]
      args = args.first if args.is_a?(Array)
      pump_queue << { klass: positional.first, args: (args || {}).deep_stringify_keys }
      true
    end

    # provision_instance → a dryrun-prefixed running NodeInstance per node
    # (the lower provider chain is exercised elsewhere).
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
                        cleanup: false, phase_pump: worker_pump,
                        compose_timeout: 30, execute_timeout: 60, **opts)
  end

  describe "a clean run" do
    it "supervises the mission to a PASS with exit code 0 and no findings" do
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
      expect(result.reached_phase).not_to eq("adapting")
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

    it "rejects a run_id carrying a SQL LIKE metacharacter (teardown blast-radius rail)" do
      expect { described_class.new(account: account, user: user, objective: objective, run_id: "%", cleanup: false) }
        .to raise_error(ArgumentError, /run_id must be alphanumeric/)
    end

    it "refuses to start a second live dryrun mission for the same account" do
      # A prior live dryrun mission is present → the new run must refuse rather
      # than risk a teardown that crosses blast radius.
      Ai::Mission.create!(account: account, created_by: user, mission_type: "infrastructure",
                          name: "dryrun-prior", objective: "prior", status: "draft")
      expect { harness.run }.to raise_error(/live dryrun mission already exists/)
    end
  end
end
