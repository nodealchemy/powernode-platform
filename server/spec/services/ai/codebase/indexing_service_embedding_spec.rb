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

  # Measured 2026-08-02: embedding "#{node.name} #{node.description}" put the
  # fully path-qualified name AND the path again AND kind/visibility/params into
  # every vector. That boilerplate is near-identical across ~89k nodes, so it
  # diluted the only discriminating text. Adding doc comments alone did not move
  # behavioural queries; the noise had to come out of the embedded text.
  describe "#embedding_text" do
    def node_with(props, name: "some/path.rb::Klass#do_thing")
      build(:ai_knowledge_graph_node, account: account, knowledge_base: knowledge_base,
                                      name: name, node_type: "code_entity", properties: props)
    end

    it "omits path, visibility and params boilerplate" do
      text = service.send(:embedding_text, node_with({
        "simple_name" => "emergency_halt!", "kind" => "method",
        "visibility" => "private", "params" => "(reason:, triggered_by:)",
        "file_path" => "server/app/services/ai/autonomy/kill_switch_service.rb"
      }))

      expect(text).not_to include("server/app/services")
      expect(text).not_to include("triggered_by")
      expect(text).not_to include("private")
    end

    it "keeps the identifier and adds a word-split form so phrasing can match" do
      text = service.send(:embedding_text, node_with({
        "simple_name" => "emergency_halt!", "kind" => "method"
      }))

      expect(text).to include("emergency_halt!")
      expect(text).to include("emergency halt")
    end

    it "splits camelCase identifiers into words" do
      text = service.send(:embedding_text, node_with({
        "simple_name" => "guardMenuForViewer", "kind" => "function"
      }))

      expect(text).to include("guard Menu For Viewer")
    end

    it "carries the doc comment, which is the actual behavioural signal" do
      text = service.send(:embedding_text, node_with({
        "simple_name" => "emergency_halt!", "kind" => "method",
        "parent" => "KillSwitchService",
        "doc" => "Coordinated emergency stop — halts ALL agentic activity for an account."
      }))

      expect(text).to include("Coordinated emergency stop")
      expect(text).to include("Kill Switch Service")
    end

    # The whole point of SymbolSummaryService: a summary that never reaches
    # embedding_text is money spent on a properties field nothing reads.
    it "carries the LLM summary, the only query-shaped text in the corpus" do
      text = service.send(:embedding_text, node_with({
        "simple_name" => "emergency_halt!", "kind" => "method",
        "llm_summary" => "immediately stops a runaway autonomous agent from taking further action"
      }))

      expect(text).to include("immediately stops a runaway autonomous agent")
    end

    it "keeps the doc alongside the summary rather than replacing it" do
      text = service.send(:embedding_text, node_with({
        "simple_name" => "emergency_halt!", "kind" => "method",
        "llm_summary" => "stops every agent right now",
        "doc" => "Coordinated emergency stop — halts ALL agentic activity."
      }))

      # The author's own words often carry domain terms the summariser would not
      # invent, so these are complementary signals, not substitutes.
      expect(text).to include("stops every agent right now")
      expect(text).to include("Coordinated emergency stop")
    end

    it "does not repeat the word-split form when it equals the identifier" do
      text = service.send(:embedding_text, node_with({ "simple_name" => "halt", "kind" => "method" }))

      expect(text.scan(/halt/).length).to eq(1)
    end

    it "uses path words for file nodes, whose directories carry the domain" do
      text = service.send(:embedding_text, node_with(
        { "simple_name" => "peer_drift_service.rb", "language" => "ruby" },
        name: "extensions/system/server/app/services/sdwan/peer_drift_service.rb"
      ))

      expect(text).to include("sdwan")
      expect(text).to include("peer_drift_service.rb")
    end

    it "is what generate_batch actually receives" do
      create(:ai_knowledge_graph_node,
             account: account, knowledge_base: knowledge_base,
             name: "a/b.rb::K#emergency_halt!", node_type: "code_entity", entity_type: "method",
             description: "method `emergency_halt!` — in a/b.rb — params: (reason:)",
             embedding: nil, status: "active",
             properties: { "simple_name" => "emergency_halt!", "kind" => "method",
                           "doc" => "Halts ALL agentic activity." })

      embedder = instance_double(Ai::Memory::EmbeddingService)
      allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedder)
      seen = nil
      allow(embedder).to receive(:generate_batch) { |texts| seen = texts.first; texts.map { vector } }

      service.send(:generate_embeddings)

      expect(seen).to include("Halts ALL agentic activity.")
      expect(seen).not_to include("in a/b.rb")
    end
  end
end
