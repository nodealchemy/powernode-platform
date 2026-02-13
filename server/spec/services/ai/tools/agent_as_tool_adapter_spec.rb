# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::AgentAsToolAdapter do
  let(:account) { create(:account) }
  let(:calling_agent) { create(:ai_agent, account: account) }
  let(:target_agent) { create(:ai_agent, account: account, status: "active") }

  describe ".definition" do
    it "returns generic invoke_agent definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("invoke_agent")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:agent_id, :prompt, :context)
    end

    it "marks agent_id and prompt as required" do
      params = described_class.definition[:parameters]
      expect(params[:agent_id][:required]).to be true
      expect(params[:prompt][:required]).to be true
    end
  end

  describe ".definition_for" do
    it "returns a definition customized for the target agent" do
      defn = described_class.definition_for(target_agent)
      expect(defn[:name]).to eq("invoke_agent_#{target_agent.name.parameterize(separator: '_')}")
      expect(defn[:description]).to include(target_agent.name)
      expect(defn[:parameters]).to include(:prompt, :context)
    end
  end

  describe ".permitted?" do
    it "requires ai.agents.execute permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.execute")
    end
  end

  describe "#initialize" do
    it "accepts account, agent, and target_agent" do
      adapter = described_class.new(account: account, agent: calling_agent, target_agent: target_agent)
      expect(adapter).to be_a(described_class)
    end
  end

  describe "#execute" do
    let(:adapter) { described_class.new(account: account, agent: calling_agent, target_agent: target_agent) }

    context "with valid target agent" do
      it "creates an execution and returns success" do
        result = adapter.execute(params: { prompt: "Analyze this code" })
        expect(result[:success]).to be true
        expect(result[:execution_id]).to be_present
        expect(result[:agent_name]).to eq(target_agent.name)
        expect(result[:status]).to eq("queued")
        expect(result[:message]).to include(target_agent.name)
      end

      it "creates an AgentExecution record" do
        expect {
          adapter.execute(params: { prompt: "Test prompt" })
        }.to change(Ai::AgentExecution, :count).by(1)
      end

      it "stores invocation metadata in the execution" do
        adapter.execute(params: { prompt: "Run analysis", context: { file: "test.rb" } })
        execution = Ai::AgentExecution.last
        expect(execution.input_data["prompt"]).to eq("Run analysis")
        expect(execution.input_data["context"]).to eq({ "file" => "test.rb" })
        expect(execution.input_data["invocation_type"]).to eq("agent_as_tool")
        expect(execution.metadata["source"]).to eq("agent_as_tool")
        expect(execution.metadata["calling_agent_id"]).to eq(calling_agent.id)
      end
    end

    context "with inactive target agent" do
      let(:inactive_agent) { create(:ai_agent, :inactive, account: account) }
      let(:adapter) { described_class.new(account: account, agent: calling_agent, target_agent: inactive_agent) }

      it "returns error" do
        result = adapter.execute(params: { prompt: "Test" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not active/)
      end
    end

    context "with target agent from different account" do
      let(:other_account) { create(:account) }
      let(:other_agent) { create(:ai_agent, account: other_account) }
      let(:adapter) { described_class.new(account: account, agent: calling_agent, target_agent: other_agent) }

      it "returns error" do
        result = adapter.execute(params: { prompt: "Test" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/does not belong/)
      end
    end

    context "without calling agent" do
      let(:adapter) { described_class.new(account: account, target_agent: target_agent) }

      it "still creates execution with nil agent references" do
        result = adapter.execute(params: { prompt: "Test" })
        expect(result[:success]).to be true
        execution = Ai::AgentExecution.last
        expect(execution.input_data["invoked_by"]).to eq("tool_adapter")
      end
    end
  end
end
