# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Provisioning::RiskScorerService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  let(:simple_brief) do
    {
      "intent" => "Provision a small stack",
      "use_case" => "OLTP",
      "scale" => { "initial" => 2, "target" => 3, "growth_profile" => "linear" },
      "regions" => ["us-east-1"],
      "compliance" => [],
      "budget_cap_usd_monthly" => 500.0,
      "data_residency" => [],
      "preferred_provider" => nil
    }
  end

  subject(:service) { described_class.new(account: account) }

  def build_mission(brief: simple_brief)
    create(
      :ai_mission,
      account: account, created_by: user,
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
        execution_config: attrs[:config],
        dependencies: attrs[:dependencies] || []
      )
    end
    plan
  end

  describe "#score" do
    it "returns the documented envelope shape" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 2 } } }
      ])

      result = service.score(plan: plan)
      expect(result.keys).to contain_exactly(:score, :severity, :factors)
      expect(result[:severity]).to be_in(%w[low med high])
      expect(result[:score]).to be_between(0, 100)
      expect(result[:factors]).to be_an(Array)
    end

    it "rates a small single-region plan as low severity" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 2 } } }
      ])

      result = service.score(plan: plan)
      expect(result[:severity]).to eq("low")
    end

    it "adds the instance count factor when total instances exceed the threshold" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_cluster", "inputs" => { "count" => 8 } } }
      ])

      result = service.score(plan: plan)
      factor = result[:factors].find { |f| f[:name] == "Instance count" }
      expect(factor).to be_present
      expect(factor[:weight]).to eq(described_class::INSTANCE_COUNT_WEIGHT)
    end

    it "adds the public IP factor for each step that allocates a public IP" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 1, "public_ip" => true } } },
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 1, "public_ip" => true } } }
      ])

      result = service.score(plan: plan)
      factor = result[:factors].find { |f| f[:name] == "Public IP allocations" }
      expect(factor).to be_present
      expect(factor[:weight]).to eq(described_class::PUBLIC_IP_WEIGHT * 2)
    end

    it "adds the SDWAN federation factor when a step plans cross-account peering" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack",
                    "inputs" => { "count" => 1, "sdwan_federation" => { "enabled" => true } } } }
      ])

      result = service.score(plan: plan)
      factor = result[:factors].find { |f| f[:name] == "SDWAN federation" }
      expect(factor).to be_present
      expect(factor[:severity]).to eq("high")
    end

    it "adds the cross-region factor when brief.regions has more than one region" do
      mission = build_mission(brief: simple_brief.merge("regions" => ["us-east-1", "eu-west-1"]))
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 1 } } }
      ])

      result = service.score(plan: plan)
      factor = result[:factors].find { |f| f[:name] == "Cross-region" }
      expect(factor).to be_present
      expect(factor[:weight]).to eq(described_class::CROSS_REGION_WEIGHT)
    end

    it "adds the data residency factor when residency is asserted" do
      mission = build_mission(brief: simple_brief.merge("data_residency" => ["EU"]))
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 1 } } }
      ])

      result = service.score(plan: plan)
      factor = result[:factors].find { |f| f[:name] == "Data residency override" }
      expect(factor).to be_present
      expect(factor[:severity]).to eq("high")
    end

    it "adds the budget headroom factor when estimated cost is within 10% of cap" do
      tight_brief = simple_brief.merge("budget_cap_usd_monthly" => 50.0,
                                       "scale" => { "initial" => 5 })
      mission = build_mission(brief: tight_brief)
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack",
                    "inputs" => { "count" => 5, "with_storage_gb" => 100, "brief" => tight_brief } } }
      ])

      # A declared 100GB volume × 5 instances × $0.10/GB-month = $50.00, exactly
      # at the $50 cap, so headroom is 0% and the factor fires.
      #
      # This fixture previously declared no resources at all and leaned on
      # CostEstimatorService's phantom storage + egress defaults to manufacture
      # a cost. IMP-051509357291 removed those, and #budget_headroom_factors
      # bails on a non-positive estimate — so the example needs a plan that
      # genuinely costs something, not one that used to be billed for nothing.
      result = service.score(plan: plan)
      factor = result[:factors].find { |f| f[:name] == "Budget headroom" }
      expect(factor).to be_present
    end

    it "produces severity 'med' when factors land in 30..59" do
      brief = simple_brief.merge("regions" => ["us-east-1", "eu-west-1"]) # +15 cross-region
      mission = build_mission(brief: brief)
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_cluster", "inputs" => { "count" => 8 } } }, # +15 instance count
        { config: { "skill" => "provision_full_stack",
                    "inputs" => { "count" => 1, "public_ip" => true } } } # +10 public ip
      ])

      result = service.score(plan: plan)
      expect(result[:score]).to be >= 30
      expect(result[:severity]).to eq("med")
    end

    it "caps the score at 100" do
      brief = simple_brief.merge(
        "regions" => ["us-east-1", "eu-west-1", "ap-south-1"],
        "data_residency" => ["EU"]
      )
      mission = build_mission(brief: brief)
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_cluster", "inputs" => { "count" => 12 } } },
        { config: { "skill" => "provision_full_stack",
                    "inputs" => { "count" => 1, "public_ip" => true,
                                  "sdwan_federation" => { "enabled" => true } } } }
      ])

      result = service.score(plan: plan)
      expect(result[:score]).to be <= 100
      expect(result[:severity]).to eq("high")
    end

    it "every factor has the documented shape" do
      brief = simple_brief.merge("regions" => ["us-east-1", "eu-west-1"])
      mission = build_mission(brief: brief)
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 1 } } }
      ])

      result = service.score(plan: plan)
      result[:factors].each do |f|
        expect(f.keys).to contain_exactly(:name, :weight, :severity, :explanation)
        expect(f[:severity]).to be_in(%w[low med high])
      end
    end
  end
end
