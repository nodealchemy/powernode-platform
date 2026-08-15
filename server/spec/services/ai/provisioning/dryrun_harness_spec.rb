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

    it "refuses to start a run whose blast radius overlaps a live dryrun mission" do
      # Same prefix ⇒ the two runs' teardown sweeps ('dryrun-<runId>%') would
      # each catch the other's instances. That, not "another dryrun exists", is
      # the property the guard defends — a soaking baseline must not block an
      # unrelated run.
      Ai::Mission.create!(account: account, created_by: user, mission_type: "infrastructure",
                          name: "dryrun-#{run_id}", objective: "prior", status: "active")
      expect { harness.run }.to raise_error(/overlaps the blast radius/)
    end

    it "refuses a run whose prefix is SUBSUMED by a live dryrun mission's prefix" do
      # 'dryrun-spec' LIKE-matches every instance of 'dryrun-spec<hex>'.
      Ai::Mission.create!(account: account, created_by: user, mission_type: "infrastructure",
                          name: "dryrun-#{run_id[0, 4]}", objective: "prior", status: "active")
      expect { harness.run }.to raise_error(/overlaps the blast radius/)
    end

    it "refuses to start when a RETAINED neighbour's fleet is inside this run's sweep" do
      # The asymmetric direction: run `<runId>` was retained with --no-cleanup,
      # so its instances are named `dryrun-<runId>-…`, which a longer-prefixed
      # run cannot see by its own prefix query — but the retained run's later
      # teardown WOULD sweep this one's fleet.
      Ai::Mission.create!(account: account, created_by: user, mission_type: "infrastructure",
                          name: "dryrun-#{run_id}", objective: "retained", status: "cancelled")
      node = create(:system_node, account: account, node_template: template)
      create(:system_node_instance, account: account, node: node,
                                    name: "dryrun-#{run_id}-retained-inst-01", status: "running")

      longer = described_class.new(account: account, user: user, objective: objective,
                                   run_id: "#{run_id}extra", cleanup: false, phase_pump: worker_pump)

      expect { longer.run }.to raise_error(/overlaps the blast radius of the retained fleet/)
    end

    it "refuses to start inside a standing fleet, even with no live mission" do
      # A `--no-cleanup` neighbour leaves instances that outlive its mission, and
      # the sweep acts on INSTANCES. A mission-only guard would let this run
      # start, mis-grade the neighbour's fleet as its own, and then terminate it.
      node = create(:system_node, account: account, node_template: template)
      create(:system_node_instance, account: account, node: node,
                                    name: "dryrun-#{run_id}-leftover-inst-01", status: "running")

      expect { harness.run }.to raise_error(/overlaps the blast radius/)
    end

    it "allows a run alongside a live dryrun mission whose prefix cannot overlap" do
      # The INC-5 coexistence case: a soaking baseline under a different run_id
      # neither blocks this run nor is touched by it.
      other = Ai::Mission.create!(account: account, created_by: user, mission_type: "infrastructure",
                                  name: "dryrun-otherbaseline", objective: "prior", status: "active")

      result = harness.run

      expect(result.oracles["instances"]).to eq(3)
      expect(other.reload.status).to eq("active")
    end
  end

  # ---- INC-5: soak mode ---------------------------------------------------
  #
  # A soak leaves the mission ACTIVE at `adapting` — a LIVE phase, per the
  # mission template ("long-lived, sensor-driven, no job class") — so the
  # evolution lane has something to watch. The observation lane's production
  # driver is the standalone worker's 60s cron POST to
  # /api/v1/system/worker_api/fleet/reconcile, whose only work is
  # FleetAutonomyService.tick! per account. `soak_pump` stands in for that cron
  # the same way `worker_pump` stands in for the job queue: it calls the REAL
  # service, then drains whatever the tick enqueued.
  describe "soak mode" do
    # tick! resolves this agent by name/type; without it the tick no-ops and
    # nothing observes anything.
    let!(:fleet_agent) do
      create(:ai_agent, account: account, name: "Fleet Autonomy", agent_type: "monitor")
    end

    # Mid-soak ground truth: what the row ACTUALLY said each time the
    # observation lane ran, read uncached, not what the harness reports later.
    let(:observed_states) { [] }

    let(:soak_pump) do
      lambda do
        m = Ai::Mission.uncached { Ai::Mission.find_by(name: "dryrun-#{run_id}") }
        observed_states << { status: m&.status, phase: m&.current_phase }
        System::Fleet::FleetAutonomyService.tick!(account: account)
        worker_pump.call
      end
    end

    # Teardown seam — the provider chain is exercised elsewhere (mirrors the
    # provision_instance stand-in above).
    before do
      allow_any_instance_of(System::ProvisioningService).to receive(:terminate_instance) do |_svc, kwargs|
        inst = kwargs.is_a?(Hash) ? kwargs[:instance] : kwargs
        inst.update!(status: "terminated")
        System::Runtime::Result.ok
      end
    end

    def soak_harness(**opts)
      harness(soak: true, soak_pump: soak_pump, soak_max_iterations: 2, **opts)
    end

    it "holds the mission ACTIVE at adapting for the whole soak window" do
      result = soak_harness.run

      expect(observed_states.size).to eq(2)
      expect(observed_states.map { |s| s[:status] }.uniq).to eq([ "active" ])
      expect(observed_states.map { |s| s[:phase] }.uniq).to eq([ "adapting" ])
      expect(result.oracles["soak_stop_reason"]).to eq("max_iterations")
      expect(result.oracles["soak_iterations"]).to eq(2)
    end

    it "is picked up by the sensor's own mission scope — ground-truth metric rows" do
      result = soak_harness.run

      rows = System::ProjectMetric.where(mission_id: result.mission_id)
      expect(rows.count).to be > 0
      expect(result.oracles["soak_metric_samples"]).to eq(rows.count)
      expect(rows.pluck(:metric_name)).to include("replica_count")
      # Provenance, not just presence: a `tick:` correlation id can only have
      # been stamped by FleetAutonomyService.tick! — the same pass that runs
      # ProjectSloSensor over the same `status: "active"` mission scope. A row
      # written by a hand-called collector would carry `project_metrics:`.
      expect(rows.pluck(:correlation_id).uniq).to all(start_with("tick:"))
    end

    # IMP-3431f73dabe6. This example used to assert `soak_live_metrics == 0` and
    # a /none from a live/ finding. That was not a property of the harness — it
    # was ProjectMetricsCollector's wrong dig path (`last_outputs.
    # node_instance_ids`, a shape nothing has ever written) showing through as
    # an expectation. With the collector reading the path SkillCompositionRunner
    # actually records, the soak observes real samples through the production
    # tick, so the gap this example used to grade is gone. The grading branch
    # itself is still real and is covered by the example below it.
    it "records LIVE metric samples once the collector can resolve the mission's instances" do
      result = soak_harness.run

      expect(result.oracles["soak_live_metrics"]).to be > 0
      expect(result.oracles["soak_live_metrics"]).to be <= result.oracles["soak_metric_samples"]
      expect(result.findings.select { |f| f.dimension == "observation" }).to be_empty
    end

    it "grades the observation gap when every sample really is unavailable" do
      # Force the precondition the grading branch exists for — a mission whose
      # provisioned instances cannot be resolved (a plan that recorded no
      # outputs) — rather than relying on a defect to supply it.
      allow_any_instance_of(System::ProjectMetricsCollector)
        .to receive(:resolvable_instance_ids).and_return([])

      result = soak_harness.run

      expect(result.oracles["soak_metric_samples"]).to be > 0
      expect(result.oracles["soak_live_metrics"]).to eq(0)
      obs = result.findings.select { |f| f.dimension == "observation" }
      expect(obs).not_to be_empty
      expect(obs.first.detail).to match(/none from a live/)
    end

    it "ends on the ITERATION ceiling taken from config, with no explicit bound" do
      SiteSetting.set("ai.dryrun.soak_max_iterations", 1, setting_type: "integer")

      result = harness(soak: true, soak_pump: soak_pump).run

      expect(observed_states.size).to eq(1)
      expect(result.oracles["soak_stop_reason"]).to eq("max_iterations")
    end

    it "ends on the DURATION ceiling taken from config" do
      SiteSetting.set("ai.dryrun.soak_max_seconds", 1, setting_type: "integer")
      slow_pump = lambda do
        soak_pump.call
        sleep(1.1)
        1
      end

      result = harness(soak: true, soak_pump: slow_pump, soak_max_iterations: 50).run

      expect(result.oracles["soak_stop_reason"]).to eq("max_seconds")
      expect(observed_states.size).to eq(1)
    end

    it "hands the routing gate back to the ACCOUNT, not to a concurrent run" do
      # Coexistence made capture-and-restore unsafe: a second run that starts
      # mid-soak captures the FIRST run's `true` as the account's own value, and
      # whichever finishes last writes it back — leaving the gate permanently
      # enabled, the exact hazard the README warns about, on the happy path.
      # A real second run is driven to completion inside the soak window.
      expect(account.settings[described_class::GATE_SETTING]).to be_nil
      gate_after_second_run = nil

      concurrent = lambda do
        soak_pump.call
        next 1 if gate_after_second_run

        described_class.new(account: account, user: user, objective: "dryrun-other run",
                            run_id: "other#{SecureRandom.hex(3)}", cleanup: false,
                            phase_pump: worker_pump, compose_timeout: 30, execute_timeout: 60).run
        # The first run is still soaking, so its gate must survive the second
        # run's restore.
        gate_after_second_run = account.reload.settings[described_class::GATE_SETTING]
        1
      end

      harness(soak: true, soak_pump: concurrent, soak_max_iterations: 2).run

      expect(gate_after_second_run).to be(true)
      settings = account.reload.settings
      expect(settings[described_class::GATE_SETTING]).to be_nil
      expect(settings).not_to have_key(described_class::GATE_HOLDERS_SETTING)
      expect(settings).not_to have_key(described_class::GATE_PRIOR_SETTING)
    end

    it "survives the interleaving where the FIRST run out is the one that captured nil" do
      # The ordering the nested-run example above cannot produce, and the only
      # one that actually corrupts the account: A captures the account's `nil`,
      # B then captures A's `true`, A finishes first (deleting the key under a
      # still-running B), and B finishes last (writing `true` back for good).
      # Driven through the gate pair directly because a nested run always
      # finishes before its host.
      a = harness
      b = described_class.new(account: account, user: user, objective: objective,
                              run_id: "other#{SecureRandom.hex(3)}", cleanup: false)

      a.send(:enable_gate!)
      b.send(:enable_gate!)

      a.send(:restore_gate!)
      expect(account.reload.settings[described_class::GATE_SETTING]).to be(true),
             "the first run out dropped the gate under a still-running second run"

      b.send(:restore_gate!)
      settings = account.reload.settings
      expect(settings[described_class::GATE_SETTING]).to be_nil
      expect(settings).not_to have_key(described_class::GATE_HOLDERS_SETTING)
      expect(settings).not_to have_key(described_class::GATE_PRIOR_SETTING)
    end

    it "does not let a hard-killed run's stale claim latch the gate on forever" do
      # A SIGKILL skips the ensure, leaving a holder whose mission never goes
      # terminal-or-live in any useful sense. If that claim were honoured, every
      # later restore would take the "someone is still running" arm and NO run
      # would ever hand the gate back — worse than the hazard it replaced.
      account.update!(settings: account.settings.merge(
        described_class::GATE_SETTING => true,
        described_class::GATE_PRIOR_SETTING => nil,
        described_class::GATE_HOLDERS_SETTING => { "deadrun" => 2.days.ago.utc.iso8601 }
      ))

      soak_harness.run

      settings = account.reload.settings
      expect(settings[described_class::GATE_SETTING]).to be_nil
      expect(settings).not_to have_key(described_class::GATE_HOLDERS_SETTING)
      expect(settings).not_to have_key(described_class::GATE_PRIOR_SETTING)
    end

    it "still refuses to approve a non-dryrun mission in soak mode" do
      allow_any_instance_of(Ai::Mission).to receive(:name).and_return("prod-mission")
      expect { soak_harness.run }.to raise_error(/refusing to approve a non-dryrun/)
    end

    it "cancels the mission and sweeps the prefix at the END of the soak" do
      result = soak_harness(cleanup: true).run

      # Active throughout the window, terminal only afterwards.
      expect(observed_states.map { |s| s[:status] }.uniq).to eq([ "active" ])
      expect(Ai::Mission.find(result.mission_id).status).to eq("cancelled")
      names = System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%")
      expect(names.count).to eq(3)
      expect(names.pluck(:status).uniq).to eq([ "terminated" ])
      expect(result.findings.map(&:dimension)).not_to include("teardown")
    end

    it "HALTS before teardown when the actuator recorded an orphan (forensics survive)" do
      # The removal actuator runs its own post-teardown ground-truth sweep and
      # records what survived under outputs.orphans. One appears mid-soak.
      orphaned = false
      halting_pump = lambda do
        soak_pump.call
        next 1 if orphaned

        orphaned = true
        mission = Ai::Mission.find_by(name: "dryrun-#{run_id}")
        plan = Ai::GoalPlan.find(mission.configuration.dig("plan", "plan_id"))
        step = plan.steps.order(:step_number).last
        step.update!(metadata: (step.metadata || {}).merge(
          "last_outputs" => { "outputs" => { "orphans" => [ { "resource" => "sdwan_peer", "ids" => %w[peer-1] } ] } }
        ))
        1
      end

      result = harness(soak: true, soak_pump: halting_pump, soak_max_iterations: 2, cleanup: true).run

      orphan = result.findings.select { |f| f.dimension == "orphan" }
      expect(orphan).not_to be_empty
      expect(orphan.first.detail).to match(/sdwan_peer/)
      # The sweep did NOT run: the fleet still matches the plan.
      expect(System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%").pluck(:status).uniq)
        .to eq([ "running" ])
    end

    it "HALTS before teardown on a volume still attached to a terminated replica" do
      # The independent reader: core sees the dangling attachment itself rather
      # than taking the actuator's word for the sweep.
      killed = false
      halting_pump = lambda do
        soak_pump.call
        next 1 if killed

        killed = true
        victim = System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%").order(:created_at).last
        victim.update!(status: "terminated")
        create(:system_provider_volume, account: account, provider_region: region,
                                        node_instance_id: victim.id, status: "in-use")
        1
      end

      result = harness(soak: true, soak_pump: halting_pump, soak_max_iterations: 2, cleanup: true).run

      expect(result.findings.map(&:dimension)).to include("orphan")
      expect(System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%")
                                 .where.not(status: "terminated").count).to eq(2)
    end

    it "still reports an orphan under --no-cleanup, where there is no sweep to halt" do
      # The halt is the consequence; the ORACLE is the point. A retained run is
      # exactly the forensics case, so it must not be the one that says nothing.
      reported = false
      pump = lambda do
        soak_pump.call
        next 1 if reported

        reported = true
        mission = Ai::Mission.find_by(name: "dryrun-#{run_id}")
        plan = Ai::GoalPlan.find(mission.configuration.dig("plan", "plan_id"))
        step = plan.steps.order(:step_number).last
        step.update!(metadata: (step.metadata || {}).merge(
          "last_outputs" => { "outputs" => { "orphans" => [ { "resource" => "provider_volume", "ids" => %w[v-1] } ] } }
        ))
        1
      end

      result = harness(soak: true, soak_pump: pump, soak_max_iterations: 2, cleanup: false).run

      expect(result.findings.map(&:dimension)).to include("orphan")
    end

    it "terminalizes the pipeline but leaves the fleet standing under --no-cleanup" do
      result = soak_harness(cleanup: false).run

      # M2 posture unchanged: the mission is always terminalized on the way out,
      # so no soak keeps actuating unattended. Only the SWEEP is opt-out.
      expect(Ai::Mission.find(result.mission_id).status).to eq("cancelled")
      expect(System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%").pluck(:status).uniq)
        .to eq([ "running" ])
    end

    it "cancels BEFORE it sweeps when the explicit teardown command finishes an abandoned run" do
      soak_harness(cleanup: false).run
      # What a killed soak process leaves behind: a live mission whose fleet is
      # still up (the instances above are real; only the status is restored to
      # the pre-finalize! value the crash would have left).
      mission = Ai::Mission.find_by(name: "dryrun-#{run_id}")
      mission.update!(status: "active")

      order = []
      allow_any_instance_of(Ai::Missions::OrchestratorService).to receive(:cancel!) do |svc, **kwargs|
        order << :cancel
        svc.mission.update!(status: "cancelled")
      end
      allow_any_instance_of(System::ProvisioningService).to receive(:terminate_instance) do |_svc, kwargs|
        order << :terminate
        (kwargs.is_a?(Hash) ? kwargs[:instance] : kwargs).update!(status: "terminated")
        System::Runtime::Result.ok
      end

      result = described_class.new(account: account, user: user, objective: objective,
                                   run_id: run_id).teardown_only!

      expect(order.first).to eq(:cancel)
      expect(order.count(:terminate)).to eq(3)
      expect(mission.reload.status).to eq("cancelled")
      expect(System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%").pluck(:status).uniq)
        .to eq([ "terminated" ])
      expect(result.passed?).to be(true), "unexpected findings: #{result.findings.map(&:to_h)}"
    end

    it "reads the actuator's orphans on teardown even though the mission is terminal" do
      # The retained-soak path leaves a CANCELLED mission, and that mission is
      # the only handle on the plan the orphan is recorded against. Looking it
      # up as "live" would find nothing and sweep straight over the leak.
      soak_harness(cleanup: false).run
      mission = Ai::Mission.find_by(name: "dryrun-#{run_id}")
      expect(mission.status).to eq("cancelled")
      plan = Ai::GoalPlan.find(mission.configuration.dig("plan", "plan_id"))
      step = plan.steps.order(:step_number).last
      step.update!(metadata: (step.metadata || {}).merge(
        "last_outputs" => { "outputs" => { "orphans" => [ { "resource" => "sdwan_peer", "ids" => %w[peer-9] } ] } }
      ))

      result = described_class.new(account: account, user: user, objective: objective,
                                   run_id: run_id).teardown_only!

      expect(result.findings.map(&:dimension)).to include("orphan")
      expect(System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%").pluck(:status).uniq)
        .to eq([ "running" ])

      # ...and the operator can finish the job once the leak has been read.
      forced = described_class.new(account: account, user: user, objective: objective,
                                   run_id: run_id, force_teardown: true).teardown_only!

      expect(forced.findings.map(&:detail)).to include(/forced past the orphan halt/)
      expect(System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%").pluck(:status).uniq)
        .to eq([ "terminated" ])
    end

    it "refuses a teardown whose sweep would cross into a live neighbour's blast radius" do
      soak_harness(cleanup: false).run
      # A live neighbour whose prefix this run's sweep ('dryrun-<runId>%') would
      # subsume. The start-time guard never saw it: it started later.
      Ai::Mission.create!(account: account, created_by: user, mission_type: "infrastructure",
                          name: "dryrun-#{run_id}extra", objective: "neighbour", status: "active")

      expect {
        described_class.new(account: account, user: user, objective: objective,
                            run_id: run_id).teardown_only!
      }.to raise_error(/overlaps the blast radius/)

      expect(System::NodeInstance.where("name LIKE ?", "dryrun-#{run_id}%").pluck(:status).uniq)
        .to eq([ "running" ])
    end

    it "can still tear itself down when a SHORTER-prefixed neighbour owns nothing" do
      # The neighbour's fleet query is `dryrun-<runId>%`, which also matches THIS
      # run's `dryrun-<runId>extra-…` instances. Read naively, a retained run
      # refuses its own teardown while naming a neighbour that owns nothing —
      # reachable from a legal sequence (clean run, then a longer-prefixed one).
      Ai::Mission.create!(account: account, created_by: user, mission_type: "infrastructure",
                          name: "dryrun-#{run_id}", objective: "swept clean", status: "completed")

      longer_id = "#{run_id}extra"
      described_class.new(account: account, user: user, objective: objective, run_id: longer_id,
                          cleanup: false, phase_pump: worker_pump,
                          compose_timeout: 30, execute_timeout: 60).run
      expect(System::NodeInstance.where("name LIKE ?", "dryrun-#{longer_id}%").count).to eq(3)

      result = described_class.new(account: account, user: user, objective: objective,
                                   run_id: longer_id).teardown_only!

      expect(System::NodeInstance.where("name LIKE ?", "dryrun-#{longer_id}%").pluck(:status).uniq)
        .to eq([ "terminated" ])
      expect(result.findings.map(&:dimension)).not_to include("teardown")
    end

    it "does not report a clean PASS for a teardown that found nothing to tear down" do
      # A mistyped run_id must not exit 0 with a green report: "swept nothing"
      # and "there was nothing to sweep" are the same output otherwise.
      result = described_class.new(account: account, user: user, objective: objective,
                                   run_id: "nosuchrun").teardown_only!

      expect(result.passed?).to be(false)
      expect(result.findings.map(&:dimension)).to include("teardown")
      expect(result.findings.first.detail).to match(/no mission and no instance/)
    end

    it "stays quiet when an already-swept run is torn down again (idempotent)" do
      soak_harness(cleanup: true).run

      result = described_class.new(account: account, user: user, objective: objective,
                                   run_id: run_id).teardown_only!

      expect(result.findings.map(&:dimension)).not_to include("teardown")
      expect(result.oracles["instances"]).to eq(3)
    end
  end
end
