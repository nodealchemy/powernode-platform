# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::AgentMemoryManagementTool do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:tool) { described_class.new(account: account, agent: agent, internal: true) }

  # No embedding, so recall ranks by the deterministic keyword path.
  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
  end

  def team_pool(access_control:, key:, value:)
    create(:ai_memory_pool, account: account, pool_type: "team_shared",
           access_control: access_control,
           data: { key => { "value" => value, "importance" => 0.5, "access_count" => 0 } })
  end

  def recall(**params)
    tool.execute(params: { action: "agent_recall" }.merge(params).with_indifferent_access)
  end

  # agent_recall stays declared read-only: the writes below are usage telemetry
  # (AgentManagedMemoryService#search_pool_entries), so the contract names them.
  describe ".action_definitions agent_recall" do
    it "is declared read-only and names every field a recall writes" do
      description = described_class.action_definitions["agent_recall"][:description]

      expect(described_class.declared_action("agent_recall")[:mutating]).to be(false)
      expect(description).to include("access_count", "last_accessed_at", "version",
                                     "data_size_bytes", "updated_at", "memory_pool_update")
    end
  end

  describe "#execute action: agent_recall with include_team: true" do
    # The team-pool query compared access_control->>'agents' (TEXT) with `@>`.
    # Postgres has no text @> operator, so the query raised, the tool rescued
    # it, and every include_team: true call returned an error.
    let!(:listed_pool) do
      team_pool(access_control: { "agents" => [ agent.id ], "public" => false },
                key: "deploy.window", value: "Deploy window is Tuesday")
    end
    let!(:public_pool) do
      team_pool(access_control: { "agents" => [], "public" => true },
                key: "deploy.freeze", value: "Deploy freeze on Friday")
    end
    let!(:other_agents_pool) do
      team_pool(access_control: { "agents" => [ SecureRandom.uuid ], "public" => false },
                key: "deploy.secret", value: "Deploy notes for another agent")
    end

    it "returns hits from team pools that list the agent or are public, and none from others" do
      result = recall(query: "deploy", include_team: true)

      expect(result[:success]).to be true
      keys = result[:data][:results].map { |r| r[:key] }
      expect(keys).to contain_exactly("deploy.window", "deploy.freeze")
    end

    it "leaves team pools out when include_team is not set" do
      result = recall(query: "deploy")

      expect(result[:success]).to be true
      expect(result[:data][:count]).to eq(0)
    end
  end
end
