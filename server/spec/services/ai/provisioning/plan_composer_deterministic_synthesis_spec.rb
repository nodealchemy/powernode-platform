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

  # ---- IMP-cdc1d0703e5a: fabric + storage footprint ----------------------
  #
  # Every composed provision/scale-out arrived as BARE COMPUTE.
  # #merge_resolved_inputs! stamped count/dry_run/region/instance-type/
  # template/mission/name_prefix and nothing else, so the two OPTIONAL legs of
  # ProvisionFullStackExecutor — per-instance Sdwan::PeerEnroller behind
  # `network_id`, and the per-instance volume behind `with_storage_gb` — were
  # unreachable from any composed plan. The actuator side is fully built
  # (ScaleProjectExecutor#run_provision threads both onward and reports
  # sdwan_peer_ids + storage_volume_ids); only the populating end was missing.
  #
  # AdaptationProposerService::FOOTPRINT_KEYS already lists both and carries
  # them from the original plan onto a composed scale-out; it was inert only
  # because the source plan never held the keys. Stamping here makes that lane
  # live with zero change there.
  describe "fabric + storage footprint (IMP-cdc1d0703e5a)" do
    it "stamps network_id from the chosen template's own sdwan_network_id" do
      plan = compose!(runtime_brief)
      pf = provision_steps(plan)

      expect(pf).not_to be_empty
      pf.each do |s|
        expect(s.execution_config["inputs"]["network_id"]).to eq(sdwan_network.id)
      end
    end

    it "reads the SAME template key the compose-time prerequisite checker reads" do
      # ProvisionPrerequisites#check gates on template.config["sdwan_network_id"].
      # Composer and checker must agree BY CONSTRUCTION — this campaign has
      # already been burned once by two components computing the same thing
      # two different ways.
      plan = compose!(runtime_brief)
      expect(template.reload.config["sdwan_network_id"]).to eq(sdwan_network.id)
      expect(provision_steps(plan).first.execution_config["inputs"]["network_id"])
        .to eq(template.config["sdwan_network_id"])
    end

    it "stamps with_storage_gb from the brief's storage_gb" do
      plan = compose!(runtime_brief.merge("storage_gb" => 50))
      pf = provision_steps(plan)

      expect(pf).not_to be_empty
      pf.each do |s|
        expect(s.execution_config["inputs"]["with_storage_gb"]).to eq(50)
      end
    end

    it "coerces a stringified storage_gb to the Integer the executor sizes a volume with" do
      plan = compose!(runtime_brief.merge("storage_gb" => "50"))
      expect(provision_steps(plan).first.execution_config["inputs"]["with_storage_gb"]).to eq(50)
    end

    it "omits with_storage_gb entirely when the brief names no volume" do
      plan = compose!(runtime_brief)
      provision_steps(plan).each do |s|
        expect(s.execution_config["inputs"]).not_to have_key("with_storage_gb")
      end
    end

    # ---- the decided design fork ---------------------------------------
    #
    # Networkless missions stay legal and SILENT; a DECLARED-but-unusable
    # network fails LOUD at compose time. Silently degrading a declared
    # fabric request to bare compute is the exact defect class this task
    # exists to remove, so the composer must not reproduce it one layer up.
    context "when the template declares NO network (a genuinely networkless mission)" do
      let!(:bare) do
        create(:system_node_template, account: account, name: "bare-compute-cell",
                                      config: { "boot_mode" => "uefi_disk" })
      end

      def bare_brief
        runtime_brief.merge("preferred_template" => "bare-compute-cell",
                            "use_case" => "a plain postgres database",
                            "intent" => "provision a db")
      end

      it "composes bare compute, omitting network_id, without noise" do
        plan = compose!(bare_brief)

        expect(plan).to be_a(Ai::GoalPlan)
        pf = provision_steps(plan)
        expect(pf).not_to be_empty
        pf.each do |s|
          expect(s.execution_config["inputs"]["template_id"]).to eq(bare.id)
          expect(s.execution_config["inputs"]).not_to have_key("network_id")
        end
      end
    end

    it "omits network_id when the template's config is not a Hash at all" do
      # `config` is a NOT NULL jsonb, so the reachable non-Hash shape is a JSON
      # array/scalar, not nil. Nothing was DECLARED, so this is the silent
      # bare-compute arm rather than the loud one.
      odd = create(:system_node_template, account: account, name: "odd-config-cell", config: {})
      odd.update_column(:config, [])
      expect(odd.reload.config).not_to be_a(Hash)

      plan = compose!(runtime_brief.merge("preferred_template" => "odd-config-cell",
                                          "use_case" => "a plain postgres database",
                                          "intent" => "provision a db"))

      expect(plan).to be_a(Ai::GoalPlan)
      provision_steps(plan).each do |s|
        expect(s.execution_config["inputs"]).not_to have_key("network_id")
      end
    end

    describe "storage_gb coercion (the reader must not parse stricter than its writer)" do
      let(:service) { described_class.new(account: account, mission: mission_for(runtime_brief)) }

      def stamped(storage_gb)
        inputs = {}
        service.send(:merge_resolved_inputs!, inputs, runtime_brief.merge("storage_gb" => storage_gb),
                     "provision_full_stack")
        inputs["with_storage_gb"]
      end

      # IntentCaptureService normalises storage_gb with to_i. A reader using
      # Integer() would reject "50.7" and silently compose NO volume — the
      # exact silent degradation this task removes, one field over.
      it "accepts a fractional string the way the brief writer's to_i does" do
        expect(stamped("50.7")).to eq(50)
      end

      it "treats a non-positive size as no volume rather than a real 0GB request" do
        expect(stamped(0)).to be_nil
        expect(stamped(-5)).to be_nil
      end

      it "treats unparseable and non-numeric shapes as no volume" do
        expect(stamped("plenty")).to be_nil
        expect(stamped({ "gb" => 50 })).to be_nil
        expect(stamped([])).to be_nil
      end
    end

    # A key present with a NULL or BLANK value must stay in the SILENT arm.
    # Builders and forms that emit every key regardless produce these routinely
    # and they read as "no network set" — routing them to the loud arm would
    # stop templates that compose perfectly well today from composing at all.
    describe "a declared-but-blank value is 'no network', not a failed declaration" do
      let(:service) { described_class.new(account: account, mission: mission_for(runtime_brief)) }

      def declaration_for(value)
        odd = create(:system_node_template, account: account, name: "blankish-#{SecureRandom.hex(3)}",
                                            config: { "boot_mode" => "uefi_disk",
                                                      "sdwan_network_id" => value })
        service.send(:template_network_declaration, odd)
      end

      it "treats an explicit JSON null as absent" do
        expect(declaration_for(nil).first).to eq(:absent)
      end

      it "treats an empty or whitespace-only string as absent" do
        expect(declaration_for("").first).to eq(:absent)
        expect(declaration_for("   ").first).to eq(:absent)
      end

      it "still composes bare compute — silently — for an explicit null" do
        create(:system_node_template, account: account, name: "null-fabric-cell",
                                      config: { "boot_mode" => "uefi_disk",
                                                "sdwan_network_id" => nil })

        plan = compose!(runtime_brief.merge("preferred_template" => "null-fabric-cell",
                                            "use_case" => "a plain postgres database",
                                            "intent" => "provision a db"))

        expect(plan).to be_a(Ai::GoalPlan)
        provision_steps(plan).each do |s|
          expect(s.execution_config["inputs"]).not_to have_key("network_id")
        end
      end

      # Core cannot check that a network EXISTS without naming the extension,
      # and does not need to: the executor fails the whole step with "sdwan
      # network not found" before provisioning anything.
      it "stamps a non-blank string even when no such network exists — the executor is the check" do
        dangling = create(:system_node_template, account: account, name: "dangling-fabric-cell",
                                                 config: { "boot_mode" => "uefi_disk",
                                                           "sdwan_network_id" => "no-such-network" })
        state, value = service.send(:template_network_declaration, dangling)
        expect([ state, value ]).to eq([ :usable, "no-such-network" ])
      end
    end

    context "when the template DECLARES sdwan_network_id but the value is unusable" do
      # Non-blank and structurally incapable of being an id. A list of network
      # ids where one is expected is the plausible operator error.
      let!(:broken) do
        create(:system_node_template, account: account, name: "broken-fabric-cell",
                                      config: { "boot_mode" => "uefi_disk",
                                                "sdwan_network_id" => %w[net-a net-b] })
      end

      def broken_brief
        runtime_brief.merge("preferred_template" => "broken-fabric-cell",
                            "use_case" => "a plain postgres database",
                            "intent" => "provision a db")
      end

      it "fails LOUD at compose time instead of silently composing bare compute" do
        result = compose!(broken_brief)

        expect(result).to be_a(Hash)
        expect(result[:clarification_needed]).to be true
        expect(result[:message]).to match(/sdwan_network_id/)
        expect(result[:message]).to include("broken-fabric-cell")
      end

      it "writes no plan pointer — a corrected retry recomposes fresh" do
        mission = mission_for(broken_brief)
        described_class.new(account: account, mission: mission).compose!

        expect(mission.reload.configuration.dig("plan", "plan_id")).to be_nil
      end
    end

    describe "||= semantics and skill scoping (direct send)" do
      let(:service) { described_class.new(account: account, mission: mission_for(runtime_brief)) }

      it "never overwrites an authored network_id or with_storage_gb" do
        inputs = { "network_id" => "author-supplied-network", "with_storage_gb" => 7 }
        service.send(:merge_resolved_inputs!, inputs, runtime_brief.merge("storage_gb" => 50),
                     "provision_full_stack")

        expect(inputs["network_id"]).to eq("author-supplied-network")
        expect(inputs["with_storage_gb"]).to eq(7)
      end

      it "stamps the same footprint onto a scale_project step" do
        inputs = {}
        service.send(:merge_resolved_inputs!, inputs, runtime_brief.merge("storage_gb" => 50),
                     "scale_project")

        expect(inputs["network_id"]).to eq(sdwan_network.id)
        expect(inputs["with_storage_gb"]).to eq(50)
      end

      it "touches neither key for a skill that is not a provisioning primitive" do
        inputs = {}
        service.send(:merge_resolved_inputs!, inputs, runtime_brief.merge("storage_gb" => 50),
                     "docker_provision")

        expect(inputs).not_to have_key("network_id")
        expect(inputs).not_to have_key("with_storage_gb")
      end
    end

    # ---- the cross-seam oracle -----------------------------------------
    #
    # The writer (this composer) and the reader (ProvisionFullStackExecutor)
    # are each already covered against a STUB of the other, and both suites
    # stayed green across the whole life of this defect. The only oracle that
    # can see the seam is one with NOTHING stubbed between them: compose a
    # plan, take the step's inputs VERBATIM, and hand them to the real
    # executor with only the provider adapter boundary stubbed.
    #
    # The assertion is deliberately sharper than "non-zero peers": peers are
    # matched to the NEWLY created node_instance_ids. An earlier
    # implementation compiled the network's already-existing peers and
    # reported them as its own output, which made a non-zero count pass
    # vacuously off the incumbent fleet.
    describe "composed inputs drive the real executor (no stub between writer and reader)" do
      let(:provisioned_node) { sdwan_test_node(account: account) }
      let(:provisioned_instances) do
        Array.new(3) { sdwan_test_node_instance(node: provisioned_node) }
      end

      # The fleet that was already on the fabric. Its peer must never be
      # reported as something this provision created.
      let!(:incumbent_peer) do
        ::Sdwan::PeerEnroller.call(
          network: sdwan_network,
          node_instance: sdwan_test_node_instance(node: sdwan_test_node(account: account))
        )
      end

      before do
        queue = provisioned_instances.dup
        allow(::System::ProvisioningService).to receive(:provision_instance) do
          ::System::Runtime::Result.ok(data: { instance: queue.shift,
                                               cloud_instance_id: "ci-#{SecureRandom.hex(2)}" })
        end
        allow(::System::VolumeManagementService).to receive(:provision) do
          ::System::Runtime::Result.ok(
            data: { volume: instance_double("System::ProviderVolume", id: SecureRandom.uuid) }
          )
        end
        allow(::System::VolumeManagementService).to receive(:attach)
          .and_return(::System::Runtime::Result.ok(data: { device: "/dev/sdb" }))
      end

      it "enrolls the instances it just created as peers, and provisions their volumes" do
        plan = compose!(runtime_brief.merge("storage_gb" => 25))
        step = provision_steps(plan).first
        inputs = step.execution_config["inputs"].symbolize_keys

        result = ::System::Ai::Skills::ProvisionFullStackExecutor
                 .new(account: account).execute(**inputs)

        expect(result[:success]).to be true
        outputs = result[:data][:outputs]
        created = outputs[:node_instance_ids]
        expect(created).not_to be_empty

        # Every reported peer belongs to an instance THIS step created...
        peers = ::Sdwan::Peer.where(id: outputs[:sdwan_peer_ids])
        expect(peers.count).to eq(created.size)
        expect(peers.pluck(:node_instance_id)).to match_array(created)
        # ...and the incumbent is not among them.
        expect(outputs[:sdwan_peer_ids]).not_to include(incumbent_peer.id)

        expect(outputs[:storage_volume_ids].size).to eq(created.size)
        expect(::System::VolumeManagementService)
          .to have_received(:provision).with(hash_including(size_gb: 25)).exactly(created.size).times
      end
    end
  end

  # ---- IMP-94728a788498: three-arm network resolution --------------------
  #
  # After IMP-cdc1d0703e5a the composer stamped network_id only from the
  # chosen template's own config — and no seed or service writes that key, so
  # fabric membership was a per-template OPT-IN an operator had to hand-
  # configure. The north star wants fabric membership as the default posture.
  #
  # Resolution order: template explicit → account default → networkless.
  # An explicit template opt-out ("none") beats the account default; a
  # configured default that could never resolve fails LOUD at compose time;
  # null/blank stays "no opinion" on BOTH arms — the swallowed-null class
  # (4db30efae's carefully-chosen bucketing) must not come back one key over.
  describe "three-arm network resolution (IMP-94728a788498)" do
    let!(:bare_template) do
      create(:system_node_template, account: account, name: "default-fabric-cell",
                                    config: { "boot_mode" => "uefi_disk" })
    end

    def bare_db_brief(extra = {})
      runtime_brief.merge("preferred_template" => "default-fabric-cell",
                          "use_case" => "a plain postgres database",
                          "intent" => "provision a db").merge(extra)
    end

    def set_account_default(value)
      account.update!(settings: (account.settings || {}).merge("default_sdwan_network_id" => value))
    end

    context "the account-default arm" do
      before { set_account_default(sdwan_network.id) }

      it "stamps network_id from the account default when the template declares none" do
        plan = compose!(bare_db_brief)
        pf = provision_steps(plan)

        expect(pf).not_to be_empty
        pf.each do |s|
          expect(s.execution_config["inputs"]["network_id"]).to eq(sdwan_network.id)
        end
      end

      it "composes a runtime (docker) plan on an unconfigured template — the prerequisite checker honors the resolved default" do
        plan = compose!(runtime_brief.merge("preferred_template" => "default-fabric-cell"))

        expect(plan).to be_a(Ai::GoalPlan)
        expect(docker_steps(plan).size).to eq(3)
        provision_steps(plan).each do |s|
          expect(s.execution_config["inputs"]["network_id"]).to eq(sdwan_network.id)
        end
      end

      it "the template's own declaration beats the account default" do
        other = ::Sdwan::Network.create!(account_id: account.id, name: "team-#{SecureRandom.hex(3)}")
        set_account_default(other.id)

        plan = compose!(runtime_brief) # powernode-ops-cell declares sdwan_network.id
        provision_steps(plan).each do |s|
          expect(s.execution_config["inputs"]["network_id"]).to eq(sdwan_network.id)
        end
      end

      it "an explicit template opt-out ('none') composes networkless even with the default set" do
        create(:system_node_template, account: account, name: "opted-out-cell",
                                      config: { "boot_mode" => "uefi_disk",
                                                "sdwan_network_id" => "none" })

        plan = compose!(bare_db_brief("preferred_template" => "opted-out-cell"))

        expect(plan).to be_a(Ai::GoalPlan)
        provision_steps(plan).each do |s|
          expect(s.execution_config["inputs"]).not_to have_key("network_id")
        end
      end
    end

    describe "opt-out bucketing (the sentinel is case-insensitive and stripped)" do
      let(:service) { described_class.new(account: account, mission: mission_for(runtime_brief)) }

      it "classifies 'none' in any case, padded or not, as :opt_out" do
        [ "none", "NONE", " None " ].each do |value|
          t = create(:system_node_template, account: account, name: "optout-#{SecureRandom.hex(3)}",
                                            config: { "sdwan_network_id" => value })
          expect(service.send(:template_network_declaration, t).first).to eq(:opt_out)
        end
      end
    end

    # The swallowed-null guard on the NEW arm: builders and forms that emit
    # every key produce null and "" routinely. On the account key those read
    # as NO DEFAULT — silent networkless — never as an opt-out and never as
    # a loud failure.
    describe "null/blank on the account key is NO DEFAULT, not an opt-out and not a failure" do
      [ nil, "", "   " ].each do |blankish|
        it "composes networkless silently for #{blankish.inspect}" do
          set_account_default(blankish)
          plan = compose!(bare_db_brief)

          expect(plan).to be_a(Ai::GoalPlan)
          provision_steps(plan).each do |s|
            expect(s.execution_config["inputs"]).not_to have_key("network_id")
          end
        end
      end

      it "treats the 'none' sentinel on the account key as no-default too" do
        set_account_default("none")
        plan = compose!(bare_db_brief)

        expect(plan).to be_a(Ai::GoalPlan)
        provision_steps(plan).each do |s|
          expect(s.execution_config["inputs"]).not_to have_key("network_id")
        end
      end
    end

    context "a configured account default that could never be an id" do
      before { set_account_default(%w[net-a net-b]) }

      it "fails LOUD at compose time instead of silently composing bare compute" do
        result = compose!(bare_db_brief)

        expect(result).to be_a(Hash)
        expect(result[:clarification_needed]).to be true
        expect(result[:message]).to match(/default_sdwan_network_id/)
      end

      it "writes no plan pointer — a corrected retry recomposes fresh" do
        mission = mission_for(bare_db_brief)
        described_class.new(account: account, mission: mission).compose!

        expect(mission.reload.configuration.dig("plan", "plan_id")).to be_nil
      end

      it "does not block a plan whose template decided for itself" do
        plan = compose!(runtime_brief) # template-declared network; default never consulted
        expect(plan).to be_a(Ai::GoalPlan)
      end

      it "does not block an explicitly opted-out template either" do
        create(:system_node_template, account: account, name: "opted-out-cell-2",
                                      config: { "boot_mode" => "uefi_disk",
                                                "sdwan_network_id" => "none" })

        plan = compose!(bare_db_brief("preferred_template" => "opted-out-cell-2"))
        expect(plan).to be_a(Ai::GoalPlan)
      end
    end

    # ---- the cross-seam oracle, account-default arm ----------------------
    #
    # Same shape as the template-arm oracle above: NOTHING stubbed between
    # the composer and ProvisionFullStackExecutor, and the assertion is
    # sharper than "non-zero peers" — every reported peer must belong to an
    # instance THIS step created, and the incumbent fleet's peer must not
    # be among them.
    describe "an account-default plan produces peers on the NEWLY created instances" do
      let(:provisioned_node) { sdwan_test_node(account: account) }
      let(:provisioned_instances) do
        Array.new(3) { sdwan_test_node_instance(node: provisioned_node) }
      end

      let!(:incumbent_peer) do
        ::Sdwan::PeerEnroller.call(
          network: sdwan_network,
          node_instance: sdwan_test_node_instance(node: sdwan_test_node(account: account))
        )
      end

      before do
        set_account_default(sdwan_network.id)
        queue = provisioned_instances.dup
        allow(::System::ProvisioningService).to receive(:provision_instance) do
          ::System::Runtime::Result.ok(data: { instance: queue.shift,
                                               cloud_instance_id: "ci-#{SecureRandom.hex(2)}" })
        end
      end

      it "enrolls the instances it just created as peers on the account's default network" do
        plan = compose!(bare_db_brief)
        step = provision_steps(plan).first
        inputs = step.execution_config["inputs"].symbolize_keys

        result = ::System::Ai::Skills::ProvisionFullStackExecutor
                 .new(account: account).execute(**inputs)

        expect(result[:success]).to be true
        outputs = result[:data][:outputs]
        created = outputs[:node_instance_ids]
        expect(created).not_to be_empty

        peers = ::Sdwan::Peer.where(id: outputs[:sdwan_peer_ids])
        expect(peers.count).to eq(created.size)
        expect(peers.pluck(:node_instance_id)).to match_array(created)
        expect(outputs[:sdwan_peer_ids]).not_to include(incumbent_peer.id)
      end
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
