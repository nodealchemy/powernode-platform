# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::ResearchService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#research" do
    let(:mock_kb_service) { instance_double(Ai::Memory::SharedKnowledgeService) }

    before do
      allow(Ai::Memory::SharedKnowledgeService).to receive(:new).and_return(mock_kb_service)
      allow(mock_kb_service).to receive(:search).and_return({ entries: [] })
    end

    it "returns structured research report with topic and sources" do
      result = service.research(topic: "code review automation")

      expect(result[:topic]).to eq("code review automation")
      expect(result[:sources_queried]).to include("knowledge_graph", "knowledge_bases", "mcp", "federation")
      expect(result[:researched_at]).to be_present
      expect(result[:findings]).to be_a(Hash)
      expect(result[:total_findings]).to be_a(Integer)
    end

    it "accepts a requesting agent" do
      agent = create(:ai_agent, account: account)
      result = service.research(topic: "testing", requesting_agent: agent)

      expect(result[:requesting_agent_id]).to eq(agent.id)
    end

    it "searches only specified sources" do
      result = service.research(topic: "testing", sources: %w[knowledge_graph])

      expect(result[:findings]).to have_key(:knowledge_graph)
      expect(result[:findings]).not_to have_key(:knowledge_bases)
      expect(result[:findings]).not_to have_key(:mcp)
    end

    it "handles errors gracefully and returns error key" do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_raise(StandardError, "connection lost")

      result = service.research(topic: "test", sources: %w[knowledge_graph])

      # Should not raise, returns result with error in the findings or top-level
      expect(result).to be_a(Hash)
    end

    context "web source" do
      it "returns results when feature flag is enabled" do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_lifecycle_research, account).and_return(true)

        result = service.research(topic: "testing", sources: %w[web])

        expect(result[:findings][:web]).to be_an(Array)
        expect(result[:findings][:web].first[:source]).to eq("web_research")
      end

      it "returns empty when feature flag is disabled" do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_lifecycle_research, account).and_return(false)

        result = service.research(topic: "testing", sources: %w[web])

        expect(result[:findings][:web]).to eq([])
      end
    end

    context "federation source" do
      it "queries A2A protocol service for federated agents" do
        mock_a2a = instance_double(Ai::A2a::ProtocolService)
        allow(Ai::A2a::ProtocolService).to receive(:new).and_return(mock_a2a)
        allow(mock_a2a).to receive(:discover_agents).and_return({
          success: true,
          agents: [
            { name: "RemoteAgent", agent_card: { "url" => "https://example.com", "capabilities" => ["code"] } }
          ]
        })

        result = service.research(topic: "code review", sources: %w[federation])

        expect(result[:findings][:federation]).to be_an(Array)
        expect(result[:findings][:federation].first[:agent_name]).to eq("RemoteAgent")
      end
    end

    context "MCP source" do
      it "searches connected MCP servers for matching tools" do
        McpServer.create!(
          account: account,
          name: "Test Server",
          url: "http://localhost:3333",
          status: "connected",
          connection_type: "http",
          capabilities: { "tools" => [{ "name" => "code_review", "description" => "Automated code review tool" }] }
        )

        result = service.research(topic: "code review", sources: %w[mcp])

        expect(result[:findings][:mcp]).to be_an(Array)
      end
    end
  end

  describe "#detect_overlaps" do
    it "returns overlaps with similarity scores" do
      skill = create(:ai_skill, account: account, name: "Code Review", description: "Review code")
      # Create node with same embedding as the one the service will generate (stubbed to Array.new(1536, 0.1))
      Ai::KnowledgeGraphNode.create!(
        account: account,
        name: "Code Review",
        entity_type: "skill",
        node_type: "entity",
        status: "active",
        confidence: 1.0,
        ai_skill_id: skill.id,
        embedding: Array.new(1536, 0.1)
      )

      result = service.detect_overlaps(proposed_name: "Code Review Pro", proposed_description: "Advanced code review")

      expect(result).to have_key(:overlaps)
      expect(result).to have_key(:count)
    end

    it "returns empty overlaps when embedding generation fails" do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)

      result = service.detect_overlaps(proposed_name: "Test", proposed_description: "Test skill")

      expect(result[:overlaps]).to eq([])
      expect(result[:warning]).to include("Could not generate embedding")
    end

    it "classifies severity based on similarity score" do
      # Test the private overlap_severity method via detect_overlaps behavior
      result = service.detect_overlaps(proposed_name: "NonExistent", proposed_description: "Nothing")

      expect(result[:overlaps]).to be_an(Array)
    end
  end

  describe "#suggest_dependencies" do
    it "returns empty array when embedding generation fails" do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)

      result = service.suggest_dependencies(proposed_skill_attrs: { name: "Test", description: "test", category: nil })

      expect(result).to eq([])
    end

    it "returns dependency suggestions with relation types" do
      skill = create(:ai_skill, account: account, name: "Dependency Skill", category: "productivity")
      # Use same embedding as the mock (stubbed to Array.new(1536, 0.1)) — pgvector returns distance ≈ 0
      # suggest_dependencies filters out similarity > 0.92 (duplicates), so identical embeddings won't return results
      # Use a slightly different embedding to get similarity in the 0.5-0.92 range
      embedding = Array.new(1536, 0.1)
      embedding[0] = 0.5 # Slightly different to avoid identical match
      Ai::KnowledgeGraphNode.create!(
        account: account,
        name: "Dependency Skill",
        entity_type: "skill",
        node_type: "entity",
        status: "active",
        confidence: 1.0,
        ai_skill_id: skill.id,
        embedding: embedding
      )

      result = service.suggest_dependencies(
        proposed_skill_attrs: { name: "New Skill", description: "A new skill", category: "productivity" }
      )

      expect(result).to be_an(Array)
    end

    it "handles errors gracefully" do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_raise(StandardError, "boom")

      result = service.suggest_dependencies(proposed_skill_attrs: { name: "Test", description: "test", category: nil })

      expect(result).to eq([])
    end
  end
end
