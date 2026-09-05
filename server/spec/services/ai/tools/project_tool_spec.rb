# frozen_string_literal: true

require "rails_helper"

# APO increment `app-4-project-noun` — the read surface for the project noun.
#
# Three READ-SHAPED verbs, gated on the EXISTING `ai.missions.read` permission.
# No new permission was minted: an undefined permission degrades to admin-only,
# and a permission nothing grants and nothing checks is a defect, not a control.
# `ai.missions.read` is the right floor because a project is the container the
# missions it owns are read through — the same operator who may read a mission
# may read the project that owns it.
#
# Every example asserts on ROWS AND RETURNED DATA, never a status code.
RSpec.describe Ai::Tools::ProjectTool do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account, permissions: %w[ai.missions.read]) }
  let(:tool)    { described_class.new(account: account, user: user) }

  let!(:project) do
    create(:ai_project, account: account, name: "Ledger Service",
                        configuration: { "slo_targets" => { "cost_ceiling_usd" => 500 } })
  end

  describe "registration" do
    it "serves all three verbs from the platform registry" do
      registry = Ai::Tools::PlatformApiToolRegistry::TOOLS

      expect(registry["project_list"]).to eq("Ai::Tools::ProjectTool")
      expect(registry["project_get"]).to eq("Ai::Tools::ProjectTool")
      expect(registry["project_status"]).to eq("Ai::Tools::ProjectTool")
    end

    it "declares every verb as non-mutating" do
      %w[project_list project_get project_status].each do |action|
        expect(described_class.declared_action(action)).to include(mutating: false)
      end
    end

    it "gates on a permission the platform already defines and grants" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.missions.read")
      expect(Permissions::CORE_PERMISSIONS).to have_key("ai.missions.read")
      # Granted, not merely defined: an undefined permission degrades to
      # admin-only, and a defined one nobody holds is the same defect wearing a
      # different hat.
      expect(Permissions::ROLES["member"][:permissions]).to include("ai.missions.read")
    end
  end

  describe "project_list" do
    it "returns this account's projects with their summaries" do
      result = tool.execute(params: { action: "project_list" })

      expect(result[:success]).to be true
      names = result[:data][:projects].map { |p| p[:name] }
      expect(names).to eq([ "Ledger Service" ])
      expect(result[:data][:projects].first[:slug]).to eq("ledger-service")
      expect(result[:data][:count]).to eq(1)
    end

    it "filters by status" do
      create(:ai_project, :archived, account: account, name: "Retired")

      result = tool.execute(params: { action: "project_list", status: "archived" })

      expect(result[:data][:projects].map { |p| p[:name] }).to eq([ "Retired" ])
    end

    it "NEVER returns another account's projects" do
      other_account = create(:account)
      create(:ai_project, account: other_account, name: "Someone Elses")

      result = tool.execute(params: { action: "project_list" })

      expect(result[:data][:projects].map { |p| p[:name] }).to eq([ "Ledger Service" ])
    end
  end

  describe "project_get" do
    it "returns the project's details including its declared SLO targets" do
      result = tool.execute(params: { action: "project_get", project_id: project.id })

      expect(result[:success]).to be true
      expect(result[:data][:project][:id]).to eq(project.id)
      expect(result[:data][:project][:slo_targets]).to eq({ "cost_ceiling_usd" => 500 })
    end

    it "resolves a project by slug as well as by id" do
      result = tool.execute(params: { action: "project_get", project_id: "ledger-service" })

      expect(result[:data][:project][:id]).to eq(project.id)
    end

    it "refuses a project belonging to a DIFFERENT account" do
      foreign = create(:ai_project, account: create(:account), name: "Someone Elses")

      result = tool.execute(params: { action: "project_get", project_id: foreign.id })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
      # The row still exists — it was refused, not deleted.
      expect(Ai::Project.find_by(id: foreign.id)).to be_present
    end

    it "requires a project_id" do
      result = tool.execute(params: { action: "project_get" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/project_id/)
    end
  end

  describe "project_status" do
    let!(:mission) do
      m = create(:ai_mission, account: account, mission_type: "infrastructure",
                              created_by: user, project: project)
      m.update_columns(status: "active", current_phase: nil)
      m
    end

    it "rolls the owned missions up and reaches them from the project" do
      result = tool.execute(params: { action: "project_status", project_id: project.id })

      expect(result[:success]).to be true
      data = result[:data]
      expect(data[:project][:id]).to eq(project.id)
      expect(data[:mission_count]).to eq(1)
      expect(data[:missions_by_status]).to eq({ "active" => 1 })
      expect(data[:missions].map { |m| m[:id] }).to eq([ mission.id ])
    end

    it "reports the resolved scaling window the project's missions run under" do
      project.update!(configuration: project.configuration.merge(
        "watch_policies" => { "auto_scale_min_replicas" => 2, "auto_scale_max_replicas" => 7 }
      ))

      result = tool.execute(params: { action: "project_status", project_id: project.id })

      expect(result[:data][:scaling_bounds]).to eq({ min: 2, max: 7, auto_scale_out: true })
    end

    it "answers for a project with no missions at all" do
      empty = create(:ai_project, account: account, name: "Nothing Yet")

      result = tool.execute(params: { action: "project_status", project_id: empty.id })

      expect(result[:success]).to be true
      expect(result[:data][:mission_count]).to eq(0)
      expect(result[:data][:missions]).to eq([])
    end

    it "NEVER reads another account's project" do
      foreign = create(:ai_project, account: create(:account))

      result = tool.execute(params: { action: "project_status", project_id: foreign.id })

      expect(result[:success]).to be false
    end
  end

  describe "authorization" do
    it "refuses a caller who does not hold ai.missions.read" do
      stranger = create(:user, account: account, permissions: [])
      unprivileged = described_class.new(account: account, user: stranger)

      result = unprivileged.execute(params: { action: "project_list" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/permission/i)
    end
  end

  it "refuses an unknown action" do
    result = tool.execute(params: { action: "project_delete", project_id: project.id })

    expect(result[:success]).to be false
    expect(result[:error]).to match(/Unknown action/)
  end
end
