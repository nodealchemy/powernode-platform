# frozen_string_literal: true

require "rails_helper"

# APO increment `app-6` — WHY a project has no team.
#
# "This project has no team" currently looks identical in three unrelated
# situations: the team was never attempted, it was attempted and the canonical
# template was not seeded on this install, or it was attempted and the write
# failed. Three states, one appearance — the same defect shape as a health
# probe that returns a constant, and the reason the app-5 best-effort path was
# correct but silent.
#
# ABSENCE IS THE LOAD-BEARING STATE. Every project that exists today has no
# record at all, and that must render as NOT ATTEMPTED rather than as anything
# healthier. A default that resolved absence to "no template" or to a bare nil
# would tell a reader something the platform does not know.
#
# The record lives in the `metadata` jsonb the project already carries — no
# migration, and nothing about this is a new shape the model did not have.
RSpec.describe "Ai::Project team-provisioning state" do
  let(:account) { create(:account) }
  let(:project) { create(:ai_project, account: account) }

  describe "#team_provisioning_state" do
    it "reports NOT ATTEMPTED for a project nothing ever tried to provision" do
      expect(project.metadata).to eq({})
      expect(project.team_provisioning_state).to eq("not_attempted")
      expect(project.team_provisioning_status[:state]).to eq("not_attempted")
      expect(project.team_provisioning_status[:attempted_at]).to be_nil
      expect(project.team_provisioning_status[:reason]).to be_present
    end

    it "reports NO TEMPLATE when the attempt found nothing to materialise" do
      project.record_team_provisioning!(state: "no_template",
                                        reason: "template \"project-operations\" is not seeded")

      status = project.reload.team_provisioning_status

      expect(status[:state]).to eq("no_template")
      expect(status[:reason]).to match(/project-operations/)
      expect(status[:attempted_at]).to be_present
      expect(status[:needs_attention]).to be true
    end

    it "reports FAILED when the attempt raised, and keeps the detail a reader can act on" do
      project.record_team_provisioning!(state: "failed",
                                        reason: "ActiveRecord::RecordInvalid: Name has already been taken")

      status = project.reload.team_provisioning_status

      expect(status[:state]).to eq("failed")
      expect(status[:reason]).to match(/RecordInvalid/)
      expect(status[:needs_attention]).to be true
    end

    it "reports PROVISIONED once a team is attached, whatever the record last said" do
      project.record_team_provisioning!(state: "failed", reason: "transient")
      project.update!(team: create(:ai_agent_team, account: account))

      status = project.reload.team_provisioning_status

      # The TEAM is the ground truth. A stale record must never outrank the row
      # it describes, or a project with a working team reads as broken forever.
      expect(status[:state]).to eq("provisioned")
      expect(status[:needs_attention]).to be false
    end

    it "reports PROVISIONED for a team an operator attached by hand, with no record at all" do
      project.update!(team: create(:ai_agent_team, account: account))

      expect(project.reload.team_provisioning_state).to eq("provisioned")
    end

    it "distinguishes all three teamless states from each other" do
      # The point of the increment: these must not collapse to one appearance.
      never = create(:ai_project, account: account, name: "Never Tried")
      absent = create(:ai_project, account: account, name: "No Template")
      broken = create(:ai_project, account: account, name: "Failed")

      absent.record_team_provisioning!(state: "no_template", reason: "not seeded")
      broken.record_team_provisioning!(state: "failed", reason: "boom")

      states = [ never, absent, broken ].map { |p| p.reload.team_provisioning_state }

      expect(states).to eq(%w[not_attempted no_template failed])
      expect(states.uniq.size).to eq(3)
    end

    it "refuses a state outside the declared vocabulary rather than recording a word nobody reads" do
      expect { project.record_team_provisioning!(state: "weird", reason: "x") }
        .to raise_error(ArgumentError, /weird/)

      expect(project.reload.team_provisioning_state).to eq("not_attempted")
    end

    it "preserves the rest of metadata when it records" do
      project.update!(metadata: { "imported_from" => "gitops" })

      project.record_team_provisioning!(state: "no_template", reason: "not seeded")

      expect(project.reload.metadata["imported_from"]).to eq("gitops")
    end

    it "tolerates a garbled metadata blob instead of raising into a status read" do
      project.update_column(:metadata, { "team_provisioning" => "not-a-hash" })

      expect(project.reload.team_provisioning_state).to eq("not_attempted")
    end
  end
end
