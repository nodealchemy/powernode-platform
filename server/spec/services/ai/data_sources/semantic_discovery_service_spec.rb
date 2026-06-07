# frozen_string_literal: true

require "rails_helper"

# Hermetic specs for the Phase-2a semantic discovery service. The service blends
# four trust signals (semantic / effectiveness / health / recency) into a single
# 0..1 score and returns sources ranked desc.
#
# Hermeticity strategy (NO real embedding calls, NO outbound HTTP):
#   * The Ai::DataSource after_commit KG sync is stubbed at the bridge boundary
#     (Ai::DataSourceGraph::BridgeService#sync_data_source) so creating sources +
#     KG nodes via factories never reaches a real embedding backend, and never
#     auto-creates KG nodes that would collide with the ones each example builds.
#   * The embedding backend (Ai::Memory::EmbeddingService#generate) is stubbed
#     per-example to a deterministic vector (semantic path) or nil (degradation /
#     keyword-fallback path).
#   * pgvector's nearest_neighbors is stubbed to return the exact KG nodes the
#     example wants ranked, each carrying a set neighbor_distance, so cosine
#     similarity is deterministic without a real vector index.
RSpec.describe Ai::DataSources::SemanticDiscoveryService, type: :service do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  subject(:service) { described_class.new(account) }

  before do
    # Keep source/node creation off the real embedding backend (and off the KG
    # sync that would otherwise build competing data_source nodes).
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  # Builds a data_source + a backing data_source KG node wired by ai_data_source_id,
  # with the trust columns the blend reads set explicitly. Returns [source, node].
  def build_source_with_node(
    account: nil,
    name: "Source",
    effectiveness_score: 0.5,
    health_status: "healthy",
    is_active: true,
    last_used_at: nil,
    description: nil
  )
    acct = account || self.account
    source = create(
      :ai_data_source,
      account: acct,
      name: name,
      description: description,
      health_status: health_status,
      is_active: is_active
    )
    # update_columns bypasses callbacks/validations so we set the rolled-up
    # scoring columns without re-triggering the (stubbed) KG sync.
    source.update_columns(effectiveness_score: effectiveness_score, last_used_at: last_used_at)

    node = create(
      :ai_knowledge_graph_node,
      account: acct,
      entity_type: "data_source",
      name: name,
      status: "active"
    )
    node.update_columns(ai_data_source_id: source.id)

    [source.reload, node]
  end

  # Returns a node-double standing in for a pgvector nearest_neighbors result:
  # the service only reads #ai_data_source_id and #neighbor_distance off each.
  def neighbor(node, distance)
    instance_double(
      Ai::KnowledgeGraphNode,
      ai_data_source_id: node.ai_data_source_id,
      neighbor_distance: distance
    )
  end

  # Stub the semantic chain so generate -> a vector and nearest_neighbors -> the
  # supplied node-doubles, fully bypassing pgvector + the embedding backend.
  #
  # The service re-evaluates `account.ai_knowledge_graph_nodes` on each call
  # (it is not memoized), so we intercept the association on `account` itself and
  # return a self-chaining relation double. The double also answers the keyword
  # fallback chain (search_by_name -> limit -> to_a => []) so that when the
  # semantic path yields nothing, the fallback degrades cleanly to empty rather
  # than hitting a real (vector-less) query.
  def stub_semantic(neighbors:, embedding: Array.new(1536, 0.01), keyword: [])
    allow_any_instance_of(Ai::Memory::EmbeddingService)
      .to receive(:generate).and_return(embedding)

    relation = double("kg_nodes_relation")
    allow(account).to receive(:ai_knowledge_graph_nodes).and_return(relation)
    # The whole chain (data_source_nodes/active/with_embeddings) is self-returning.
    allow(relation).to receive(:data_source_nodes).and_return(relation)
    allow(relation).to receive(:active).and_return(relation)
    allow(relation).to receive(:with_embeddings).and_return(relation)
    allow(relation).to receive(:nearest_neighbors)
      .with(:embedding, embedding, distance: "cosine")
      .and_return(neighbors)
    # Keyword fallback terminal chain.
    allow(relation).to receive(:search_by_name).and_return(relation)
    allow(relation).to receive(:limit).and_return(relation)
    allow(relation).to receive(:to_a).and_return(keyword)
  end

  describe "#discover blended ranking (semantic path)" do
    it "ranks results by the blended score (cosine + effectiveness + health + recency), highest first" do
      # source_a: strong semantic match (low distance), high effectiveness, healthy, fresh.
      source_a, node_a = build_source_with_node(
        name: "Precipitation Forecast",
        effectiveness_score: 0.9,
        health_status: "healthy",
        last_used_at: Time.current
      )
      # source_b: weaker semantic match (higher distance), low effectiveness, degraded, stale.
      source_b, node_b = build_source_with_node(
        name: "Stale Equities Feed",
        effectiveness_score: 0.1,
        health_status: "degraded",
        last_used_at: 6.days.ago
      )

      stub_semantic(neighbors: [neighbor(node_a, 0.1), neighbor(node_b, 0.8)])

      results = service.discover(query: "hourly precipitation forecast")

      expect(results.map { |r| r[:data_source] }).to eq([source_a, source_b])
      # Descending by score regardless of the order nearest_neighbors returned.
      expect(results.first[:score]).to be > results.last[:score]
    end

    it "promotes a high-effectiveness source above a marginally closer-but-poor one (blend, not raw cosine)" do
      # closer cosine, but unhealthy + ineffective + never used.
      poor, poor_node = build_source_with_node(
        name: "Flaky Source",
        effectiveness_score: 0.0,
        health_status: "critical",
        is_active: false,
        last_used_at: nil
      )
      # slightly farther cosine, but effective + healthy + fresh.
      strong, strong_node = build_source_with_node(
        name: "Reliable Source",
        effectiveness_score: 1.0,
        health_status: "healthy",
        last_used_at: Time.current
      )

      stub_semantic(neighbors: [neighbor(poor_node, 0.20), neighbor(strong_node, 0.25)])

      results = service.discover(query: "weather")

      expect(results.first[:data_source]).to eq(strong)
      expect(results.last[:data_source]).to eq(poor)
    end

    it "computes semantic similarity as (1 - cosine_distance) and folds the WEIGHTS into the score" do
      source, node = build_source_with_node(
        name: "Exact Match",
        effectiveness_score: 0.5,
        health_status: "healthy",
        last_used_at: Time.current
      )

      stub_semantic(neighbors: [neighbor(node, 0.0)]) # identical => similarity 1.0

      result = service.discover(query: "anything").first
      signals = result[:signals]

      # distance 0.0 -> semantic 1.0; healthy -> 1.0; fresh (just used) -> 1.0;
      # effectiveness 0.5. Blended via the published WEIGHTS.
      w = described_class::WEIGHTS
      expected = (
        (w[:semantic] * 1.0) +
        (w[:effectiveness] * 0.5) +
        (w[:health] * 1.0) +
        (w[:recency] * 1.0)
      ).round(4)

      expect(signals[:semantic]).to eq(1.0)
      expect(result[:score]).to eq(expected)
      expect(result[:score]).to be_between(0.0, 1.0)
    end
  end

  describe "#discover signals payload" do
    it "returns a signals hash with semantic, effectiveness, health, and recency" do
      _source, node = build_source_with_node(
        name: "Signalled Source",
        effectiveness_score: 0.42,
        health_status: "healthy",
        last_used_at: Time.current
      )

      stub_semantic(neighbors: [neighbor(node, 0.3)])

      result = service.discover(query: "data").first

      expect(result).to include(:data_source, :score, :signals)
      expect(result[:signals].keys).to contain_exactly(:semantic, :effectiveness, :health, :recency)
      expect(result[:signals][:semantic]).to eq((1.0 - 0.3).round(4))
      expect(result[:signals][:effectiveness]).to eq(0.42)
      expect(result[:signals][:health]).to eq(1.0)        # healthy -> 1.0
      expect(result[:signals][:recency]).to be_within(0.01).of(1.0) # just used -> ~1.0
    end

    it "reports health as 0.0 for an unhealthy (degraded/inactive) source" do
      _source, node = build_source_with_node(
        name: "Degraded Source",
        health_status: "degraded",
        last_used_at: Time.current
      )

      stub_semantic(neighbors: [neighbor(node, 0.2)])

      result = service.discover(query: "data").first
      expect(result[:signals][:health]).to eq(0.0)
    end

    it "reports a neutral 0.5 recency for a never-used source" do
      _source, node = build_source_with_node(name: "Never Used", last_used_at: nil)

      stub_semantic(neighbors: [neighbor(node, 0.2)])

      result = service.discover(query: "data").first
      expect(result[:signals][:recency]).to eq(0.5)
    end
  end

  describe "#discover keyword fallback (no embeddings)" do
    it "falls back to search_by_name when the embedding backend yields nothing" do
      # No vector available -> semantic path returns [] -> keyword path runs.
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(nil)

      match, = build_source_with_node(name: "Weather Radar")
      _miss, = build_source_with_node(name: "Stock Tickers")

      results = service.discover(query: "weather")

      expect(results.map { |r| r[:data_source] }).to eq([match])
    end

    it "neutralizes the semantic signal to the keyword baseline on the fallback path" do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(nil)

      build_source_with_node(name: "Keyword Hit", effectiveness_score: 0.5)

      result = service.discover(query: "keyword").first
      expect(result[:signals][:semantic]).to eq(described_class::KEYWORD_SEMANTIC_BASELINE)
    end

    it "returns [] when neither embeddings nor a name match surface anything" do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(nil)

      build_source_with_node(name: "Completely Unrelated")

      expect(service.discover(query: "zzz-no-such-source")).to eq([])
    end
  end

  describe "#discover limit + scoping" do
    it "respects the limit, returning only the top-N by score" do
      nodes = []
      4.times do |i|
        _src, node = build_source_with_node(
          name: "Source #{i}",
          effectiveness_score: 0.5,
          last_used_at: Time.current
        )
        # Ascending distance so node 0 is the strongest semantic match.
        nodes << neighbor(node, 0.1 * (i + 1))
      end

      stub_semantic(neighbors: nodes)

      results = service.discover(query: "data", limit: 2)
      expect(results.size).to eq(2)
      # Sorted desc by score -> the two lowest-distance (strongest) sources.
      expect(results.first[:score]).to be >= results.last[:score]
    end

    it "returns an empty array when the account has no data_source nodes" do
      # Embedding present, but nearest_neighbors finds nothing; keyword fallback
      # also finds nothing (no data_source nodes exist).
      stub_semantic(neighbors: [])

      expect(service.discover(query: "anything")).to eq([])
    end

    it "returns [] for a blank query without touching the backend" do
      expect_any_instance_of(Ai::Memory::EmbeddingService).not_to receive(:generate)
      expect(service.discover(query: "   ")).to eq([])
    end

    it "does not surface another account's data sources" do
      # A foreign source whose node happens to come back from nearest_neighbors
      # is dropped because sources_for scopes the DataSource lookup to the account.
      _foreign_src, foreign_node = build_source_with_node(account: other_account, name: "Foreign")
      mine_src, mine_node = build_source_with_node(account: account, name: "Mine")

      stub_semantic(neighbors: [neighbor(foreign_node, 0.1), neighbor(mine_node, 0.2)])

      results = service.discover(query: "data")
      expect(results.map { |r| r[:data_source] }).to eq([mine_src])
    end
  end

  describe "#discover rerank: true" do
    it "routes candidates through Ai::Rag::RerankingService and folds relevance into the semantic signal" do
      source, node = build_source_with_node(
        name: "Rerankable Source",
        description: "weather observations",
        effectiveness_score: 0.5,
        health_status: "healthy",
        last_used_at: Time.current
      )

      stub_semantic(neighbors: [neighbor(node, 0.4)]) # pre-rerank semantic 0.6

      # The reranker receives content-adapted candidates and returns them with a
      # :rerank_score that overrides the semantic signal.
      reranked = nil
      allow_any_instance_of(Ai::Rag::RerankingService)
        .to receive(:rerank) do |_svc, query:, results:|
          expect(query).to eq("precipitation")
          # Service adapts each candidate into a :content blob before reranking.
          expect(results.first).to include(:content, :data_source, :signals)
          reranked = results.map { |r| r.merge(rerank_score: 0.95) }
          reranked
        end

      result = service.discover(query: "precipitation", rerank: true).first

      expect(result[:data_source]).to eq(source)
      # Semantic signal now reflects the reranker's relevance, not the raw cosine.
      expect(result[:signals][:semantic]).to eq(0.95)
      # Re-blended score uses the new semantic signal + unchanged trust signals.
      w = described_class::WEIGHTS
      expected = (
        (w[:semantic] * 0.95) +
        (w[:effectiveness] * 0.5) +
        (w[:health] * 1.0) +
        (w[:recency] * result[:signals][:recency])
      ).round(4)
      expect(result[:score]).to eq(expected)
      # The transient adapter key is stripped from the returned hash.
      expect(result).not_to have_key(:content)
      expect(result).not_to have_key(:rerank_score)
    end

    it "does not invoke the reranker when rerank is false (default, hermetic)" do
      _source, node = build_source_with_node(name: "No Rerank")
      stub_semantic(neighbors: [neighbor(node, 0.3)])

      expect_any_instance_of(Ai::Rag::RerankingService).not_to receive(:rerank)
      service.discover(query: "data") # rerank defaults to false
    end

    it "keeps the blended order when the reranker returns nothing usable" do
      source, node = build_source_with_node(
        name: "Fallback Source",
        effectiveness_score: 0.5,
        last_used_at: Time.current
      )
      stub_semantic(neighbors: [neighbor(node, 0.4)])

      allow_any_instance_of(Ai::Rag::RerankingService)
        .to receive(:rerank).and_return([])

      result = service.discover(query: "data", rerank: true).first
      expect(result[:data_source]).to eq(source)
      # Original blended semantic (1 - 0.4) is preserved, not overwritten.
      expect(result[:signals][:semantic]).to eq((1.0 - 0.4).round(4))
    end
  end
end
