# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::MemoryTool do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:tool) { described_class.new(account: account, agent: agent) }
  let(:pool) { create(:ai_memory_pool, account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("memory_management")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:action, :pool_id, :key)
    end

    it "marks action as required" do
      params = described_class.definition[:parameters]
      expect(params[:action][:required]).to be true
      # pool_id and key are optional in the base definition but
      # required per-action (see action_definitions)
      expect(params[:pool_id][:required]).to be false
      expect(params[:key][:required]).to be false
    end
  end

  describe ".permitted?" do
    it "requires ai.agents.read permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.read")
    end
  end

  describe "#execute" do
    context "with read_shared_memory action" do
      it "reads data from the memory pool" do
        allow_any_instance_of(Ai::MemoryPool).to receive(:read_data).with("test.key", agent_id: agent.id).and_return("value")

        result = tool.execute(params: { action: "read_shared_memory", pool_id: pool.pool_id, key: "test.key" })
        expect(result[:success]).to be true
        expect(result[:key]).to eq("test.key")
        expect(result[:value]).to eq("value")
      end
    end

    context "with write_shared_memory action" do
      it "writes data to the memory pool" do
        allow_any_instance_of(Ai::MemoryPool).to receive(:write_data).with("test.key", "new_value", agent_id: agent.id)

        result = tool.execute(params: { action: "write_shared_memory", pool_id: pool.pool_id, key: "test.key", value: "new_value" })
        expect(result[:success]).to be true
        expect(result[:key]).to eq("test.key")
        expect(result[:written]).to be true
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(params: { action: "delete_memory", pool_id: pool.pool_id, key: "test" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Unknown action/)
      end
    end

    context "when pool is not found" do
      it "returns error" do
        result = tool.execute(params: { action: "read_shared_memory", pool_id: "nonexistent", key: "test" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end
    end

    context "parameter validation" do
      it "raises ArgumentError when required params are missing" do
        # action is the only required param in the base definition
        expect { tool.execute(params: {}) }.to raise_error(ArgumentError, /Missing required parameters/)
      end
    end
  end
end
