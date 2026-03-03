# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Conversation, type: :model do
  describe '#parse_mention_segments' do
    let(:account) { create(:account) }
    let(:provider) { create(:ai_provider, account: account, is_active: true) }
    let(:user) { create(:user, account: account) }
    let(:workspace_team) { create(:ai_agent_team, :workspace, account: account) }
    let(:concierge) { create(:ai_agent, account: account, provider: provider, name: "Powernode Assistant", is_concierge: true) }
    let(:cc2) { create(:ai_agent, :mcp_client, account: account, provider: provider, name: "Claude Code (powernode) #2") }
    let(:cc3) { create(:ai_agent, :mcp_client, account: account, provider: provider, name: "Claude Code (powernode) #3") }
    let(:conversation) do
      create(:ai_conversation, account: account, user: user, agent: concierge,
             agent_team: workspace_team, conversation_type: "team")
    end

    before do
      create(:ai_agent_team_member, team: workspace_team, agent: concierge, role: "facilitator")
      create(:ai_agent_team_member, team: workspace_team, agent: cc2, role: "executor")
      create(:ai_agent_team_member, team: workspace_team, agent: cc3, role: "executor")
    end

    it "parses preamble + two agent segments" do
      content = "Respond to all agent responses, @Claude Code (powernode) #2 Ask for an introduction from the Powernode Assistant @Claude Code (powernode) #3 Tell the Powernode Assistant you are ready for instructions."
      result = conversation.parse_mention_segments(content)

      expect(result["preamble"]).to eq("Respond to all agent responses,")
      expect(result["segments"][cc2.id]).to eq("Ask for an introduction from the Powernode Assistant")
      expect(result["segments"][cc3.id]).to eq("Tell the Powernode Assistant you are ready for instructions.")
    end

    it "handles message starting with @mention (empty preamble)" do
      content = "@Claude Code (powernode) #2 do something @Claude Code (powernode) #3 do something else"
      result = conversation.parse_mention_segments(content)

      expect(result["preamble"]).to eq("")
      expect(result["segments"][cc2.id]).to eq("do something")
      expect(result["segments"][cc3.id]).to eq("do something else")
    end

    it "handles single mention with trailing text" do
      content = "Hey team, @Claude Code (powernode) #2 please check the latest deployment logs"
      result = conversation.parse_mention_segments(content)

      expect(result["preamble"]).to eq("Hey team,")
      expect(result["segments"][cc2.id]).to eq("please check the latest deployment logs")
      expect(result["segments"].keys).not_to include(cc3.id)
    end

    it "concatenates when same agent is mentioned twice" do
      content = "@Claude Code (powernode) #2 first task @Claude Code (powernode) #3 your task @Claude Code (powernode) #2 also do this"
      result = conversation.parse_mention_segments(content)

      expect(result["segments"][cc2.id]).to eq("first task also do this")
      expect(result["segments"][cc3.id]).to eq("your task")
    end

    it "prefers longest match to prevent partial name collisions" do
      short_agent = create(:ai_agent, :mcp_client, account: account, provider: provider, name: "Claude Code")
      create(:ai_agent_team_member, team: workspace_team, agent: short_agent, role: "executor")

      content = "@Claude Code (powernode) #2 specific task @Claude Code general task"
      result = conversation.parse_mention_segments(content)

      expect(result["segments"][cc2.id]).to eq("specific task")
      expect(result["segments"][short_agent.id]).to eq("general task")
    end

    it "handles mention at end of message with no trailing text" do
      content = "Check this out @Claude Code (powernode) #2"
      result = conversation.parse_mention_segments(content)

      expect(result["preamble"]).to eq("Check this out")
      expect(result["segments"][cc2.id]).to eq("")
    end

    it "returns nil when no @mentions found" do
      result = conversation.parse_mention_segments("Hello everyone, please check the logs")
      expect(result).to be_nil
    end

    it "returns nil for non-workspace conversations" do
      regular_conv = create(:ai_conversation, account: account, user: user, agent: concierge)
      result = regular_conv.parse_mention_segments("@Claude Code (powernode) #2 test")
      expect(result).to be_nil
    end

    it "returns nil for empty content" do
      expect(conversation.parse_mention_segments("")).to be_nil
      expect(conversation.parse_mention_segments(nil)).to be_nil
    end

    it "ignores @mentions of agents not in the workspace team" do
      content = "@Claude Code (powernode) #2 your task @NonExistent Agent ignored text"
      result = conversation.parse_mention_segments(content)

      expect(result["segments"][cc2.id]).to eq("your task @NonExistent Agent ignored text")
      expect(result["segments"].keys).to contain_exactly(cc2.id)
    end
  end

  describe '#cleanup_orphaned_workspace_team' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:provider) { create(:ai_provider, account: account) }
    let(:agent) { create(:ai_agent, account: account, provider: provider) }

    context 'when conversation belongs to a workspace team' do
      let(:workspace_team) do
        create(:ai_agent_team, account: account, team_type: 'workspace', coordination_strategy: 'round_robin')
      end

      let!(:conversation) do
        create(:ai_conversation,
               account: account,
               user: user,
               agent: agent,
               provider: provider,
               agent_team: workspace_team,
               conversation_type: 'team')
      end

      it 'destroys the workspace team when the last conversation is deleted' do
        expect { conversation.destroy! }.to change { Ai::AgentTeam.count }.by(-1)
        expect(Ai::AgentTeam.find_by(id: workspace_team.id)).to be_nil
      end

      it 'does not destroy the workspace team when other conversations remain' do
        create(:ai_conversation,
               account: account,
               user: user,
               agent: agent,
               provider: provider,
               agent_team: workspace_team,
               conversation_type: 'team')

        expect { conversation.destroy! }.not_to change { Ai::AgentTeam.count }
      end
    end

    context 'when conversation belongs to a non-workspace team' do
      let(:team) do
        create(:ai_agent_team, account: account, team_type: 'hierarchical', coordination_strategy: 'manager_led')
      end

      let!(:conversation) do
        create(:ai_conversation,
               account: account,
               user: user,
               agent: agent,
               provider: provider,
               agent_team: team,
               conversation_type: 'team')
      end

      it 'does not destroy the team' do
        expect { conversation.destroy! }.not_to change { Ai::AgentTeam.count }
      end
    end

    context 'when conversation has no team' do
      let!(:conversation) do
        create(:ai_conversation,
               account: account,
               user: user,
               agent: agent,
               provider: provider)
      end

      it 'does not raise an error' do
        expect { conversation.destroy! }.not_to raise_error
      end
    end
  end
end
