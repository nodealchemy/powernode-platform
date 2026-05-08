# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Provisioning::TopologyRendererService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  let(:default_brief) do
    {
      "intent" => "Provision a 3-node Postgres cluster",
      "use_case" => "OLTP",
      "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
      "regions" => ["us-east-1"],
      "compliance" => [],
      "budget_cap_usd_monthly" => 500.0,
      "data_residency" => [],
      "preferred_provider" => "aws"
    }
  end

  def build_mission(brief: default_brief)
    create(
      :ai_mission,
      account: account,
      created_by: user,
      mission_type: "infrastructure",
      custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
      configuration: { "brief" => brief }
    )
  end

  def build_goal(mission)
    Ai::AgentGoal.create!(
      account: account, agent: agent,
      title: "Provisioning goal", description: "test",
      goal_type: "creation", status: "pending", priority: 3, progress: 0.0,
      success_criteria: { "mission_id" => mission.id },
      metadata: { "provisioning_mission_id" => mission.id }
    )
  end

  def build_plan(goal, steps:)
    plan = Ai::GoalPlan.create!(
      account: account, goal: goal, agent: agent,
      status: "draft", version: 1
    )
    steps.each_with_index do |attrs, idx|
      Ai::GoalPlanStep.create!(
        plan: plan, step_number: idx + 1,
        step_type: "provisioning_skill", status: "pending",
        description: attrs[:description].to_s,
        execution_config: attrs[:config],
        dependencies: attrs[:dependencies] || []
      )
    end
    plan
  end

  describe "#render" do
    it "returns the documented envelope shape" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => default_brief } },
          description: "stand up postgres" }
      ])

      result = described_class.new(account: account, plan: plan).render
      expect(result.keys).to contain_exactly(:nodes, :edges, :regions, :estimated_resources)
      expect(result[:nodes]).to be_an(Array)
      expect(result[:edges]).to be_an(Array)
      expect(result[:regions]).to be_an(Array)
    end

    it "always includes a user_device + gateway pair" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => default_brief } } }
      ])

      result = described_class.new(account: account, plan: plan).render
      types = result[:nodes].map { |n| n[:type] }
      expect(types).to include("user_device", "gateway", "external_provider")
    end

    it "emits one region container per region in the brief" do
      brief = default_brief.merge("regions" => ["us-east-1", "eu-west-1"])
      mission = build_mission(brief: brief)
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => brief } } }
      ])

      result = described_class.new(account: account, plan: plan).render
      expect(result[:regions].map { |r| r[:name] }).to contain_exactly("us-east-1", "eu-west-1")
    end

    it "synthesizes one compute node per scale.initial when count not pinned" do
      brief = default_brief.merge("scale" => { "initial" => 4 })
      mission = build_mission(brief: brief)
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => brief } },
          description: "stand up the cluster" }
      ])

      result = described_class.new(account: account, plan: plan).render
      compute_or_db = result[:nodes].select { |n| %w[compute database].include?(n[:type]) }
      expect(compute_or_db.size).to eq(4)
    end

    it "uses 'database' node type when intent mentions postgres" do
      brief = default_brief.merge("intent" => "Postgres cluster", "scale" => { "initial" => 2 })
      mission = build_mission(brief: brief)
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => brief } },
          description: "postgres" }
      ])

      result = described_class.new(account: account, plan: plan).render
      db_nodes = result[:nodes].select { |n| n[:type] == "database" }
      expect(db_nodes.size).to eq(2)
      expect(db_nodes.map { |n| n[:label] }).to include(match(/primary/i), match(/replica/i))
    end

    it "creates a volume per compute node" do
      brief = default_brief.merge("scale" => { "initial" => 2 })
      mission = build_mission(brief: brief)
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => brief } } }
      ])

      result = described_class.new(account: account, plan: plan).render
      volumes = result[:nodes].select { |n| n[:type] == "volume" }
      expect(volumes.size).to eq(2)
    end

    it "skips compute synthesis for non-compute skills" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "drift_remediate", "inputs" => {} } }
      ])

      result = described_class.new(account: account, plan: plan).render
      compute_nodes = result[:nodes].select { |n| %w[compute database cache].include?(n[:type]) }
      expect(compute_nodes).to be_empty
    end

    it "emits an ingress edge from user_device to gateway" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => default_brief } } }
      ])

      result = described_class.new(account: account, plan: plan).render
      ingress = result[:edges].find { |e| e[:kind] == "ingress" }
      expect(ingress).to be_present
    end

    it "tolerates an empty regions array by falling back to 'default'" do
      brief = default_brief.merge("regions" => [])
      mission = build_mission(brief: brief)
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => brief } } }
      ])

      result = described_class.new(account: account, plan: plan).render
      expect(result[:regions].first[:name]).to eq("default")
    end

    it "calls Sdwan::TopologyCompiler.compile_for_network in dry-run when sdwan_network is in inputs" do
      sdwan_payload = { "name" => "preview-net-#{SecureRandom.hex(2)}", "routing_protocol" => "static" }
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack",
                    "inputs" => { "brief" => default_brief, "sdwan_network" => sdwan_payload } } }
      ])

      expect(::Sdwan::TopologyCompiler).to receive(:compile_for_network)
        .with(an_instance_of(::Sdwan::Network)).and_return([])

      described_class.new(account: account, plan: plan).render
    end
  end
end
