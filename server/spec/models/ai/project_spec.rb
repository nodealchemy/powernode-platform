# frozen_string_literal: true

require "rails_helper"

# APO increment `app-4-project-noun`.
#
# Before this model there was no noun for "project": a project WAS an
# infrastructure `Ai::Mission`, so the thing that outlives its work had the
# lifecycle of the work. Missions end; projects do not. Nothing bound a
# template + repository + owning team + budget/bounds + SLO targets together,
# and the per-project scaling window had to be declared on every mission
# separately.
#
# CORE PURITY: the node template a project is composed from is owned by an
# extension. This model must never name that class — the association is
# POLYMORPHIC, and these examples prove the seam by pointing it at an
# arbitrary CORE record. If the seam only worked for one extension class it
# would not be a seam.
RSpec.describe Ai::Project do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  describe "shape" do
    it "persists with a UUIDv7 primary key and a slug derived from the name" do
      project = described_class.create!(account: account, name: "Ledger Service")

      expect(project.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7/)
      expect(project.slug).to eq("ledger-service")
      expect(project.status).to eq("active")
      expect(project.configuration).to eq({})
      expect(project.metadata).to eq({})
    end

    it "refuses a duplicate slug inside one account and allows it across accounts" do
      create(:ai_project, account: account, name: "Ledger Service")
      dup = described_class.new(account: account, name: "ledger service")
      other = described_class.new(account: create(:account), name: "Ledger Service")

      expect(dup).not_to be_valid
      expect(dup.errors[:slug]).to be_present
      expect(other).to be_valid
    end

    it "refuses a status outside the declared vocabulary" do
      project = build(:ai_project, account: account, status: "completed")

      expect(project).not_to be_valid
      expect(described_class::STATUSES).to contain_exactly("active", "paused", "archived")
    end
  end

  describe "associations" do
    it "owns its missions and reaches the mission-keyed metric time series" do
      project = create(:ai_project, account: account)
      mission = create(:ai_mission, account: account, mission_type: "infrastructure",
                                  created_by: user, project: project)

      expect(project.reload.missions).to contain_exactly(mission)
      # The extension's per-project metric time series is keyed by mission_id
      # (it `belongs_to :mission`), so owning the mission ids IS reachability:
      # this is the exact key set a metrics reader scopes on.
      expect(project.mission_ids).to eq([ mission.id ])
    end

    it "nullifies a mission's project rather than destroying the mission" do
      project = create(:ai_project, account: account)
      mission = create(:ai_mission, account: account, mission_type: "infrastructure",
                                  created_by: user, project: project)

      project.destroy!

      expect(Ai::Mission.find_by(id: mission.id)).to be_present
      expect(mission.reload.ai_project_id).to be_nil
    end

    it "holds the template GENERICALLY so core never names the extension class" do
      # Any record can be the template through this seam. A core record is used
      # deliberately: it proves the column pair carries an arbitrary type, which
      # is what lets the extension's node template sit here without core knowing
      # its name.
      stand_in = create(:ai_mission_template)
      project = create(:ai_project, account: account, template: stand_in)

      expect(project.reload.template_type).to eq("Ai::MissionTemplate")
      expect(project.template_id).to eq(stand_in.id)
      expect(project.template_ref).to eq({ type: "Ai::MissionTemplate", id: stand_in.id })
    end

    it "reports no template reference when none is attached" do
      expect(create(:ai_project, account: account).template_ref).to be_nil
    end

    it "binds a repository and an owning team" do
      repo = create(:git_repository, account: account)
      team = create(:ai_agent_team, account: account)
      project = create(:ai_project, account: account, repository: repo, team: team)

      expect(project.reload.repository).to eq(repo)
      expect(project.team).to eq(team)
    end
  end

  describe "declarations read by the bounds ladder" do
    it "exposes watch_policies and slo_targets in the SAME shape a mission declares" do
      project = create(:ai_project, account: account, configuration: {
        "watch_policies" => { "auto_scale_min_replicas" => 3 },
        "slo_targets" => { "max_cpu_pct" => 70, "cost_ceiling_usd" => 500 }
      })

      expect(project.watch_policies_hash).to eq({ "auto_scale_min_replicas" => 3 })
      expect(project.slo_targets_hash).to eq({ "max_cpu_pct" => 70, "cost_ceiling_usd" => 500 })
    end

    it "answers empty hashes for a project that declared nothing" do
      project = create(:ai_project, account: account)

      expect(project.watch_policies_hash).to eq({})
      expect(project.slo_targets_hash).to eq({})
    end

    it "tolerates a garbled configuration instead of raising into the ladder" do
      project = create(:ai_project, account: account)
      project.update_column(:configuration, { "watch_policies" => "not-a-hash" })

      expect(project.reload.watch_policies_hash).to eq({})
    end
  end

  describe "#status_rollup" do
    it "counts missions by status and names the ones still in progress" do
      project = create(:ai_project, account: account)
      active = create(:ai_mission, account: account, mission_type: "infrastructure",
                                 created_by: user, project: project)
      active.update_columns(status: "active")
      done = create(:ai_mission, account: account, mission_type: "infrastructure",
                               created_by: user, project: project)
      done.update_columns(status: "completed")

      rollup = project.reload.status_rollup

      expect(rollup[:mission_count]).to eq(2)
      expect(rollup[:missions_by_status]).to eq({ "active" => 1, "completed" => 1 })
      expect(rollup[:in_progress_mission_ids]).to eq([ active.id ])
    end
  end
end
