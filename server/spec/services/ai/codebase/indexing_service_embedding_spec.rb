# frozen_string_literal: true

require "rails_helper"

# Two defects found live on ops-hub 2026-08-02 while re-indexing powernode-platform.
#
# 1. generate_embeddings issued ONE rails -> worker -> OpenAI round-trip per node
#    (~27 nodes/min measured), so re-vectoring ~81.6k entities would have taken
#    ~50 hours. EmbeddingService#generate_batch already existed and was unused.
#
# 2. upsert_node refreshed an existing node's description but never cleared its
#    embedding, and generate_embeddings only ever selects `embedding: nil`. A
#    re-index therefore kept the ORIGINAL vector forever — semantic search drifted
#    from the code on every run and no amount of re-indexing could correct it.
RSpec.describe Ai::Codebase::IndexingService do
  let(:account) { create(:account) }
  let(:knowledge_base) { create(:ai_knowledge_base, account: account) }
  let(:service) { described_class.new(account: account, knowledge_base: knowledge_base, base_path: Dir.tmpdir) }
  let(:vector) { Array.new(1536, 0.01) }

  def code_node(name:, description: "does a thing", embedding: nil)
    create(:ai_knowledge_graph_node,
           account: account, knowledge_base: knowledge_base,
           name: name, node_type: "code_entity", entity_type: "class",
           description: description, embedding: embedding, status: "active")
  end

  describe "#generate_embeddings" do
    it "batches instead of making one provider call per node" do
      250.times { |i| code_node(name: "Klass#{i}") }

      embedder = instance_double(Ai::Memory::EmbeddingService)
      allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedder)
      sizes = []
      allow(embedder).to receive(:generate_batch) do |texts|
        sizes << texts.size
        texts.map { vector }
      end

      service.send(:generate_embeddings)

      # 250 nodes => 3 calls at EMBED_BATCH_SIZE=100, never one per node.
      expect(sizes.size).to eq(3)
      expect(sizes.max).to be <= described_class::EMBED_BATCH_SIZE
      expect(sizes.sum).to eq(250)
      expect(embedder).not_to have_received(:generate_batch).with(a_string_matching(/./))
      expect(service.stats[:nodes_embedded]).to eq(250)
      expect(service.stats[:embedding_failures]).to eq(0)
      expect(knowledge_base.knowledge_graph_nodes.where(embedding: nil).count).to eq(0)
    end

    it "assigns each returned vector to its own node, preserving order" do
      a = code_node(name: "Alpha")
      b = code_node(name: "Beta")
      vec_a = Array.new(1536, 0.11)
      vec_b = Array.new(1536, 0.22)

      embedder = instance_double(Ai::Memory::EmbeddingService)
      allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedder)
      allow(embedder).to receive(:generate_batch) do |texts|
        # Mirror the worker contract: results come back index-aligned with input.
        texts.map { |t| t.start_with?("Alpha") ? vec_a : vec_b }
      end

      service.send(:generate_embeddings)

      expect(a.reload.embedding.first.round(2)).to eq(0.11)
      expect(b.reload.embedding.first.round(2)).to eq(0.22)
    end

    it "counts nil vectors as failures rather than silently reporting success" do
      code_node(name: "Good")
      code_node(name: "Bad")

      embedder = instance_double(Ai::Memory::EmbeddingService)
      allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedder)
      allow(embedder).to receive(:generate_batch) do |texts|
        texts.map { |t| t.start_with?("Good") ? vector : nil }
      end

      service.send(:generate_embeddings)

      expect(service.stats[:nodes_embedded]).to eq(1)
      expect(service.stats[:embedding_failures]).to eq(1)
    end

    it "survives a failing batch and still reports the failure" do
      2.times { |i| code_node(name: "Boom#{i}") }

      embedder = instance_double(Ai::Memory::EmbeddingService)
      allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedder)
      allow(embedder).to receive(:generate_batch).and_raise(StandardError, "worker down")

      expect { service.send(:generate_embeddings) }.not_to raise_error
      expect(service.stats[:nodes_embedded]).to eq(0)
      expect(service.stats[:embedding_failures]).to eq(2)
    end
  end

  describe "#upsert_node re-embedding" do
    it "clears the stale embedding when the description changes" do
      node = code_node(name: "Drifted", description: "old behaviour", embedding: vector)

      service.send(:upsert_node, name: "Drifted", entity_type: "class",
                                 description: "new behaviour")

      expect(node.reload.description).to eq("new behaviour")
      expect(node.embedding).to be_nil, "stale vector must be re-queued for embedding"
    end

    it "keeps the embedding when the description is unchanged" do
      node = code_node(name: "Stable", description: "same text", embedding: vector)

      service.send(:upsert_node, name: "Stable", entity_type: "class",
                                 description: "same text")

      expect(node.reload.embedding).not_to be_nil, "unchanged nodes must not be re-embedded"
    end
  end
end
