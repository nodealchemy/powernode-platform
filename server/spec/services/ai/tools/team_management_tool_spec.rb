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
      it "queues team execution" do
        team = create(:ai_agent_team, account: account)
        result = tool.execute(params: { action: "execute_team", team_id: team.id })
        expect(result[:success]).to be true
        expect(result[:status]).to eq("execution_queued")
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
end
