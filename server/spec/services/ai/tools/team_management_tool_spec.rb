# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::TeamManagementTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("team_management")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:action, :team_id, :name, :team_type, :agent_id, :role, :input)
    end

    it "marks action as required" do
      expect(described_class.definition[:parameters][:action][:required]).to be true
    end
  end

  describe ".permitted?" do
    it "requires ai.agents.execute permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.execute")
    end
  end

  describe "#execute" do
    context "with create_team action" do
      it "creates a team for the account" do
        result = tool.execute(params: { action: "create_team", name: "Alpha Team" })
        expect(result[:success]).to be true
        expect(result[:team_id]).to be_present
        expect(result[:name]).to eq("Alpha Team")
      end

      it "defaults team_type to sequential" do
        result = tool.execute(params: { action: "create_team", name: "Beta Team" })
        team = Ai::AgentTeam.find(result[:team_id])
        expect(team.team_type).to eq("sequential")
      end

      it "accepts custom team_type" do
        result = tool.execute(params: { action: "create_team", name: "Gamma Team", team_type: "parallel" })
        team = Ai::AgentTeam.find(result[:team_id])
        expect(team.team_type).to eq("parallel")
      end

      it "returns error on invalid record" do
        result = tool.execute(params: { action: "create_team", name: nil })
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context "with add_team_member action" do
      let(:team) { create(:ai_agent_team, account: account) }
      let(:agent) { create(:ai_agent, account: account) }

      it "adds an agent as a team member" do
        result = tool.execute(params: { action: "add_team_member", team_id: team.id, agent_id: agent.id })
        expect(result[:success]).to be true
        expect(result[:member_id]).to be_present
      end

      it "defaults role to worker" do
        result = tool.execute(params: { action: "add_team_member", team_id: team.id, agent_id: agent.id })
        member = Ai::AgentTeamMember.find(result[:member_id])
        expect(member.role).to eq("worker")
      end

      it "accepts a custom role" do
        result = tool.execute(params: { action: "add_team_member", team_id: team.id, agent_id: agent.id, role: "researcher" })
        member = Ai::AgentTeamMember.find(result[:member_id])
        expect(member.role).to eq("researcher")
      end

      # REVIEW FIX (HIER-P4): extracting the member-role -> Ai::TeamRole#role_type
      # map onto Ai::AgentTeamMember.role_type_for CHANGED this verb's answer for
      # "specialist" (the deleted inline map had no branch for it, so it fell
      # through to "worker"). The intended value is pinned here, not left to the
      # extraction's side effect.
      it "backs a specialist member with a specialist TeamRole" do
        result = tool.execute(params: { action: "add_team_member", team_id: team.id,
                                        agent_id: agent.id, role: "specialist" })

        expect(result[:success]).to be true
        expect(Ai::AgentTeamMember.find(result[:member_id]).role).to eq("specialist")
        expect(team.ai_team_roles.find_by(ai_agent_id: agent.id).role_type).to eq("specialist")
      end

      it "backs an unmapped role with the worker default" do
        result = tool.execute(params: { action: "add_team_member", team_id: team.id,
                                        agent_id: agent.id, role: "floater" })

        expect(team.ai_team_roles.find_by(ai_agent_id: agent.id).role_type).to eq("worker")
      end

      it "returns error for non-existent team" do
        result = tool.execute(params: { action: "add_team_member", team_id: SecureRandom.uuid, agent_id: agent.id })
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end

      it "returns error for non-existent agent" do
        result = tool.execute(params: { action: "add_team_member", team_id: team.id, agent_id: SecureRandom.uuid })
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context "with execute_team action" do
      before do
        allow(WorkerJobService).to receive(:enqueue_ai_team_execution).and_return(true)
      end

      it "queues team execution" do
        team = create(:ai_agent_team, account: account)
        result = tool.execute(params: { action: "execute_team", team_id: team.id })
        expect(result[:success]).to be true
        expect(result[:status]).to eq("execution_dispatched")
      end

      it "returns error for non-existent team" do
        result = tool.execute(params: { action: "execute_team", team_id: SecureRandom.uuid })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(params: { action: "nuke_everything" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Unknown action/)
      end
    end

    context "parameter validation" do
      it "raises ArgumentError when action is missing" do
        expect { tool.execute(params: {}) }.to raise_error(ArgumentError, /Missing required parameters: action/)
      end
    end
  end

  # HIER-P4 — a CANONICAL team (the per-account materialisation of a global
  # Ai::TeamTemplate) is read-only through the MCP verbs, like a canonical
  # agent: list/get show it flagged, every mutating verb refuses with a result
  # envelope and points at clone-to-customise.
  describe "canonical teams" do
    let(:template) do
      create(:ai_team_template, :system_template, name: "Ops Crew", slug: "ops-crew", source_key: "ops-crew")
    end
    let!(:canonical_team) do
      create(:ai_agent_team, account: account, name: "Ops Crew", template_id: template.id,
                             team_config: { "canonical" => true, "source_key" => "ops-crew" })
    end
    let(:agent) { create(:ai_agent, account: account) }

    it "lists and shows the team flagged canonical with its template" do
      listed = tool.execute(params: { action: "list_teams" })[:teams].find { |t| t[:id] == canonical_team.id }
      expect(listed[:canonical]).to be true
      expect(listed[:template_id]).to eq(template.id)

      shown = tool.execute(params: { action: "get_team", team_id: canonical_team.id })[:team]
      expect(shown[:canonical]).to be true
      expect(shown[:source_key]).to eq("ops-crew")
    end

    it "refuses every mutating verb on a canonical team, naming the clone path" do
      [
        { action: "update_team", team_id: canonical_team.id, name: "Renamed" },
        { action: "delete_team", team_id: canonical_team.id },
        { action: "add_team_member", team_id: canonical_team.id, agent_id: agent.id },
        { action: "remove_team_member", team_id: canonical_team.id, agent_id: agent.id }
      ].each do |params|
        result = tool.execute(params: params)
        expect(result[:success]).to be(false), "#{params[:action]} should refuse"
        expect(result[:canonical]).to be true
        expect(result[:error]).to match(/canonical/i)
        expect(result[:error]).to match(/clone/i)
      end

      expect(canonical_team.reload.name).to eq("Ops Crew")
      expect(canonical_team.members.count).to eq(0)
    end

    it "leaves a team cloned from the template writable" do
      clone = template.create_team!(account: account, name: "My Ops Crew")

      result = tool.execute(params: { action: "update_team", team_id: clone.id, name: "Mine" })
      expect(result[:success]).to be true
      expect(clone.reload.name).to eq("Mine")
    end
  end
end
