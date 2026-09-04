# frozen_string_literal: true

require "rails_helper"

# REVIEW FIX (HIER-P4). Ai::Tools::TeamManagementTool refuses update/delete/
# add_member/remove_member on a CANONICAL team (the account's materialisation
# of a global Ai::TeamTemplate), but the HTTP doors had no twin: DELETE
# /api/v1/ai/agent_teams/:id hard-destroyed the team plus its members, channels
# and executions. Canonical AGENTS are guarded server-side at the REST door
# (GloballyScopedContent), so canonical TEAMS must be too.
#
# Every example asserts the ROW, not only the status — a guard that renders
# from an action body does not halt the write.
RSpec.describe "Canonical team read-only guard", type: :request do
  let(:account) { create(:account) }

  let!(:team_role) do
    role = Role.create!(name: "canonical_team_manager", display_name: "Canonical Team Manager",
                        role_type: "user", description: "Can manage AI agent teams")
    %w[ai.teams.manage ai.teams.execute].each do |perm|
      role.role_permissions.find_or_create_by!(permission_name: perm)
    end
    role
  end

  let!(:user) do
    u = create(:user, :manager, account: account)
    UserRole.find_or_create_by!(user: u, role: team_role)
    u.reload
    u
  end

  let(:headers) { auth_headers_for(user) }

  let(:template) do
    create(:ai_team_template, :system_template, name: "Platform Engineering",
           slug: "platform-engineering", source_key: "platform-engineering")
  end

  # The account's materialisation, exactly as Ai::Teams::CanonicalTeamReconciler
  # writes it: template_id + the canonical flag in team_config.
  let!(:canonical_team) do
    create(:ai_agent_team, account: account, name: "Platform Engineering",
           team_type: "hierarchical", status: "active", template_id: template.id,
           team_config: { "canonical" => true, "source_key" => template.source_key,
                          "template_slug" => template.slug })
  end

  # A team merely CLONED from the same template: template_id, no flag, the
  # account's own and fully writable.
  let!(:cloned_team) do
    create(:ai_agent_team, account: account, name: "My Platform Engineering",
           team_type: "hierarchical", status: "active", template_id: template.id,
           team_config: {})
  end

  let(:agent) { create(:ai_agent, account: account) }

  describe "Api::V1::Ai::AgentTeamsController" do
    it "refuses PATCH on a canonical team and leaves the row unchanged" do
      patch "/api/v1/ai/agent_teams/#{canonical_team.id}",
            params: { name: "Hijacked" }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(canonical_team.reload.name).to eq("Platform Engineering")
    end

    it "refuses DELETE on a canonical team and leaves the row present" do
      expect {
        delete "/api/v1/ai/agent_teams/#{canonical_team.id}", headers: headers, as: :json
      }.not_to change(Ai::AgentTeam, :count)

      expect(response).to have_http_status(:forbidden)
      expect(Ai::AgentTeam.exists?(canonical_team.id)).to be true
    end

    it "refuses POST members on a canonical team" do
      expect {
        post "/api/v1/ai/agent_teams/#{canonical_team.id}/members",
             params: { agent_id: agent.id, role: "executor" }, headers: headers, as: :json
      }.not_to change(Ai::AgentTeamMember, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses DELETE members on a canonical team" do
      member = canonical_team.members.create!(agent: agent, role: "executor")

      expect {
        delete "/api/v1/ai/agent_teams/#{canonical_team.id}/members/#{member.id}",
               headers: headers, as: :json
      }.not_to change(Ai::AgentTeamMember, :count)

      expect(response).to have_http_status(:forbidden)
      expect(Ai::AgentTeamMember.exists?(member.id)).to be true
    end

    it "names the clone path in the refusal" do
      patch "/api/v1/ai/agent_teams/#{canonical_team.id}",
            params: { name: "Hijacked" }, headers: headers, as: :json

      expect(response.parsed_body["error"] || response.parsed_body["message"]).to include("clone the template")
    end

    it "still updates and destroys a team merely cloned from the template" do
      patch "/api/v1/ai/agent_teams/#{cloned_team.id}",
            params: { name: "Renamed" }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(cloned_team.reload.name).to eq("Renamed")

      delete "/api/v1/ai/agent_teams/#{cloned_team.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(Ai::AgentTeam.exists?(cloned_team.id)).to be false
    end
  end

  describe "Api::V1::Ai::TeamsController" do
    it "refuses PATCH on a canonical team and leaves the row unchanged" do
      patch "/api/v1/ai/teams/#{canonical_team.id}",
            params: { name: "Hijacked" }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(canonical_team.reload.name).to eq("Platform Engineering")
    end

    it "refuses DELETE on a canonical team and leaves the row present" do
      expect {
        delete "/api/v1/ai/teams/#{canonical_team.id}", headers: headers, as: :json
      }.not_to change(Ai::AgentTeam, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Ai::Teams::CrudService" do
    subject(:service) { Ai::Teams::CrudService.new(account: account) }

    it "raises on update_team and writes nothing" do
      expect { service.update_team(canonical_team.id, { name: "Hijacked" }) }
        .to raise_error(Ai::AgentTeam::ReadOnlyCanonical, /clone the template/)
      expect(canonical_team.reload.name).to eq("Platform Engineering")
    end

    it "raises on delete_team and writes nothing" do
      expect { service.delete_team(canonical_team.id) }
        .to raise_error(Ai::AgentTeam::ReadOnlyCanonical)
      expect(Ai::AgentTeam.exists?(canonical_team.id)).to be true
    end

    it "leaves a cloned team writable" do
      expect(service.update_team(cloned_team.id, { name: "Renamed" }).name).to eq("Renamed")
    end
  end
end
