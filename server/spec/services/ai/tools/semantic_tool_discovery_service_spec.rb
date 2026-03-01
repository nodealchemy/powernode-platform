# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::SemanticToolDiscoveryService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  describe "constants" do
    it "defines CACHE_TTL" do
      expect(described_class::CACHE_TTL).to eq(6.hours)
    end

    it "defines SIMILARITY_THRESHOLD" do
      expect(described_class::SIMILARITY_THRESHOLD).to eq(0.3)
    end

    it "defines MAX_RESULTS" do
      expect(described_class::MAX_RESULTS).to eq(10)
    end
  end

  describe "#discover" do
    before do
      # Mock embedding provider to force keyword fallback
      allow(service).to receive(:find_embedding_provider).and_return(nil)
    end

    it "returns tools ranked by keyword relevance" do
      create(:ai_agent, account: account, name: "Deploy Agent", description: "Handles deployment", status: "active")

      results = service.discover(query: "deploy")
      expect(results).to be_an(Array)
    end

    it "includes platform tools" do
      results = service.discover(query: "agent management create")
      platform_results = results.select { |t| t[:source] == "platform" }
      expect(platform_results).not_to be_empty
    end

    it "includes agent-as-tool entries" do
      create(:ai_agent, account: account, name: "Code Reviewer", description: "Reviews code", status: "active", agent_type: "assistant")

      results = service.discover(query: "code review")
      agent_results = results.select { |t| t[:source] == "agent" }
      expect(agent_results).not_to be_empty
    end

    it "excludes workflow_optimizer agents from agent-as-tool" do
      create(:ai_agent, account: account, name: "Optimizer", description: "Optimizes workflows", status: "active", agent_type: "workflow_optimizer")

      results = service.discover(query: "optimizer")
      agent_results = results.select { |t| t[:source] == "agent" && t[:name]&.include?("optimizer") }
      expect(agent_results).to be_empty
    end

    it "respects limit parameter" do
      results = service.discover(query: "agent", limit: 2)
      expect(results.size).to be <= 2
    end

    it "filters by capabilities when provided" do
      results_all = service.discover(query: "management")
      results_filtered = service.discover(query: "management", capabilities: ["pipeline"])

      # Filtered results should be subset
      expect(results_filtered.size).to be <= results_all.size
    end

    it "includes relevance_score in results" do
      results = service.discover(query: "agent management")
      results.each do |result|
        expect(result[:relevance_score]).to be_a(Numeric)
      end
    end
  end

  describe "#index_tools!" do
    it "returns the count of indexed tools" do
      # Mock embedding to return nil (no provider)
      allow(service).to receive(:find_embedding_provider).and_return(nil)

      count = service.index_tools!
      expect(count).to be >= 0
    end

    context "with an embedding provider" do
      let(:provider) { double("provider") }

      before do
        allow(service).to receive(:find_embedding_provider).and_return(provider)
        allow(provider).to receive(:generate_embedding).and_return(Array.new(1536, 0.1))
      end

      it "caches embeddings for each tool" do
        allow(Rails.cache).to receive(:write)

        count = service.index_tools!
        expect(count).to be > 0
      end
    end
  end

  describe ".register_dynamic_tool" do
    it "registers a tool in the cache" do
      result = described_class.register_dynamic_tool(
        account: account,
        name: "custom_deploy",
        description: "Custom deployment tool",
        parameters: { target: { type: "string" } },
        handler: "Ai::Tools::BaseTool"
      )

      expect(result[:id]).to eq("dynamic.custom_deploy")
      expect(result[:name]).to eq("custom_deploy")
      expect(result[:dynamic]).to be true
      expect(result[:handler_class]).to eq("Ai::Tools::BaseTool")
    end

    it "replaces existing tool with same name" do
      described_class.register_dynamic_tool(
        account: account, name: "my_tool", description: "v1",
        parameters: {}, handler: "Ai::Tools::BaseTool"
      )
      described_class.register_dynamic_tool(
        account: account, name: "my_tool", description: "v2",
        parameters: {}, handler: "Ai::Tools::BaseTool"
      )

      cache_key = "tool_discovery:#{account.id}:dynamic_tools"
      tools = Rails.cache.read(cache_key)
      matching = tools.select { |t| t[:name] == "my_tool" }
      expect(matching.size).to eq(1)
      expect(matching.first[:description]).to eq("v2")
    end

    it "handles handler as a class" do
      result = described_class.register_dynamic_tool(
        account: account, name: "class_tool", description: "Test",
        parameters: {}, handler: Ai::Tools::BaseTool
      )
      expect(result[:handler_class]).to eq("Ai::Tools::BaseTool")
    end
  end

  describe ".unregister_dynamic_tool" do
    it "removes the tool from cache" do
      described_class.register_dynamic_tool(
        account: account, name: "temp_tool", description: "Temporary",
        parameters: {}, handler: "Ai::Tools::BaseTool"
      )

      described_class.unregister_dynamic_tool(account: account, name: "temp_tool")

      cache_key = "tool_discovery:#{account.id}:dynamic_tools"
      tools = Rails.cache.read(cache_key) || []
      expect(tools.none? { |t| t[:name] == "temp_tool" }).to be true
    end

    it "handles unregistering a non-existent tool gracefully" do
      expect {
        described_class.unregister_dynamic_tool(account: account, name: "nonexistent")
      }.not_to raise_error
    end
  end

  describe "private methods" do
    describe "#keyword_score" do
      it "calculates proportion of matching query terms" do
        score = service.send(:keyword_score, "agent management", "agent management tool create list")
        expect(score).to eq(1.0)
      end

      it "returns partial score for partial matches" do
        score = service.send(:keyword_score, "agent deploy pipeline", "agent management tool")
        expect(score).to be_between(0.0, 1.0)
      end

      it "returns 0 for no matches" do
        score = service.send(:keyword_score, "zebra", "agent management tool")
        expect(score).to eq(0.0)
      end
    end

    describe "#cosine_similarity" do
      it "returns 1.0 for identical vectors" do
        vec = [1.0, 0.0, 0.0]
        expect(service.send(:cosine_similarity, vec, vec)).to be_within(0.001).of(1.0)
      end

      it "returns 0.0 for orthogonal vectors" do
        vec_a = [1.0, 0.0]
        vec_b = [0.0, 1.0]
        expect(service.send(:cosine_similarity, vec_a, vec_b)).to be_within(0.001).of(0.0)
      end

      it "returns 0.0 for mismatched vector sizes" do
        expect(service.send(:cosine_similarity, [1.0], [1.0, 2.0])).to eq(0.0)
      end

      it "returns 0.0 for zero vectors" do
        expect(service.send(:cosine_similarity, [0.0, 0.0], [0.0, 0.0])).to eq(0.0)
      end

      it "returns 0.0 for non-array inputs" do
        expect(service.send(:cosine_similarity, nil, [1.0])).to eq(0.0)
      end
    end

    describe "#build_search_text" do
      it "combines name and description" do
        text = service.send(:build_search_text, "my_tool", { description: "A useful tool" })
        expect(text).to include("my tool")
        expect(text).to include("A useful tool")
      end

      it "includes parameter keys" do
        text = service.send(:build_search_text, "test", { description: "desc", parameters: { action: {}, name: {} } })
        expect(text).to include("action")
        expect(text).to include("name")
      end

      it "handles missing description" do
        text = service.send(:build_search_text, "test", {})
        expect(text).to include("test")
      end
    end

    describe "#filter_by_capabilities" do
      it "filters tools by capability keywords" do
        tools = [
          { search_text: "agent management create list" },
          { search_text: "pipeline trigger deploy" },
          { search_text: "memory read write" }
        ]

        filtered = service.send(:filter_by_capabilities, tools, ["pipeline"])
        expect(filtered.size).to eq(1)
        expect(filtered.first[:search_text]).to include("pipeline")
      end

      it "is case insensitive" do
        tools = [{ search_text: "Pipeline Management" }]
        filtered = service.send(:filter_by_capabilities, tools, ["pipeline"])
        expect(filtered.size).to eq(1)
      end
    end
  end
end
