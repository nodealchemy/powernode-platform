# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Provisioning::CostEstimatorService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, status: "active")
  end

  subject(:service) { described_class.new(account: account) }

  # ---- helpers --------------------------------------------------------------

  let(:default_brief) do
    {
      "intent" => "Provision a 3-node cluster",
      "use_case" => "OLTP",
      "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
      "regions" => ["us-east-1"],
      "compliance" => [],
      "budget_cap_usd_monthly" => 500.0,
      "data_residency" => [],
      "preferred_provider" => nil
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
        execution_config: attrs[:config],
        dependencies: attrs[:dependencies] || []
      )
    end
    plan
  end

  # ---- estimate(plan:) ------------------------------------------------------

  describe "#estimate" do
    it "returns the documented envelope shape" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => default_brief } } }
      ])

      result = service.estimate(plan: plan)
      expect(result.keys).to contain_exactly(:monthly_usd, :one_time_usd, :by_resource, :confidence)
      expect(result[:by_resource]).to be_an(Array)
      expect(result[:by_resource].first.keys).to include(:resource_type, :name, :monthly_usd, :count)
      expect(result[:confidence]).to be_in(%w[high med low])
    end

    it "falls back to brief.scale.initial for instance count when step omits count" do
      mission = build_mission(brief: default_brief.merge("scale" => { "initial" => 4 }))
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "brief" => default_brief } } }
      ])

      result = service.estimate(plan: plan)
      compute_row = result[:by_resource].find { |r| r[:resource_type] == "compute" }
      expect(compute_row[:count]).to eq(4)
    end

    it "uses explicit step input count over brief scale" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_cluster", "inputs" => { "count" => 7 } } }
      ])

      result = service.estimate(plan: plan)
      compute_row = result[:by_resource].find { |r| r[:resource_type] == "compute" }
      expect(compute_row[:count]).to eq(7)
    end

    it "downgrades confidence to medium when plan contains unpriceable skills" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 2 } } },
        { config: { "skill" => "drift_remediate", "inputs" => {} } } # unpriceable
      ])

      result = service.estimate(plan: plan)
      expect(result[:confidence]).to eq("med")
    end

    it "emits an SDWAN line with zero monthly cost for sdwan_failover steps" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "sdwan_failover", "inputs" => { "brief" => default_brief } } }
      ])

      result = service.estimate(plan: plan)
      sdwan_row = result[:by_resource].find { |r| r[:resource_type] == "sdwan" }
      expect(sdwan_row).to be_present
      expect(sdwan_row[:monthly_usd]).to eq(0.0)
    end

    it "estimates storage and egress lines for compute steps" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 2 } } }
      ])

      result = service.estimate(plan: plan)
      types = result[:by_resource].map { |r| r[:resource_type] }
      expect(types).to include("storage", "network")
    end

    it "returns zero monthly_usd when plan has no priceable steps" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "drift_remediate", "inputs" => {} } }
      ])

      result = service.estimate(plan: plan)
      expect(result[:monthly_usd]).to eq(0.0)
      expect(result[:confidence]).to eq("low")
    end

    it "collapses duplicate (resource_type, name) rows" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 2 } } },
        { config: { "skill" => "provision_full_stack", "inputs" => { "count" => 3 } } }
      ])

      result = service.estimate(plan: plan)
      compute_rows = result[:by_resource].select { |r| r[:resource_type] == "compute" }
      # Same region label "(instance type TBD)" merges into one row.
      expect(compute_rows.size).to eq(1)
      expect(compute_rows.first[:count]).to eq(5)
    end
  end

  # ---- estimate_step ---------------------------------------------------------

  describe "#estimate_step" do
    it "marks runbook_generate steps as unpriceable" do
      step = double("Step",
                    execution_config: {
                      "skill" => "runbook_generate", "inputs" => {}
                    })
      result = service.estimate_step(step: step)
      expect(result[:unpriceable]).to be true
      expect(result[:by_resource]).to be_empty
    end

    it "emits one compute row per priced provision step" do
      step = double("Step",
                    execution_config: {
                      "skill" => "provision_full_stack",
                      "inputs" => { "count" => 2, "brief" => default_brief }
                    })
      result = service.estimate_step(step: step, brief: default_brief)
      compute_rows = result[:by_resource].select { |r| r[:resource_type] == "compute" }
      expect(compute_rows.size).to eq(1)
      expect(compute_rows.first[:count]).to eq(2)
    end
  end

  # ---- pricing lookup (system instance type) --------------------------------

  describe "instance type pricing lookup", :system_extension do
    let(:system_provider) do
      ::System::Provider.create!(
        account: account, name: "test-provider-#{SecureRandom.hex(2)}",
        provider_type: "aws"
      )
    end

    let(:instance_type) do
      ::System::ProviderInstanceType.create!(
        account: account, provider: system_provider,
        name: "c5.large-#{SecureRandom.hex(2)}",
        instance_type_code: "c5.large.#{SecureRandom.hex(2)}",
        hourly_price: 0.085,
        vcpus: 2, memory_mb: 4096
      )
    end

    it "uses the stored hourly_price for compute pricing when provider_instance_type_id is set" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack",
                    "inputs" => { "provider_instance_type_id" => instance_type.id, "count" => 2 } } }
      ])

      result = service.estimate(plan: plan)
      compute_row = result[:by_resource].find { |r| r[:resource_type] == "compute" }
      expected_monthly = (0.085 * described_class::HOURS_PER_MONTH * 2).round(2)
      expect(compute_row[:monthly_usd]).to eq(expected_monthly)
    end

    it "downgrades confidence to low when instance type pricing is older than 30 days" do
      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack",
                    "inputs" => { "provider_instance_type_id" => instance_type.id, "count" => 1 } } }
      ])
      instance_type.update_columns(updated_at: 60.days.ago)

      result = service.estimate(plan: plan)
      expect(result[:confidence]).to eq("low")
    end

    it "does not report high confidence when a pinned instance type has no price" do
      unpriced_type = ::System::ProviderInstanceType.create!(
        account: account, provider: system_provider,
        name: "unpriced-#{SecureRandom.hex(2)}",
        instance_type_code: "unpriced.#{SecureRandom.hex(2)}",
        hourly_price: nil,
        vcpus: 2, memory_mb: 4096
      )

      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack",
                    "inputs" => { "provider_instance_type_id" => unpriced_type.id } } }
      ])
      # Keep pricing fresh so staleness is NOT the reason for any downgrade.
      unpriced_type.update_columns(updated_at: Time.current)

      result = service.estimate(plan: plan)
      compute_row = result[:by_resource].find { |r| r[:resource_type] == "compute" }
      expect(compute_row[:monthly_usd]).to eq(0.0)
      # The pinned compute couldn't be priced — defaulted storage/egress must not
      # rescue confidence up to "high".
      expect(result[:confidence]).not_to eq("high")
    end

    it "ignores instance types that belong to other accounts" do
      other_account = create(:account)
      other_provider = ::System::Provider.create!(
        account: other_account, name: "other-#{SecureRandom.hex(2)}", provider_type: "aws"
      )
      other_type = ::System::ProviderInstanceType.create!(
        account: other_account, provider: other_provider,
        name: "isolation-#{SecureRandom.hex(2)}",
        instance_type_code: "iso.#{SecureRandom.hex(2)}",
        hourly_price: 1.0
      )

      mission = build_mission
      goal = build_goal(mission)
      plan = build_plan(goal, steps: [
        { config: { "skill" => "provision_full_stack",
                    "inputs" => { "provider_instance_type_id" => other_type.id, "count" => 1 } } }
      ])

      result = service.estimate(plan: plan)
      compute_row = result[:by_resource].find { |r| r[:resource_type] == "compute" }
      # Treated as unpinned — placeholder, no priced compute.
      expect(compute_row[:monthly_usd]).to eq(0.0)
    end
  end
end
