# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::AgentManagementTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("agent_management")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:action, :agent_id, :name, :description, :model, :input)
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
    context "with create_agent action" do
      it "creates an agent for the account" do
        result = tool.execute(params: { action: "create_agent", name: "Test Agent", description: "A test" })
        expect(result[:success]).to be true
        expect(result[:agent_id]).to be_present
        expect(result[:name]).to eq("Test Agent")
      end

      it "returns error on invalid record" do
        result = tool.execute(params: { action: "create_agent", name: nil })
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context "with list_agents action" do
      it "returns active agents for the account" do
        create(:ai_agent, account: account, status: "active")
        create(:ai_agent, account: account, status: "active")

        result = tool.execute(params: { action: "list_agents" })
        expect(result[:success]).to be true
        expect(result[:agents].size).to eq(2)
        expect(result[:agents].first).to include(:id, :name, :model, :status)
      end

      it "does not return inactive agents" do
        create(:ai_agent, account: account, status: "active")
        create(:ai_agent, :inactive, account: account)

        result = tool.execute(params: { action: "list_agents" })
        expect(result[:agents].size).to eq(1)
      end

      it "does not return agents from other accounts" do
        other_account = create(:account)
        create(:ai_agent, account: other_account, status: "active")
        create(:ai_agent, account: account, status: "active")

        result = tool.execute(params: { action: "list_agents" })
        expect(result[:agents].size).to eq(1)
      end
    end

    context "with execute_agent action" do
      it "queues agent execution" do
        agent = create(:ai_agent, account: account)
        result = tool.execute(params: { action: "execute_agent", agent_id: agent.id })
        expect(result[:success]).to be true
        expect(result[:status]).to eq("execution_queued")
      end

      it "returns error for non-existent agent" do
        result = tool.execute(params: { action: "execute_agent", agent_id: SecureRandom.uuid })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(params: { action: "destroy_everything" })
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
