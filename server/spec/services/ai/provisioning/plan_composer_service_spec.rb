# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Provisioning::PlanComposerService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  let(:brief) do
    {
      "intent" => "Spin up a 3-node Postgres cluster",
      "use_case" => "Primary OLTP",
      "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
      "regions" => ["us-east-1"],
      "compliance" => [],
      "budget_cap_usd_monthly" => 200.0,
      "latency_targets_ms" => { "p99" => 100 },
      "data_residency" => [],
      "preferred_provider" => nil
    }
  end

  let(:mission) do
    create(
      :ai_mission,
      account: account,
      created_by: user,
      mission_type: "infrastructure",
      custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
      configuration: { "brief" => brief }
    )
  end

  subject(:service) { described_class.new(account: account, mission: mission) }

  describe "#compose!" do
    let(:fake_steps) do
      [
        { description: "Provision the 3-node compute cluster", config: { "action" => "provision new stack" }, dependencies: [] },
        { description: "Configure SDWAN failover for the cluster", config: { "action" => "sdwan failover" }, dependencies: [1] },
        { description: "Apply rolling module upgrade across nodes", config: { "action" => "rolling upgrade" }, dependencies: [1] }
      ]
    end

    before do
      allow_any_instance_of(Ai::Autonomy::GoalDecompositionService)
        .to receive(:decompose) do |_inst, goal|
          next_version = (Ai::GoalPlan.where(goal_id: goal.id).maximum(:version) || 0) + 1
          plan = Ai::GoalPlan.create!(
            account: account, goal: goal, agent: goal.agent,
            status: "draft", version: next_version, plan_data: { "stub" => true }
          )
          fake_steps.each_with_index do |s, i|
            plan.steps.create!(
              step_number: i + 1,
              step_type: "agent_execution",
              description: s[:description],
              execution_config: s[:config],
              dependencies: s[:dependencies]
            )
          end
          plan
        end
    end

    it "creates an AgentGoal linked to the mission" do
      expect { service.compose! }.to change(Ai::AgentGoal, :count).by(1)
      goal = Ai::AgentGoal.last
      expect(goal.metadata["provisioning_mission_id"]).to eq(mission.id)
      expect(goal.success_criteria["brief"]).to eq(brief)
    end

    it "rewrites every step to step_type = provisioning_skill" do
      plan = service.compose!
      expect(plan.steps.pluck(:step_type)).to all(eq("provisioning_skill"))
    end

    it "produces execution_config with skill / inputs / on_failure on every step" do
      plan = service.compose!

      plan.steps.in_order.each do |step|
        cfg = step.execution_config
        expect(cfg).to include("skill", "inputs", "on_failure")
        expect(described_class::ALLOWED_EXECUTORS).to include(cfg["skill"])
        expect(cfg["inputs"]).to include("brief" => brief)
        expect(cfg["on_failure"]).to eq("rollback")
      end
    end

    it "maps suggested actions to the closest allowlisted executor" do
      plan = service.compose!
      skills = plan.steps.in_order.pluck(:execution_config).map { |c| c["skill"] }
      expect(skills[0]).to eq("provision_full_stack")
      expect(skills[1]).to eq("sdwan_failover")
      expect(skills[2]).to eq("rolling_module_upgrade")
    end

    it "preserves dependencies as an Array of step numbers" do
      plan = service.compose!
      step2 = plan.steps.find_by(step_number: 2)
      expect(step2.dependencies).to eq([1])
    end

    it "raises BriefMissingError when the mission has no brief" do
      mission.update!(configuration: {})
      expect { service.compose! }.to raise_error(described_class::BriefMissingError)
    end

    it "reuses an existing provisioning goal on re-run" do
      first_plan = service.compose!
      expect { service.compose! }.not_to change(Ai::AgentGoal, :count)
      expect(Ai::GoalPlan.where(goal_id: first_plan.goal_id).count).to be >= 2
    end
  end

  describe "#validate_plan" do
    let(:goal) do
      Ai::AgentGoal.create!(
        account: account, agent: agent, title: "Goal", goal_type: "creation",
        status: "pending", priority: 3, progress: 0.0,
        success_criteria: {}
      )
    end
    let(:plan) do
      Ai::GoalPlan.create!(
        account: account, goal: goal, agent: agent,
        status: "draft", version: 1, plan_data: {}
      )
    end

    it "flags an empty plan" do
      result = service.validate_plan(plan)
      expect(result[:valid]).to be false
      expect(result[:errors]).to include(/no steps/i)
    end

    it "passes a plan whose steps all use allowed executors" do
      plan.steps.create!(
        step_number: 1, step_type: "provisioning_skill",
        description: "x",
        execution_config: { "skill" => "provision_full_stack", "inputs" => {}, "on_failure" => "rollback" },
        dependencies: []
      )
      result = service.validate_plan(plan)
      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end

    it "flags steps with disallowed skills" do
      plan.steps.create!(
        step_number: 1, step_type: "provisioning_skill",
        description: "x",
        execution_config: { "skill" => "made_up_skill", "inputs" => {}, "on_failure" => "rollback" },
        dependencies: []
      )
      result = service.validate_plan(plan)
      expect(result[:valid]).to be false
      expect(result[:errors].first).to match(/made_up_skill/)
    end

    it "flags circular dependencies" do
      plan.steps.create!(
        step_number: 1, step_type: "provisioning_skill",
        description: "a",
        execution_config: { "skill" => "provision_full_stack" },
        dependencies: [2]
      )
      plan.steps.create!(
        step_number: 2, step_type: "provisioning_skill",
        description: "b",
        execution_config: { "skill" => "provision_full_stack" },
        dependencies: [1]
      )
      result = service.validate_plan(plan)
      expect(result[:valid]).to be false
      expect(result[:errors]).to include(/circular/i)
    end

    it "flags dependencies that reference non-existent step numbers" do
      plan.steps.create!(
        step_number: 1, step_type: "provisioning_skill",
        description: "a",
        execution_config: { "skill" => "provision_full_stack" },
        dependencies: [99]
      )
      result = service.validate_plan(plan)
      expect(result[:valid]).to be false
      expect(result[:errors].any? { |e| e.match?(/unknown step 99/) }).to be true
    end
  end

  describe "step-collapse pass" do
    # The LLM sometimes over-decomposes a simple intent into a chain of
    # identical sequential provisioning steps. After rewrite_steps! we walk
    # the DAG and merge consecutive same-target steps so a 1-instance brief
    # collapses to a single executable step.
    let(:single_instance_brief) do
      brief.merge("scale" => { "initial" => 1, "target" => 1, "growth_profile" => "steady" })
    end

    let(:single_instance_mission) do
      create(
        :ai_mission,
        account: account,
        created_by: user,
        mission_type: "infrastructure",
        custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
        configuration: { "brief" => single_instance_brief }
      )
    end

    def stub_decomposition_with(steps_payload)
      allow_any_instance_of(Ai::Autonomy::GoalDecompositionService)
        .to receive(:decompose) do |_inst, goal|
          next_version = (Ai::GoalPlan.where(goal_id: goal.id).maximum(:version) || 0) + 1
          plan = Ai::GoalPlan.create!(
            account: account, goal: goal, agent: goal.agent,
            status: "draft", version: next_version, plan_data: { "stub" => true }
          )
          steps_payload.each_with_index do |s, i|
            plan.steps.create!(
              step_number: i + 1,
              step_type: "agent_execution",
              description: s[:description],
              execution_config: s[:config],
              dependencies: s[:dependencies]
            )
          end
          plan
        end
    end

    it "collapses three sequential same-target provisioning steps into one with summed count" do
      stub_decomposition_with([
        { description: "Provision the stack",  config: { "action" => "provision new stack" }, dependencies: [] },
        { description: "Provision again",      config: { "action" => "provision new stack" }, dependencies: [1] },
        { description: "Provision once more",  config: { "action" => "provision new stack" }, dependencies: [2] }
      ])

      svc = described_class.new(account: account, mission: single_instance_mission)
      plan = svc.compose!

      expect(plan.steps.count).to eq(1)
      step = plan.steps.first
      expect(step.execution_config["skill"]).to eq("provision_full_stack")
      expect(step.execution_config["inputs"]["count"]).to eq(3)
      expect(step.dependencies).to eq([])
    end

    it "produces exactly one step for a 1-instance brief even when the LLM over-decomposes" do
      stub_decomposition_with([
        { description: "Stand up the workload",   config: { "action" => "provision new stack" }, dependencies: [] },
        { description: "Stand it up again",       config: { "action" => "provision new stack" }, dependencies: [1] },
        { description: "Stand it up yet again",   config: { "action" => "provision new stack" }, dependencies: [2] }
      ])

      svc = described_class.new(account: account, mission: single_instance_mission)
      plan = svc.compose!

      expect(plan.steps.count).to eq(1)
    end

    it "leaves two same-skill steps alone when their target regions differ" do
      stub_decomposition_with([
        { description: "Provision region A", config: { "action" => "provision new stack", "inputs" => { "provider_region_id" => "region-a" } }, dependencies: [] },
        { description: "Provision region B", config: { "action" => "provision new stack", "inputs" => { "provider_region_id" => "region-b" } }, dependencies: [1] }
      ])

      svc = described_class.new(account: account, mission: single_instance_mission)
      plan = svc.compose!

      expect(plan.steps.count).to eq(2)
      regions = plan.steps.in_order.map { |s| s.execution_config["inputs"]["provider_region_id"] }
      expect(regions).to eq(["region-a", "region-b"])
    end

    it "collapses a same-fingerprint parallel-branch fan-out for a 1-instance brief" do
      # step 2 and step 3 both depend on step 1 (a fan-out, not a linear
      # chain). collapse_redundant_provisioning_clusters! groups by fingerprint
      # (template_id + provider_region_id + provider_instance_type_id) and folds
      # any group >1 regardless of DAG shape — here all three share the same
      # nil/nil/nil fingerprint and the brief's scale.initial is 1, so a
      # 1-instance brief must produce a single provision step.
      stub_decomposition_with([
        { description: "Root provision",      config: { "action" => "provision new stack" }, dependencies: [] },
        { description: "Branch A provision",  config: { "action" => "provision new stack" }, dependencies: [1] },
        { description: "Branch B provision",  config: { "action" => "provision new stack" }, dependencies: [1] }
      ])

      svc = described_class.new(account: account, mission: single_instance_mission)
      plan = svc.compose!

      expect(plan.steps.count).to eq(1)
      expect(plan.steps.first.execution_config["inputs"]["count"]).to eq(1)
    end
  end

  describe "multi-provider routing (M2 BYOC)" do
    # The decompose stub is reused across cases — it only fires when compose!
    # actually proceeds past the routing check (single-provider or matched
    # preferred_provider paths).
    let(:fake_steps) do
      [
        { description: "Provision the stack", config: { "action" => "provision new stack" }, dependencies: [] }
      ]
    end

    before do
      # `Account.after_create_commit :run_account_bootstrap` autoseeds a
      # "Pro Cloud" System::Provider on every account (plus default regions /
      # instance types / templates). Strip the whole subtree so each scenario
      # controls the provider count explicitly — otherwise the 1-provider
      # tests double up to 2 and the multi-provider tests pull in a third.
      # Use destroy_all so dependent: :destroy cascades through regions,
      # instance types, networks, etc.
      ::System::Provider.where(account_id: account.id).destroy_all

      allow_any_instance_of(Ai::Autonomy::GoalDecompositionService)
        .to receive(:decompose) do |_inst, goal|
          next_version = (Ai::GoalPlan.where(goal_id: goal.id).maximum(:version) || 0) + 1
          plan = Ai::GoalPlan.create!(
            account: account, goal: goal, agent: goal.agent,
            status: "draft", version: next_version, plan_data: { "stub" => true }
          )
          fake_steps.each_with_index do |s, i|
            plan.steps.create!(
              step_number: i + 1,
              step_type: "agent_execution",
              description: s[:description],
              execution_config: s[:config],
              dependencies: s[:dependencies]
            )
          end
          plan
        end
    end

    context "when exactly one provider is configured" do
      let!(:only_provider) do
        ::System::Provider.create!(
          account: account, name: "Only", provider_type: "aws", enabled: true
        )
      end

      it "uses that provider without asking for clarification" do
        plan = service.compose!
        expect(plan).to be_a(Ai::GoalPlan)
        expect(plan.steps.first.execution_config["skill"]).to eq("provision_full_stack")
      end

      it "scopes the resolved provider_region_id to that provider's catalog" do
        own_region = ::System::ProviderRegion.create!(
          account: account, provider: only_provider, name: "us-east-1",
          region_code: "us-east-1", enabled: true
        )
        # A different (disabled) provider with a same-named region must NOT
        # leak into the lookup.
        other = ::System::Provider.create!(
          account: account, name: "Other", provider_type: "gcp", enabled: false
        )
        ::System::ProviderRegion.create!(
          account: account, provider: other, name: "us-east-1",
          region_code: "us-east-1-gcp", enabled: true
        )

        plan = service.compose!
        resolved = plan.steps.first.execution_config["inputs"]["provider_region_id"]
        expect(resolved).to eq(own_region.id)
      end
    end

    context "when multiple providers are configured and brief specifies preferred_provider" do
      let!(:aws_provider) do
        ::System::Provider.create!(
          account: account, name: "AWS-prod", provider_type: "aws", enabled: true
        )
      end
      let!(:digitalocean_provider) do
        ::System::Provider.create!(
          account: account, name: "DO-prod", provider_type: "digitalocean", enabled: true
        )
      end
      let(:brief_with_preference) { brief.merge("preferred_provider" => "digitalocean") }
      let(:mission_with_preference) do
        create(
          :ai_mission,
          account: account,
          created_by: user,
          mission_type: "infrastructure",
          custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
          configuration: { "brief" => brief_with_preference }
        )
      end

      it "uses the preferred provider when it matches an account provider" do
        own_region = ::System::ProviderRegion.create!(
          account: account, provider: digitalocean_provider, name: "us-east-1",
          region_code: "us-east-1", enabled: true
        )
        ::System::ProviderRegion.create!(
          account: account, provider: aws_provider, name: "us-east-1",
          region_code: "us-east-1-aws", enabled: true
        )

        svc = described_class.new(account: account, mission: mission_with_preference)
        plan = svc.compose!
        expect(plan).to be_a(Ai::GoalPlan)
        resolved = plan.steps.first.execution_config["inputs"]["provider_region_id"]
        expect(resolved).to eq(own_region.id)
      end

      it "matches preferred_provider case-insensitively" do
        brief_upcase = brief.merge("preferred_provider" => "AWS")
        mission_upcase = create(
          :ai_mission,
          account: account, created_by: user,
          mission_type: "infrastructure",
          custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
          configuration: { "brief" => brief_upcase }
        )
        svc = described_class.new(account: account, mission: mission_upcase)
        plan = svc.compose!
        expect(plan).to be_a(Ai::GoalPlan)
      end
    end

    context "when multiple providers are configured and brief lacks preferred_provider" do
      let!(:aws_provider) do
        ::System::Provider.create!(
          account: account, name: "AWS", provider_type: "aws", enabled: true
        )
      end
      let!(:digitalocean_provider) do
        ::System::Provider.create!(
          account: account, name: "DigitalOcean", provider_type: "digitalocean", enabled: true
        )
      end

      it "returns a clarification payload instead of a plan" do
        result = service.compose!
        expect(result).to be_a(Hash)
        expect(result[:clarification_needed]).to be true
        expect(result[:message]).to include("multiple cloud providers")
        expect(result[:message]).to include("Which would you like to use?")
        expect(result[:available_providers]).to be_an(Array)
        expect(result[:available_providers].map { |p| p[:type] })
          .to match_array(%w[aws digitalocean])
        result[:available_providers].each do |p|
          expect(p.keys).to match_array([:id, :name, :type])
        end
      end

      it "does NOT invoke the decomposition kernel when clarification is required" do
        expect_any_instance_of(Ai::Autonomy::GoalDecompositionService)
          .not_to receive(:decompose)
        service.compose!
      end

      it "does NOT persist a plan or goal pointer when clarification is required" do
        expect { service.compose! }.not_to change(Ai::AgentGoal, :count)
        expect { service.compose! }.not_to change(Ai::GoalPlan, :count)
      end
    end

    context "when preferred_provider does not match any configured provider" do
      let!(:aws_provider) do
        ::System::Provider.create!(
          account: account, name: "AWS", provider_type: "aws", enabled: true
        )
      end
      let!(:digitalocean_provider) do
        ::System::Provider.create!(
          account: account, name: "DigitalOcean", provider_type: "digitalocean", enabled: true
        )
      end
      let(:brief_unknown) { brief.merge("preferred_provider" => "vultr") }
      let(:mission_unknown) do
        create(
          :ai_mission,
          account: account, created_by: user,
          mission_type: "infrastructure",
          custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
          configuration: { "brief" => brief_unknown }
        )
      end

      it "returns a clarification payload listing the available providers" do
        svc = described_class.new(account: account, mission: mission_unknown)
        result = svc.compose!
        expect(result).to be_a(Hash)
        expect(result[:clarification_needed]).to be true
        expect(result[:available_providers].map { |p| p[:type] })
          .to match_array(%w[aws digitalocean])
      end
    end

    context "when the account has no providers configured (legacy / test path)" do
      it "proceeds without clarification (no provider scoping applied)" do
        plan = service.compose!
        expect(plan).to be_a(Ai::GoalPlan)
      end
    end

    context "when only one of multiple providers is enabled" do
      let!(:enabled_provider) do
        ::System::Provider.create!(
          account: account, name: "AWS", provider_type: "aws", enabled: true
        )
      end
      let!(:disabled_provider) do
        ::System::Provider.create!(
          account: account, name: "DigitalOcean", provider_type: "digitalocean", enabled: false
        )
      end

      it "treats disabled providers as absent and uses the single enabled one" do
        plan = service.compose!
        expect(plan).to be_a(Ai::GoalPlan)
      end
    end
  end

  describe "M3 Run-My-Code routing" do
    # The decompose stub emits a single provision step so we can assert on
    # what `compose!` appends after rewrite/collapse.
    let(:fake_steps) do
      [
        { description: "Provision the stack", config: { "action" => "provision new stack" }, dependencies: [] }
      ]
    end

    before do
      allow_any_instance_of(Ai::Autonomy::GoalDecompositionService)
        .to receive(:decompose) do |_inst, goal|
          next_version = (Ai::GoalPlan.where(goal_id: goal.id).maximum(:version) || 0) + 1
          plan = Ai::GoalPlan.create!(
            account: account, goal: goal, agent: goal.agent,
            status: "draft", version: next_version, plan_data: { "stub" => true }
          )
          fake_steps.each_with_index do |s, i|
            plan.steps.create!(
              step_number: i + 1,
              step_type: "agent_execution",
              description: s[:description],
              execution_config: s[:config],
              dependencies: s[:dependencies]
            )
          end
          plan
        end
    end

    def make_node_module(name)
      ::System::NodeModule.create!(
        account: account,
        name: name,
        variety: "subscription",
        priority: 100,
        enabled: true
      )
    end

    def mission_for(brief)
      create(
        :ai_mission,
        account: account, created_by: user,
        mission_type: "infrastructure",
        custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
        configuration: { "brief" => brief }
      )
    end

    context "use_case → role module mapping" do
      it "maps use_case=discord_bot → nodejs-runtime and appends deploy_app_code" do
        nodejs = make_node_module("nodejs-runtime")
        brief_with_repo = brief.merge(
          "use_case" => "discord_bot",
          "repo_url" => "https://github.com/me/my-bot",
          "branch" => "main",
          "start_command" => "node index.js"
        )

        svc = described_class.new(account: account, mission: mission_for(brief_with_repo))
        plan = svc.compose!

        # deploy_app_code step appended
        skills = plan.steps.in_order.pluck(:execution_config).map { |c| c["skill"] }
        expect(skills).to eq(%w[provision_full_stack deploy_app_code])

        # role module attached to the default template
        template = ::System::NodeTemplate.where(account_id: account.id).order(:created_at).first
        expect(template.node_modules.pluck(:id)).to include(nodejs.id)
      end

      it "runtime_hint=python overrides use_case mapping" do
        python = make_node_module("python-runtime")
        nodejs = make_node_module("nodejs-runtime")

        brief_python = brief.merge(
          "use_case" => "discord_bot", # would normally map to nodejs-runtime
          "runtime_hint" => "python",
          "repo_url" => "https://github.com/me/svc",
          "start_command" => "python app.py"
        )

        svc = described_class.new(account: account, mission: mission_for(brief_python))
        svc.compose!

        template = ::System::NodeTemplate.where(account_id: account.id).order(:created_at).first
        attached_ids = template.node_modules.pluck(:id)
        expect(attached_ids).to include(python.id)
        expect(attached_ids).not_to include(nodejs.id)
      end

      it "runtime_hint that explicitly maps to nil (e.g. ruby) attaches no module" do
        nodejs = make_node_module("nodejs-runtime")

        brief_ruby = brief.merge(
          "use_case" => "discord_bot",
          "runtime_hint" => "ruby",
          "repo_url" => "https://github.com/me/svc"
        )

        svc = described_class.new(account: account, mission: mission_for(brief_ruby))
        svc.compose!

        template = ::System::NodeTemplate.where(account_id: account.id).order(:created_at).first
        expect(template.node_modules.pluck(:id)).not_to include(nodejs.id)
      end

      it "use_case=database → postgres-server module" do
        pg = make_node_module("postgres-server")

        brief_db = brief.merge(
          "use_case" => "database",
          "repo_url" => nil # no deploy step in this scenario
        )

        svc = described_class.new(account: account, mission: mission_for(brief_db))
        svc.compose!

        template = ::System::NodeTemplate.where(account_id: account.id).order(:created_at).first
        expect(template.node_modules.pluck(:id)).to include(pg.id)
      end

      it "falls back to nodejs-runtime when use_case is unknown and no hint given" do
        nodejs = make_node_module("nodejs-runtime")

        brief_default = brief.merge(
          "use_case" => "Primary OLTP for a side-business SaaS", # not a known key
          "runtime_hint" => nil,
          "repo_url" => nil
        )

        svc = described_class.new(account: account, mission: mission_for(brief_default))
        svc.compose!

        template = ::System::NodeTemplate.where(account_id: account.id).order(:created_at).first
        expect(template.node_modules.pluck(:id)).to include(nodejs.id)
      end

      it "skips role-module attachment silently when the named module isn't seeded" do
        # No NodeModule created — Slice A hasn't run yet.
        brief_default = brief.merge(
          "use_case" => "discord_bot",
          "repo_url" => nil
        )

        svc = described_class.new(account: account, mission: mission_for(brief_default))
        expect { svc.compose! }.not_to raise_error
      end
    end

    # attach_role_module_to_template! was the FIFTH TemplateModule writer and
    # the only one that created the join unchecked. The other four run the
    # assignment through System::TemplateCompositionAnalysis first
    # (TemplateModulesController#create, system_assign_module_to_template,
    # Gitops::ApplyService, ModuleSmokeVerifyExecutor) and refuse an addition
    # that introduces an error-severity composition conflict.
    #
    # It matters more here than at any of those four because this writer always
    # targets the account's DEFAULT template — the oldest one, which every
    # later mission composes onto. A conflict landed here becomes permanent
    # BASELINE: additions_verdict diffs against the template's current closure,
    # so once a collision is in the baseline every later assignment is obliged
    # to treat it as acceptable, and TemplateExpansionService then ships it to
    # real nodes.
    context "composition conflicts on the default template" do
      let!(:runtime_category) do
        ::System::NodeModuleCategory.create!(
          account: account, name: "Runtime", variety: "instance", position: 2
        )
      end

      def default_template
        ::System::NodeTemplate.where(account_id: account.id).order(:created_at).first
      end

      # Only one instance-variety module may ship per category — a second is an
      # error-severity `instance_variety_collision` in
      # TemplateComposerService#detect_conflicts.
      def make_instance_module(name)
        ::System::NodeModule.create!(
          account: account, name: name, variety: "instance",
          category: runtime_category, priority: 100, enabled: true
        )
      end

      def discord_bot_mission
        mission_for(brief.merge("use_case" => "discord_bot", "repo_url" => nil))
      end

      it "refuses an attachment that would introduce an instance-variety collision" do
        incumbent = make_instance_module("incumbent-runtime")
        ::System::TemplateModule.create!(node_template: default_template, node_module: incumbent)
        nodejs = make_instance_module("nodejs-runtime")

        described_class.new(account: account, mission: discord_bot_mission).compose!

        attached = default_template.reload.node_modules.pluck(:id)
        expect(attached).not_to include(nodejs.id)
        # The incumbent is untouched: refusing the addition must not detach
        # what was already composing cleanly.
        expect(attached).to include(incumbent.id)
      end

      it "still attaches when the addition introduces no conflict" do
        # Same shape, minus the collision: the guard must refuse conflicts, not
        # role-module attachment in general.
        nodejs = make_instance_module("nodejs-runtime")

        described_class.new(account: account, mission: discord_bot_mission).compose!

        expect(default_template.reload.node_modules.pluck(:id)).to include(nodejs.id)
      end

      it "refuses rather than writing unchecked when the analysis is unavailable" do
        # Core mode: the system extension supplies both the models and the
        # guard, so a build where the guard is missing must not fall back to
        # the unguarded write this task removed. Fail closed — skipping costs
        # one module attachment, proceeding can poison the default template's
        # baseline permanently.
        nodejs = make_instance_module("nodejs-runtime")
        hide_const("System::TemplateCompositionAnalysis")

        described_class.new(account: account, mission: discord_bot_mission).compose!

        expect(default_template.reload.node_modules.pluck(:id)).not_to include(nodejs.id)
      end

      it "skips the attachment rather than failing the compose when the analysis raises" do
        # The analysis resolves a closure over catalog data this service does
        # not own. A guard that can take mission compose down with it would be
        # a worse bargain than the unguarded write it replaced, so it fails
        # closed here too: no plan lost, and still nothing written unchecked.
        nodejs = make_instance_module("nodejs-runtime")
        allow(::System::TemplateCompositionAnalysis).to receive(:new)
          .and_raise(StandardError, "catalog resolution blew up")

        svc = described_class.new(account: account, mission: discord_bot_mission)
        expect { svc.compose! }.not_to raise_error
        expect(default_template.reload.node_modules.pluck(:id)).not_to include(nodejs.id)
      end

      it "does not fail the compose when it refuses the attachment" do
        incumbent = make_instance_module("incumbent-runtime")
        ::System::TemplateModule.create!(node_template: default_template, node_module: incumbent)
        make_instance_module("nodejs-runtime")

        # Best-effort by contract: a refused attachment is logged and skipped,
        # exactly like a role module Slice A has not seeded. The mission plan
        # is not the thing in conflict and must still compose.
        svc = described_class.new(account: account, mission: discord_bot_mission)
        expect { svc.compose! }.not_to raise_error
        expect(svc.compose!).to be_present
      end
    end

    context "deploy_app_code step shape" do
      let(:brief_with_repo) do
        brief.merge(
          "use_case" => "discord_bot",
          "scale" => { "initial" => 1, "target" => 1, "growth_profile" => "steady" },
          "repo_url" => "https://github.com/me/my-bot",
          "branch" => "develop",
          "start_command" => "node bot.js",
          "runtime_hint" => "node"
        )
      end

      it "no repo_url → no deploy_app_code step appended" do
        plan = service.compose!
        skills = plan.steps.in_order.pluck(:execution_config).map { |c| c["skill"] }
        expect(skills).not_to include("deploy_app_code")
      end

      it "deploy_app_code step has the documented inputs shape" do
        make_node_module("nodejs-runtime")
        m = mission_for(brief_with_repo)
        svc = described_class.new(account: account, mission: m)
        plan = svc.compose!

        deploy_step = plan.steps.find { |s| s.execution_config["skill"] == "deploy_app_code" }
        expect(deploy_step).not_to be_nil
        expect(deploy_step.description).to start_with("Deploy ")

        cfg = deploy_step.execution_config
        expect(cfg["skill"]).to eq("deploy_app_code")
        expect(cfg["on_failure"]).to eq("rollback")

        inputs = cfg["inputs"]
        expect(inputs.keys).to include("repo_url", "branch", "start_command", "mission_id", "brief")
        expect(inputs["repo_url"]).to eq("https://github.com/me/my-bot")
        expect(inputs["branch"]).to eq("develop")
        expect(inputs["start_command"]).to eq("node bot.js")
        expect(inputs["mission_id"]).to eq(m.id)
        expect(inputs["brief"]).to include("repo_url" => "https://github.com/me/my-bot")
      end

      it "deploy_app_code defaults branch to 'main' when brief omits it" do
        make_node_module("nodejs-runtime")
        b = brief_with_repo.merge("branch" => nil)
        svc = described_class.new(account: account, mission: mission_for(b))
        plan = svc.compose!
        deploy_step = plan.steps.find { |s| s.execution_config["skill"] == "deploy_app_code" }
        expect(deploy_step.execution_config["inputs"]["branch"]).to eq("main")
      end

      it "deploy_app_code step depends on the last provision_full_stack step" do
        make_node_module("nodejs-runtime")
        svc = described_class.new(account: account, mission: mission_for(brief_with_repo))
        plan = svc.compose!

        deploy_step = plan.steps.find { |s| s.execution_config["skill"] == "deploy_app_code" }
        provision_step = plan.steps.find { |s| s.execution_config["skill"] == "provision_full_stack" }
        expect(deploy_step.dependencies).to eq([provision_step.step_number])
      end

      it "wires node_instance_id from the upstream provision step's outputs (cross-step data flow)" do
        make_node_module("nodejs-runtime")
        svc = described_class.new(account: account, mission: mission_for(brief_with_repo))
        plan = svc.compose!

        deploy_step = plan.steps.find { |s| s.execution_config["skill"] == "deploy_app_code" }
        provision_step = plan.steps.find { |s| s.execution_config["skill"] == "provision_full_stack" }

        mapping = deploy_step.execution_config["depends_on_outputs"]
        expect(mapping).to be_present
        expect(mapping["node_instance_id"]).to eq(
          "from_step" => provision_step.step_number,
          "path" => "outputs.node_instance_ids",
          "select" => "first"
        )
      end

      it "deploy_app_code step is step_type=provisioning_skill (not collapsed with provision_full_stack)" do
        make_node_module("nodejs-runtime")
        svc = described_class.new(account: account, mission: mission_for(brief_with_repo))
        plan = svc.compose!

        # Two distinct steps — the M1 step-collapse only merges same-skill
        # consecutive steps, and deploy_app_code != provision_full_stack.
        expect(plan.steps.count).to eq(2)
        types = plan.steps.in_order.pluck(:step_type)
        expect(types).to all(eq("provisioning_skill"))
      end
    end

    context "validate_plan accepts deploy_app_code" do
      it "treats deploy_app_code as an allowed executor" do
        make_node_module("nodejs-runtime")
        b = brief.merge(
          "use_case" => "discord_bot",
          "scale" => { "initial" => 1, "target" => 1, "growth_profile" => "steady" },
          "repo_url" => "https://github.com/me/x"
        )
        svc = described_class.new(account: account, mission: mission_for(b))
        plan = svc.compose!
        result = svc.validate_plan(plan)
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end
    end
  end

  describe "CostCapGuard integration" do
    let(:fake_steps) do
      [
        { description: "Provision the stack", config: { "action" => "provision new stack" }, dependencies: [] }
      ]
    end

    before do
      allow_any_instance_of(Ai::Autonomy::GoalDecompositionService)
        .to receive(:decompose) do |_inst, goal|
          next_version = (Ai::GoalPlan.where(goal_id: goal.id).maximum(:version) || 0) + 1
          plan = Ai::GoalPlan.create!(
            account: account, goal: goal, agent: goal.agent,
            status: "draft", version: next_version, plan_data: { "stub" => true }
          )
          fake_steps.each_with_index do |s, i|
            plan.steps.create!(
              step_number: i + 1,
              step_type: "agent_execution",
              description: s[:description],
              execution_config: s[:config],
              dependencies: s[:dependencies]
            )
          end
          plan
        end
    end

    it "returns nil and exposes cap_exceeded_payload when the daily LLM spend cap is hit" do
      allow(::Ai::Provisioning::CostCapGuard).to receive(:allow?).and_return(
        ::Ai::Provisioning::CostCapGuard::Result.new(
          status: :cap_exceeded,
          payload: { spent: 0.55, cap: 0.50, remaining: 0.0 }
        )
      )

      result = service.compose!
      expect(result).to be_nil
      expect(service.cap_exceeded_payload).to include(spent: 0.55, cap: 0.50)
    end

    it "proceeds normally when the cap guard returns ok" do
      allow(::Ai::Provisioning::CostCapGuard).to receive(:allow?).and_return(
        ::Ai::Provisioning::CostCapGuard::Result.new(
          status: :ok,
          payload: { spent: 0.10, cap: 0.50, remaining: 0.40 }
        )
      )

      plan = service.compose!
      expect(plan).to be_a(Ai::GoalPlan)
      expect(service.cap_exceeded_payload).to be_nil
    end
  end
end
