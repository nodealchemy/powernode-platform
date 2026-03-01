# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Memory::EmbeddingService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:mock_redis) { instance_double(Redis) }

  subject(:service) { described_class.new(account: account, provider: provider) }

  before do
    allow_any_instance_of(described_class).to receive(:redis_client).and_return(mock_redis)
  end

  # ===========================================================================
  # #generate
  # ===========================================================================

  describe "#generate" do
    it "returns nil for blank text" do
      expect(service.generate("")).to be_nil
      expect(service.generate(nil)).to be_nil
    end

    it "returns an embedding vector for valid text" do
      allow(mock_redis).to receive(:get).and_return(nil)
      allow(mock_redis).to receive(:setex)

      embedding = service.generate("Hello, world!")

      expect(embedding).to be_an(Array)
      expect(embedding.length).to eq(described_class::EMBEDDING_DIMENSION)
      expect(embedding.all? { |v| v.is_a?(Numeric) }).to be true
    end

    it "returns cached embedding when available" do
      cached_embedding = Array.new(described_class::EMBEDDING_DIMENSION) { rand(-1.0..1.0) }
      allow(mock_redis).to receive(:get).and_return(cached_embedding.to_json)

      embedding = service.generate("cached text")

      expect(embedding).to eq(cached_embedding)
    end

    it "caches generated embeddings in redis" do
      allow(mock_redis).to receive(:get).and_return(nil)
      expect(mock_redis).to receive(:setex).with(
        anything,
        described_class::CACHE_TTL.to_i,
        anything
      )

      service.generate("text to cache")
    end

    it "skips cache when use_cache is false" do
      expect(mock_redis).not_to receive(:get)
      expect(mock_redis).not_to receive(:setex)

      embedding = service.generate("uncached text", use_cache: false)

      expect(embedding).to be_an(Array)
    end

    it "generates deterministic embeddings for the same text" do
      allow(mock_redis).to receive(:get).and_return(nil)
      allow(mock_redis).to receive(:setex)

      embedding1 = service.generate("same text", use_cache: false)
      embedding2 = service.generate("same text", use_cache: false)

      expect(embedding1).to eq(embedding2)
    end

    it "generates different embeddings for different text" do
      allow(mock_redis).to receive(:get).and_return(nil)
      allow(mock_redis).to receive(:setex)

      embedding1 = service.generate("text one", use_cache: false)
      embedding2 = service.generate("text two", use_cache: false)

      expect(embedding1).not_to eq(embedding2)
    end
  end

  # ===========================================================================
  # #generate_batch
  # ===========================================================================

  describe "#generate_batch" do
    before do
      allow(mock_redis).to receive(:get).and_return(nil)
      allow(mock_redis).to receive(:setex)
    end

    it "returns empty array for blank input" do
      expect(service.generate_batch([])).to eq([])
      expect(service.generate_batch(nil)).to eq([])
    end

    it "generates embeddings for multiple texts" do
      texts = ["Hello", "World", "Test"]
      embeddings = service.generate_batch(texts)

      expect(embeddings.length).to eq(3)
      embeddings.each do |embedding|
        expect(embedding).to be_an(Array)
        expect(embedding.length).to eq(described_class::EMBEDDING_DIMENSION)
      end
    end

    it "uses cached values when available" do
      cached_embedding = Array.new(described_class::EMBEDDING_DIMENSION) { 0.5 }
      allow(mock_redis).to receive(:get).and_return(nil)
      allow(mock_redis).to receive(:get)
        .with(anything)
        .and_return(nil, cached_embedding.to_json, nil)

      texts = ["uncached1", "cached", "uncached2"]
      embeddings = service.generate_batch(texts)

      expect(embeddings.length).to eq(3)
      expect(embeddings[1]).to eq(cached_embedding)
    end

    it "caches each generated embedding" do
      texts = ["alpha", "beta"]
      expect(mock_redis).to receive(:setex).exactly(2).times

      service.generate_batch(texts)
    end
  end

  # ===========================================================================
  # #similarity
  # ===========================================================================

  describe "#similarity" do
    it "returns 0.0 for blank embeddings" do
      expect(service.similarity(nil, nil)).to eq(0.0)
      expect(service.similarity([], [])).to eq(0.0)
    end

    it "returns 0.0 for mismatched dimensions" do
      expect(service.similarity([1.0, 2.0], [1.0])).to eq(0.0)
    end

    it "returns 1.0 for identical normalized vectors" do
      vector = [1.0, 0.0, 0.0]
      expect(service.similarity(vector, vector)).to eq(1.0)
    end

    it "returns 0.0 for orthogonal vectors" do
      v1 = [1.0, 0.0, 0.0]
      v2 = [0.0, 1.0, 0.0]
      expect(service.similarity(v1, v2)).to eq(0.0)
    end

    it "returns a value between -1 and 1" do
      v1 = [0.5, 0.3, -0.1, 0.8]
      v2 = [0.2, -0.4, 0.6, 0.1]
      result = service.similarity(v1, v2)

      expect(result).to be_between(-1.0, 1.0)
    end
  end

  # ===========================================================================
  # #find_similar
  # ===========================================================================

  describe "#find_similar" do
    it "returns empty array for blank inputs" do
      expect(service.find_similar(nil, [])).to eq([])
      expect(service.find_similar([], nil)).to eq([])
    end

    it "ranks candidates by similarity score" do
      query = [1.0, 0.0, 0.0]
      candidates = [
        { id: 1, embedding: [0.0, 1.0, 0.0] },  # orthogonal
        { id: 2, embedding: [0.9, 0.1, 0.0] },   # similar
        { id: 3, embedding: [1.0, 0.0, 0.0] }    # identical
      ]

      results = service.find_similar(query, candidates, top_k: 3)

      expect(results.first[:id]).to eq(3)
      expect(results.first[:similarity]).to eq(1.0)
      expect(results.last[:id]).to eq(1)
    end

    it "limits results to top_k" do
      query = [1.0, 0.0]
      candidates = Array.new(10) { |i| { id: i, embedding: [rand, rand] } }

      results = service.find_similar(query, candidates, top_k: 3)

      expect(results.length).to eq(3)
    end

    it "includes similarity score in each result" do
      query = [1.0, 0.0]
      candidates = [{ id: 1, embedding: [0.5, 0.5] }]

      results = service.find_similar(query, candidates)

      expect(results.first).to have_key(:similarity)
      expect(results.first[:similarity]).to be_a(Numeric)
    end
  end

  # ===========================================================================
  # #clear_cache / #clear_all_cache
  # ===========================================================================

  describe "#clear_cache" do
    it "deletes a specific cache entry" do
      expect(mock_redis).to receive(:del).with(anything)

      service.clear_cache("some text")
    end
  end

  describe "#clear_all_cache" do
    it "deletes all cache entries for the account" do
      keys = ["key1", "key2"]
      expect(mock_redis).to receive(:keys)
        .with("#{described_class::CACHE_PREFIX}:#{account.id}:*")
        .and_return(keys)
      expect(mock_redis).to receive(:del).with(*keys)

      service.clear_all_cache
    end

    it "does nothing when no keys exist" do
      expect(mock_redis).to receive(:keys).and_return([])
      expect(mock_redis).not_to receive(:del)

      service.clear_all_cache
    end
  end
end
