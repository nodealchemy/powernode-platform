# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::CodeDiscoveryTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("code_discovery")
      expect(defn[:parameters]).to include(:action, :repository_id, :query)
    end
  end

  # Live symptom on the fleet control plane 2026-08-02: with the repository
  # correctly registered, semantic_search still failed with "Repository
  # 'powernode-platform' has no local_path in metadata". It queries
  # knowledge-graph rows and never touches the filesystem — it discards the
  # base_path it was forcing to resolve — so requiring a working copy to exist
  # on the server made pure vector search impossible on any node not hosting a
  # checkout.
  describe "#execute action=semantic_search without a repository local_path" do
    let!(:repository) do
      create(:git_repository, account: account, full_name: "nodealchemy/powernode-platform", metadata: {})
    end

    it "does not demand a filesystem path it never uses" do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(Array.new(1536) { 0.01 })

      result = tool.execute(params: {
        action: "semantic_search", query: "hostname envelope",
        repository_id: "nodealchemy/powernode-platform"
      })

      expect(result[:error].to_s).not_to include("local_path")
      expect(result[:success]).to be true
    end
  end

  describe "#execute action=semantic_search" do
    it "requires a query" do
      result = tool.execute(params: { action: "semantic_search", repository_id: "whatever" })
      expect(result).to eq({ success: false, error: "query is required" })
    end

    it "requires a repository_id" do
      result = tool.execute(params: { action: "semantic_search", query: "find the thing" })
      expect(result).to eq({ success: false, error: "repository_id is required" })
    end

    context "when repository_id does not match any repository for the account" do
      it "surfaces a self-correcting error listing the account's available repositories" do
        create(:git_repository, account: account, full_name: "nodealchemy/powernode-platform")
        create(:git_repository, account: account, full_name: "nodealchemy/other-repo")

        result = tool.execute(params: {
          action: "semantic_search",
          repository_id: "powernode",
          query: "embedding service"
        })

        expect(result[:success]).to be false
        expect(result[:error]).to include("repository not found: powernode")
        expect(result[:error]).to include("nodealchemy/powernode-platform")
        expect(result[:error]).to include("nodealchemy/other-repo")
      end

      it "never leaks another account's repositories" do
        other_account = create(:account)
        create(:git_repository, account: other_account, full_name: "other/secret-repo")

        result = tool.execute(params: {
          action: "semantic_search",
          repository_id: "powernode",
          query: "embedding service"
        })

        expect(result[:success]).to be false
        expect(result[:error]).not_to include("secret-repo")
        expect(result[:error]).to include("no git repositories")
      end
    end
  end

  # Measured 2026-08-03 (docs/operations/code-index-retrieval-quality.md):
  # pure vector search answered identifier-shaped queries well (0.73) but could
  # not retrieve KillSwitchService#emergency_halt! for "immediately stop a
  # runaway autonomous agent" — not even in the top TEN — despite that node
  # carrying the doc "Coordinated emergency stop — halts ALL agentic activity".
  # Three attempts at enriching the corpus did not fix it. The lexical arm
  # recovers it because the answer IS reachable by a word in the query.
  describe "hybrid retrieval" do
    let!(:repository) do
      create(:git_repository, account: account, full_name: "acme/app", metadata: {})
    end
    let!(:kb) { create(:ai_knowledge_base, account: account, git_repository_id: repository.id) }

    def node(simple, description, embedding: nil, mentions: 1)
      create(:ai_knowledge_graph_node,
             account: account, knowledge_base: kb,
             name: "app/svc.rb::Svc##{simple}", node_type: "code_entity", entity_type: "method",
             description: description, embedding: embedding, status: "active",
             mention_count: mentions,
             properties: { "simple_name" => simple, "file_path" => "app/svc.rb" })
    end

    def search(query, top_k: 5)
      tool.execute(params: { action: "semantic_search", query: query,
                             repository_id: "acme/app", top_k: top_k })
    end

    # Only the decoys are embedded, so the vector arm can never return the
    # target — exactly the situation measured in production.
    def setup_target_invisible_to_vector!
      target = node("emergency_halt!", "Coordinated emergency stop - halts ALL agentic activity for an account.")
      decoys = 3.times.map { |i| node("unrelated_#{i}", "something else entirely", embedding: Array.new(1536) { 0.01 }) }
      [target, decoys]
    end

    before do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(Array.new(1536) { 0.01 })
    end

    it "surfaces a behavioural match the vector arm cannot return at all" do
      target, = setup_target_invisible_to_vector!

      result = search("immediately stop a runaway autonomous agent")

      expect(result[:success]).to be true
      ids = result[:results].map { |r| r[:id] }
      expect(ids).to include(target.id), "lexical arm must recover what the vector arm cannot see"
      expect(result[:retrieval][:mode]).to eq("hybrid")
    end

    it "labels which arm found each result" do
      target, = setup_target_invisible_to_vector!

      hit = search("emergency stop agentic").fetch(:results).find { |r| r[:id] == target.id }

      expect(hit[:matched_by]).to eq(["lexical"])
      expect(hit[:lexical_rank]).to be_present
      expect(hit[:vector_rank]).to be_nil
    end

    it "ranks a node matching more query terms above one matching fewer" do
      both = node("halt_agent", "stops the agent")
      one  = node("halt_only", "stops a job")

      ids = search("halt agent").fetch(:results).map { |r| r[:id] }

      expect(ids.index(both.id)).to be < ids.index(one.id)
    end

    it "degrades to lexical-only instead of failing when embeddings are down" do
      target, = setup_target_invisible_to_vector!
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_raise(Ai::Memory::EmbeddingService::EmbeddingError, "worker down")

      result = search("emergency stop agentic")

      expect(result[:success]).to be true
      expect(result[:retrieval][:mode]).to eq("lexical_only")
      expect(result[:results].map { |r| r[:id] }).to include(target.id)
    end

    it "drops stopwords and short tokens so they cannot match the whole corpus" do
      expect(tool.send(:query_terms, "how do I stop an agent from the queue"))
        .to eq(%w[stop agent queue])
    end

    it "still answers identifier-shaped queries, which vector search already did well" do
      target = node("emergency_halt!", "Coordinated emergency stop.",
                    embedding: Array.new(1536) { 0.01 })

      expect(search("emergency_halt").fetch(:results).map { |r| r[:id] }).to include(target.id)
    end
  end
end
