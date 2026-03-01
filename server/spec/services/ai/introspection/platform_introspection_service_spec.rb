# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Introspection::PlatformIntrospectionService do
  let(:account) { create(:account) }
  let(:mock_redis) { instance_double(Redis) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Redis).to receive(:new).and_return(mock_redis)
    # Allow common Redis operations used by embedding/knowledge graph callbacks
    allow(mock_redis).to receive(:get).and_return(nil)
    allow(mock_redis).to receive(:set)
    allow(mock_redis).to receive(:setex)
  end

  describe "#initialize" do
    it "sets the account" do
      expect(service).to be_a(described_class)
    end
  end

  describe "#list_resources" do
    context "when cached" do
      it "returns cached result for agents" do
        cached_data = { count: 2, items: [{ id: "1", name: "Agent 1" }] }.to_json
        cache_key = "platform_introspection:#{account.id}:resources:agents"

        allow(mock_redis).to receive(:get).with(cache_key).and_return(cached_data)

        result = service.list_resources(type: "agents")

        expect(result).to eq(JSON.parse(cached_data))
      end
    end

    context "when not cached" do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_redis).to receive(:setex)
      end

      context "for agents" do
        let!(:agent) do
          provider = create(:ai_provider, account: account)
          create(:ai_agent, account: account, provider: provider)
        end

        it "returns agent list with count and items" do
          result = service.list_resources(type: "agents")

          expect(result[:count]).to eq(1)
          expect(result[:items]).to be_an(Array)
          expect(result[:items].first[:id]).to eq(agent.id)
          expect(result[:items].first[:name]).to eq(agent.name)
        end

        it "caches the result" do
          cache_key = "platform_introspection:#{account.id}:resources:agents"

          expect(mock_redis).to receive(:setex).with(
            cache_key,
            described_class::CACHE_TTL.to_i,
            anything
          )

          service.list_resources(type: "agents")
        end
      end

      context "for workflows" do
        let!(:workflow) do
          user = create(:user, account: account)
          create(:ai_workflow, account: account, creator: user)
        end

        it "returns workflow list with count and items" do
          result = service.list_resources(type: "workflows")

          expect(result[:count]).to eq(1)
          expect(result[:items]).to be_an(Array)
          expect(result[:items].first[:id]).to eq(workflow.id)
        end
      end

      context "for teams" do
        let!(:team) { create(:ai_agent_team, account: account) }

        it "returns team list with count and items" do
          result = service.list_resources(type: "teams")

          expect(result[:count]).to eq(1)
          expect(result[:items]).to be_an(Array)
          expect(result[:items].first[:id]).to eq(team.id)
        end
      end

      context "for unknown type" do
        it "returns an error hash" do
          result = service.list_resources(type: "unknown")

          expect(result[:error]).to include("Unknown resource type")
        end
      end

      it "accepts type as symbol" do
        result = service.list_resources(type: :agents)

        expect(result).to have_key(:count)
        expect(result).to have_key(:items)
      end
    end
  end

  describe "#capability_inventory" do
    context "when cached" do
      it "returns cached result" do
        cached_data = { mcp_tools: [], workflow_node_types: [], providers: [] }.to_json
        cache_key = "platform_introspection:#{account.id}:capabilities"

        allow(mock_redis).to receive(:get).with(cache_key).and_return(cached_data)

        result = service.capability_inventory

        expect(result).to eq(JSON.parse(cached_data))
      end
    end

    context "when not cached" do
      before do
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_redis).to receive(:setex)
      end

      it "returns mcp_tools, workflow_node_types, and providers" do
        allow(service).to receive(:list_mcp_tools).and_return([
          { id: "tool-1", name: "Search Tool" },
          { id: "tool-2", name: "Code Runner" }
        ])
        allow(Ai::WorkflowNode).to receive_message_chain(:distinct, :pluck).and_return(["condition", "action", "trigger"])
        allow(Ai::Provider).to receive(:pluck).with(:name, :provider_type).and_return([["OpenAI", "llm"]])

        result = service.capability_inventory

        expect(result[:mcp_tools]).to be_an(Array)
        expect(result[:mcp_tools].length).to eq(2)
        expect(result[:mcp_tools].first[:name]).to eq("Search Tool")
        expect(result[:workflow_node_types]).to eq(["condition", "action", "trigger"])
        expect(result[:providers]).to eq([["OpenAI", "llm"]])
      end

      it "handles MCP registry errors gracefully" do
        allow(Mcp::RegistryService).to receive(:new).and_raise(StandardError, "Registry unavailable")
        allow(Ai::WorkflowNode).to receive_message_chain(:distinct, :pluck).and_return([])
        allow(Ai::Provider).to receive(:pluck).and_return([])

        result = service.capability_inventory

        expect(result[:mcp_tools]).to eq([])
      end

      it "caches the result" do
        cache_key = "platform_introspection:#{account.id}:capabilities"
        allow(Mcp::RegistryService).to receive(:new).and_raise(StandardError)
        allow(Ai::WorkflowNode).to receive_message_chain(:distinct, :pluck).and_return([])
        allow(Ai::Provider).to receive(:pluck).and_return([])

        expect(mock_redis).to receive(:setex).with(
          cache_key,
          described_class::CACHE_TTL.to_i,
          anything
        )

        service.capability_inventory
      end
    end
  end

  describe "#dependency_map" do
    before do
      allow(mock_redis).to receive(:get).and_return(nil)
      allow(mock_redis).to receive(:setex)
    end

    it "returns model associations for core models" do
      result = service.dependency_map

      expect(result[:models]).to have_key("Ai::Agent")
      expect(result[:models]).to have_key("Ai::Workflow")
      expect(result[:models]).to have_key("Ai::AgentTeam")
      expect(result[:models]).to have_key("Devops::Pipeline")
    end

    it "includes association details" do
      result = service.dependency_map

      agent_associations = result[:models]["Ai::Agent"]
      expect(agent_associations).to be_an(Array)
      expect(agent_associations.first).to have_key(:name)
      expect(agent_associations.first).to have_key(:type)
    end

    it "caches the result" do
      cache_key = "platform_introspection:#{account.id}:dependencies"

      expect(mock_redis).to receive(:setex).with(
        cache_key,
        described_class::CACHE_TTL.to_i,
        anything
      )

      service.dependency_map
    end

    context "when cached" do
      it "returns cached result" do
        cached_data = { models: {} }.to_json
        allow(mock_redis).to receive(:get).and_return(cached_data)

        result = service.dependency_map

        expect(result).to eq(JSON.parse(cached_data))
      end
    end
  end

  describe "#get_resource_config" do
    context "for agent" do
      let(:provider) { create(:ai_provider, account: account) }
      let!(:agent) { create(:ai_agent, account: account, provider: provider) }

      it "returns agent configuration" do
        result = service.get_resource_config(type: "agent", id: agent.id)

        expect(result[:id]).to eq(agent.id)
        expect(result[:name]).to eq(agent.name)
        expect(result[:status]).to eq(agent.status)
        expect(result).to have_key(:created_at)
      end

      it "returns nil for non-existent agent" do
        result = service.get_resource_config(type: "agent", id: SecureRandom.uuid)

        expect(result).to be_nil
      end

      it "scopes to account" do
        other_account = create(:account)
        other_provider = create(:ai_provider, account: other_account)
        other_agent = create(:ai_agent, account: other_account, provider: other_provider)

        result = service.get_resource_config(type: "agent", id: other_agent.id)

        expect(result).to be_nil
      end
    end

    context "for unknown type" do
      it "returns nil" do
        result = service.get_resource_config(type: "unknown", id: SecureRandom.uuid)

        expect(result).to be_nil
      end
    end
  end

  describe "CACHE_TTL" do
    it "is set to 5 minutes" do
      expect(described_class::CACHE_TTL).to eq(5.minutes)
    end
  end
end
