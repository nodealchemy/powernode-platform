# frozen_string_literal: true

require "rails_helper"

# Deterministic plan synthesis for recognized provisioning briefs
# (IMP 019fe7f0; subsumes the F-1 runtime-leg guard IMP 019fe76e and the
# docker dedup IMP 019fe7e0).
#
# The platform-autonomy-dryrun campaign ran the SAME brief (scale.initial=3,
# regions dna+rna, container-runtime use case) four times through the LLM
# decomposer and got a differently broken plan each run: run c 3 docker steps
# (ok by luck), run d 0 docker steps, run e 2→6 docker steps after fan-out,
# run f count 9+9 = 18 instances for a 3-instance brief (est. $1008/mo). The
# brief was extracted correctly every time — the variance was entirely the
# LLM's, and each guard pass fixed one dimension while the next run revealed
# another.
#
# For a brief the ComposerRouter recognizes as a provisioning scenario
# (deterministic_provisioning? — the exact predicate that routes briefs to
# this composer), the plan is now SYNTHESIZED from the brief: provision steps
# summing to scale.initial split across the named regions, plus one wired
# docker_provision step per instance when the brief demands runtime work.
# No LLM call, zero variance; the run-d/e/f defects are structurally
# impossible rather than patched.
RSpec.describe Ai::Provisioning::PlanComposerService, "deterministic synthesis", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  before do
    skip "system extension not loaded" unless defined?(::System::ProviderRegion)
    ::System::Provider.where(account_id: account.id).destroy_all
  end

  let(:sys_provider) do
    ::System::Provider.create!(account: account, name: "IPNode PVE", provider_type: "proxmox", enabled: true)
  end
  let!(:dna) do
    ::System::ProviderRegion.create!(account: account, provider: sys_provider,
                                     region_code: "dna", name: "dna", enabled: true)
  end
  let!(:rna) do
    ::System::ProviderRegion.create!(account: account, provider: sys_provider,
                                     region_code: "rna", name: "rna", enabled: true)
  end
  let!(:instance_type) do
    ::System::ProviderInstanceType.create!(account: account, provider: sys_provider,
                                           name: "small", instance_type_code: "small-1", enabled: true)
  end
  # The template must satisfy the compose-time prerequisite seam
  # (IMP 019fe647): docker_provision demands a declared, existing SDWAN
  # overlay network, or compose! returns a clarification instead of a plan.
  let!(:sdwan_network) do
    ::Sdwan::Network.create!(account_id: account.id, name: "overlay-#{SecureRandom.hex(3)}")
  end
  let!(:template) do
    create(:system_node_template, account: account, name: "powernode-ops-cell",
                                  config: { "boot_mode" => "uefi_disk",
                                            "sdwan_network_id" => sdwan_network.id })
  end

  # The exact dryrun brief shape that produced runs c–f.
  let(:runtime_brief) do
    {
      "intent" => "provision the platform-validation workload",
      "use_case" => "an end-to-end platform-validation test workload exercising " \
                    "provisioning, module assignment, and the container-runtime handshake",
      "scale" => { "initial" => 3, "target" => 3 },
      "regions" => %w[dna rna],
      "preferred_template" => "powernode-ops-cell",
      "budget_cap_usd_monthly" => 5.0
    }
  end

  def mission_for(brief, extra_config = {})
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        configuration: { "brief" => brief }.merge(extra_config))
  end

  def compose!(brief, extra_config = {})
    described_class.new(account: account, mission: mission_for(brief, extra_config)).compose!
  end

  def provision_steps(plan)
    plan.steps.reload.order(:step_number).select { |s| s.execution_config["skill"] == "provision_full_stack" }
  end

  def docker_steps(plan)
    plan.steps.reload.order(:step_number).select { |s| s.execution_config["skill"] == "docker_provision" }
  end

  it "never calls the LLM decomposer for a recognized provisioning brief" do
    expect_any_instance_of(Ai::Autonomy::GoalDecompositionService).not_to receive(:decompose)
    plan = compose!(runtime_brief)
    expect(plan).to be_a(Ai::GoalPlan)
  end

  it "stamps synthesis provenance on the plan" do
    plan = compose!(runtime_brief)
    expect(plan.plan_data["composer"]).to eq("deterministic_synthesis")
  end

  describe "the run-f defect (scale explosion) is impossible" do
    it "provision counts sum to exactly scale.initial, split 2+1 across dna/rna" do
      plan = compose!(runtime_brief)
      pf = provision_steps(plan)

      expect(pf.size).to eq(2)
      expect(pf.sum { |s| s.execution_config["inputs"]["count"].to_i }).to eq(3)
      by_region = pf.to_h do |s|
        [s.execution_config["inputs"]["provider_region_id"], s.execution_config["inputs"]["count"].to_i]
      end
      expect(by_region).to eq(dna.id => 2, rna.id => 1)
    end

    it "produces the identical shape on every composition — no run-to-run variance" do
      shapes = Array.new(3) do
        plan = compose!(runtime_brief)
        provision_steps(plan).map { |s| [s.execution_config["inputs"]["provider_region_id"], s.execution_config["inputs"]["count"].to_i] }
      end
      expect(shapes.uniq.size).to eq(1)
      expect(shapes.first.sum(&:last)).to eq(3)
    end
  end

  describe "the run-d/run-e defects (missing / duplicated docker leg) are impossible" do
    it "emits exactly one wired docker_provision step per instance" do
      plan = compose!(runtime_brief)
      dockers = docker_steps(plan)
      pf = provision_steps(plan)
      dna_step = pf.find { |s| s.execution_config["inputs"]["provider_region_id"] == dna.id }
      rna_step = pf.find { |s| s.execution_config["inputs"]["provider_region_id"] == rna.id }

      expect(dockers.size).to eq(3)
      mappings = dockers.map { |s| s.execution_config.dig("depends_on_outputs", "node_instance_id") }
      expect(mappings).to all(include("path" => "outputs.node_instance_ids"))
      expect(mappings.map { |m| [m["from_step"], m["select"]] })
        .to match_array([[dna_step.step_number, 0], [dna_step.step_number, 1], [rna_step.step_number, 0]])
    end

    it "each docker step depends only on its own provision step" do
      plan = compose!(runtime_brief)
      docker_steps(plan).each do |s|
        from = s.execution_config.dig("depends_on_outputs", "node_instance_id", "from_step")
        expect(Array(s.dependencies).map(&:to_i)).to eq([from])
      end
    end

    it "emits no docker steps when the brief does not demand runtime work" do
      plan = compose!(runtime_brief.merge("use_case" => "a plain postgres database",
                                          "intent" => "provision a db"))
      expect(docker_steps(plan)).to be_empty
      expect(provision_steps(plan).sum { |s| s.execution_config["inputs"]["count"].to_i }).to eq(3)
    end

    it "honors runtime_hint: docker as the demand signal" do
      plan = compose!(runtime_brief.merge("use_case" => "run my app", "intent" => "run it",
                                          "runtime_hint" => "docker"))
      expect(docker_steps(plan).size).to eq(3)
    end
  end

  describe "step shape" do
    it "every step is a provisioning_skill with skill/inputs/on_failure and the brief" do
      plan = compose!(runtime_brief)
      expect(plan.steps.count).to eq(5) # 2 provision + 3 docker
      plan.steps.each do |step|
        expect(step.step_type).to eq("provisioning_skill")
        cfg = step.execution_config
        expect(described_class::ALLOWED_EXECUTORS).to include(cfg["skill"])
        expect(cfg["on_failure"]).to eq("rollback")
        expect(cfg["inputs"]["brief"]).to eq(runtime_brief)
      end
    end

    it "resolves preferred_template and instance type onto provision inputs" do
      plan = compose!(runtime_brief)
      provision_steps(plan).each do |s|
        expect(s.execution_config["inputs"]["template_id"]).to eq(template.id)
        expect(s.execution_config["inputs"]["provider_instance_type_id"]).to eq(instance_type.id)
        expect(s.execution_config["inputs"]["dry_run"]).to be false
      end
    end

    it "passes validate_plan" do
      service = described_class.new(account: account, mission: mission_for(runtime_brief))
      plan = service.compose!
      expect(service.validate_plan(plan)).to eq(valid: true, errors: [])
    end
  end

  describe "F3 naming provenance" do
    it "stamps mission_id and the dryrun-derived name_prefix on provision inputs" do
      mission = mission_for(runtime_brief, "dryrun_run_id" => "20260809g")
      plan = described_class.new(account: account, mission: mission).compose!

      provision_steps(plan).each do |s|
        expect(s.execution_config["inputs"]["mission_id"]).to eq(mission.id)
        expect(s.execution_config["inputs"]["name_prefix"]).to eq("dryrun-20260809g")
      end
    end
  end

  describe "F7 budget surfacing" do
    it "the synthesized plan's snapshot carries the cap-vs-estimate block" do
      plan = compose!(runtime_brief)
      snapshot_service = Ai::Provisioning::PlanSnapshotService.new(account: account)
      allow(snapshot_service).to receive(:build_cost_estimate).and_return(
        { monthly_usd: 42.0, one_time_usd: 0.0, by_resource: [], confidence: "med" }
      )

      budget = snapshot_service.snapshot(plan: plan)[:budget]
      expect(budget[:cap_usd_monthly]).to eq(5.0)
      expect(budget[:within_budget]).to be false
    end
  end

  describe "degenerate briefs" do
    it "a single-instance single-region brief yields exactly one provision step" do
      plan = compose!(runtime_brief.merge("scale" => { "initial" => 1, "target" => 1 },
                                          "regions" => %w[dna],
                                          "use_case" => "a plain database", "intent" => "one node"))
      expect(plan.steps.count).to eq(1)
      step = plan.steps.first
      expect(step.execution_config["inputs"]["count"]).to eq(1)
      expect(step.execution_config["inputs"]["provider_region_id"]).to eq(dna.id)
    end

    it "a region-less brief yields one full-count step on the fallback region" do
      plan = compose!(runtime_brief.merge("regions" => [],
                                          "use_case" => "a plain database", "intent" => "three nodes"))
      pf = provision_steps(plan)
      expect(pf.size).to eq(1)
      expect(pf.first.execution_config["inputs"]["count"]).to eq(3)
    end

    it "fewer instances than regions means fewer steps, never a zero share" do
      plan = compose!(runtime_brief.merge("scale" => { "initial" => 1, "target" => 1 },
                                          "use_case" => "a plain database", "intent" => "one node"))
      pf = provision_steps(plan)
      expect(pf.size).to eq(1)
      expect(pf.first.execution_config["inputs"]["count"]).to eq(1)
      expect(pf.first.execution_config["inputs"]["provider_region_id"]).to eq(dna.id)
    end
  end

  describe "the unrecognized-brief fallback (direct instantiation only)" do
    it "still routes through the LLM decomposer + rewrite pipeline" do
      unrecognized = { "intent" => "Spin up something", "use_case" => "Primary OLTP" }
      expect(::Ai::Missions::ComposerRouter.deterministic_provisioning?(unrecognized)).to be(false)

      called = false
      allow_any_instance_of(Ai::Autonomy::GoalDecompositionService)
        .to receive(:decompose) { |_inst, _goal| called = true; nil }

      compose!(unrecognized)
      expect(called).to be(true)
    end
  end
end
