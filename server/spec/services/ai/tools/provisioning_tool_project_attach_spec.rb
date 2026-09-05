# frozen_string_literal: true

require "rails_helper"

# APO increment `app-4-project-noun` — attach-on-capture.
#
# The priority use case is "a git URL becomes something running, exposed,
# monitored and owned by a team". That chain starts at the provisioning brief,
# which until now created a bare infrastructure mission and nothing that
# outlives it. Capturing a brief must therefore also produce the PROJECT the
# mission belongs to.
#
# THE ADDITIVE GUARANTEE is asserted here too, and it is the load-bearing half:
# every mission that already exists has no project, and a nil project must not
# break any current caller. A migration that made the column NOT NULL, or a
# reader that assumed a project, would break the entire installed base
# silently. These examples pin that a project-less mission still resolves its
# bounds, serializes, and advances.
RSpec.describe "ProvisioningTool — project attach on brief capture" do
  let(:account) { create(:account) }
  let(:user) do
    create(:user, account: account, permissions: %w[ai.missions.read ai.missions.manage])
  end
  let(:tool) { Ai::Tools::ProvisioningTool.new(account: account, user: user) }

  let!(:provisioning_template) do
    ::Ai::MissionTemplate.find_or_create_by!(
      name: Ai::Tools::ProvisioningTool::MISSION_TEMPLATE_NAME, template_type: "system"
    ) do |t|
      t.account = nil
      t.description = "test fixture"
      t.mission_type = "infrastructure"
      t.status = "active"
      t.is_default = true
      t.version = 1
      t.phases = [
        { "order" => 0, "key" => "capture_intent", "label" => "Capture", "requires_approval" => false },
        { "order" => 1, "key" => "compose_plan",   "label" => "Compose", "requires_approval" => false }
      ]
      t.approval_gates = []
      t.rejection_mappings = {}
      t.skill_compositions = {}
      t.default_configuration = {}
    end
  end

  before do
    allow_any_instance_of(::Ai::Provisioning::IntentCaptureService)
      .to receive(:capture)
      .and_return({ brief: { "workload" => "ledger api" }, missing_fields: %w[scale] })
  end

  describe "a new brief" do
    it "creates a project and makes the mission belong to it" do
      expect {
        tool.execute(params: {
          action: "platform_provisioning_capture_brief",
          natural_language: "Deploy the ledger API from git.example.com/ledger"
        })
      }.to change(Ai::Project, :count).by(1)

      project = Ai::Project.order(:created_at).last
      mission = Ai::Mission.order(:created_at).last

      expect(project.account_id).to eq(account.id)
      expect(mission.project).to eq(project)
      expect(project.missions).to contain_exactly(mission)
      # Reachability of the mission-keyed metric time series IS this key set.
      expect(project.mission_ids).to eq([ mission.id ])
    end

    it "names the project from the same hint the mission is named from" do
      tool.execute(params: {
        action: "platform_provisioning_capture_brief",
        natural_language: "Ledger API service"
      })

      project = Ai::Project.order(:created_at).last

      expect(project.name).to eq("Ledger API service")
      expect(project.slug).to eq("ledger-api-service")
      expect(project.created_by).to eq(user)
      expect(project.status).to eq("active")
    end
  end

  describe "a clarification onto an EXISTING mission" do
    it "does not create a second project" do
      tool.execute(params: {
        action: "platform_provisioning_capture_brief",
        natural_language: "Deploy the ledger API"
      })
      mission = Ai::Mission.order(:created_at).last
      project = mission.project

      allow_any_instance_of(::Ai::Provisioning::IntentCaptureService)
        .to receive(:refine)
        .and_return({ brief: { "workload" => "ledger api", "scale" => 3 }, missing_fields: [] })

      expect {
        tool.execute(params: {
          action: "platform_provisioning_capture_brief",
          mission_id: mission.id,
          natural_language: "three replicas"
        })
      }.not_to change(Ai::Project, :count)

      expect(mission.reload.project).to eq(project)
    end
  end

  # APO app-5 — the brief path is also where a project acquires its OWNING TEAM.
  describe "the project's owning team" do
    let!(:openai) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }

    def canonical(slug, name)
      create(:ai_agent, :global, owner_account: account, slug: slug, source_key: slug,
                                 name: name, agent_type: "monitor", is_system: true)
    end

    before do
      canonical("infrastructure-health-monitor", "Infrastructure Health Monitor")
      canonical("release-manager", "Release Manager")
      canonical("system-health-monitor", "System Health Monitor")
      silence_warnings { load Rails.root.join("db", "seeds", "ai_project_operations_team_seed.rb") }
    end

    it "materialises a team for the project the brief created" do
      tool.execute(params: {
        action: "platform_provisioning_capture_brief",
        natural_language: "Deploy the ledger API"
      })

      project = Ai::Project.order(:created_at).last

      expect(project.team).to be_present
      expect(project.team.members.count).to eq(3)
      # Clones, never the canonicals (ruling 8).
      expect(project.team.members.includes(:agent).map { |m| m.agent.account_id }.uniq).to eq([ account.id ])
    end

    it "still creates the project when the template is not seeded" do
      Ai::TeamTemplate.where(slug: Ai::Projects::TeamProvisioner::TEMPLATE_SLUG).destroy_all

      tool.execute(params: {
        action: "platform_provisioning_capture_brief",
        natural_language: "Deploy the ledger API"
      })

      project = Ai::Project.order(:created_at).last

      expect(project).to be_present
      expect(project.team).to be_nil
      expect(Ai::Mission.order(:created_at).last.project).to eq(project)
    end
  end

  describe "THE ADDITIVE GUARANTEE — a mission with no project" do
    let(:orphan) do
      create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                          configuration: { "watch_policies" => { "auto_scale_max_replicas" => 4 } })
    end

    it "still resolves its scaling bounds" do
      expect(orphan.project).to be_nil

      bounds = orphan.scaling_bounds

      expect(bounds.min).to eq(1)
      expect(bounds.max).to eq(4)
      expect(bounds.auto_scale_out?).to be true
    end

    it "still resolves its utilization targets" do
      expect { orphan.utilization_targets }.not_to raise_error
      expect(orphan.utilization_targets.cpu_pct).to be_nil
    end

    it "still serializes through the mission summary and details readers" do
      expect(orphan.mission_summary[:id]).to eq(orphan.id)
      expect(orphan.mission_details[:configuration]).to be_a(Hash)
    end

    it "still saves and reloads with a nil project_id" do
      orphan.update!(objective: "unchanged behaviour")

      expect(orphan.reload.ai_project_id).to be_nil
      expect(Ai::Mission.where(project: nil)).to include(orphan)
    end
  end
end
