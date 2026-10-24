# frozen_string_literal: true

require "rails_helper"

# Production incident (token cap rollout): every discover_tools call embedded the
# query AND every catalog tool one worker request at a time. Tool embeddings were
# only cached on success and nothing warmed them, so each call cost ~N worker
# round trips, each costing the server two internal API calls, and the per-IP
# throttle shut every worker->server call out. A discovery call must cost at most
# ONE embedding worker request, and none when no provider answers.
RSpec.describe Ai::Tools::SemanticToolDiscoveryService, "embedding budget" do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:vector) { Array.new(8) { |i| (i + 1) / 10.0 } }
  let(:embedder) { instance_double(Ai::Memory::EmbeddingService) }

  let(:model_id) { "openai:text-embedding-3-small" }
  let(:requests) { [] }
  let(:failing) { false }

  before do
    allow(Rails).to receive(:cache).and_return(store)
    allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedder)
    allow(embedder).to receive(:model_id) { model_id }
    allow(embedder).to receive(:generate) do |_text, **|
      requests << :generate
      raise StandardError, "no provider" if failing
      vector
    end
    allow(embedder).to receive(:generate_batch) do |texts, **|
      requests << :generate_batch
      raise StandardError, "no provider" if failing
      texts.map { vector }
    end
  end

  def worker_requests
    requests.clear
    yield
    requests.size
  end

  it "makes at most one embedding request on a cold cache" do
    expect(worker_requests { service.discover(query: "deploy a node") }).to be <= 1
  end

  it "makes at most one embedding request once tool embeddings are cached" do
    service.discover(query: "deploy a node")
    expect(worker_requests { service.discover(query: "something else entirely") }).to be <= 1
  end

  it "makes none when the same query was answered and every tool is warmed" do
    service.discover(query: "deploy a node")
    expect(worker_requests { service.discover(query: "deploy a node") }).to eq(0)
  end

  context "when no embedding provider answers" do
    let(:failing) { true }

    it "falls back to keyword relevance and stops asking for a while" do
      first = nil
      expect(worker_requests { first = service.discover(query: "agent management create") }).to be <= 1
      expect(first).not_to be_empty
      expect(worker_requests { described_class.new(account: account).discover(query: "agent management") }).to eq(0)
    end
  end

  # The query cache key carried no account: one tenant's query vector (and the
  # tool ranking it drives) was served to another tenant that asked the same words.
  context "across accounts" do
    let(:other) { create(:account) }

    it "never serves one account's query embedding to another" do
      service.discover(query: "deploy a node")
      other_requests = worker_requests { described_class.new(account: other).discover(query: "deploy a node") }

      expect(other_requests).to eq(1)
      query_keys = store.instance_variable_get(:@data).keys.grep(/:query:/)
      expect(query_keys.size).to eq(2)
      expect(query_keys).to all(start_with("tool_discovery:"))
      expect(query_keys.join).to include(account.id).and include(other.id)
    end
  end

  # A tool's cached vector went stale silently when its description changed or the
  # account switched embedding model: the key was only the tool id.
  context "when the vector's inputs change" do
    it "re-embeds a different embedding model" do
      service.discover(query: "deploy a node")
      allow(embedder).to receive(:model_id) { "openai:text-embedding-3-large" }

      expect(worker_requests { described_class.new(account: account).discover(query: "deploy a node") }).to eq(1)
      expect(store.instance_variable_get(:@data).keys.grep(/:embedding:/).join).to include("text-embedding-3-large")
    end

    it "re-embeds a tool whose search text changed, and only that one" do
      service.discover(query: "deploy a node")
      tools = service.send(:collect_all_tools)
      changed = tools.first.merge(search_text: "a completely rewritten description")
      allow(service).to receive(:collect_all_tools).and_return([ changed ] + tools.drop(1))
      texts = nil
      allow(embedder).to receive(:generate_batch) { |t, **| texts = t; t.map { vector } }

      service.discover(query: "deploy a node")

      expect(texts).to eq([ "a completely rewritten description" ])
    end
  end

  it "reads the cached tool embeddings in one read_multi" do
    service.discover(query: "deploy a node")
    allow(store).to receive(:read).and_call_original
    allow(store).to receive(:read_multi).and_call_original

    service.discover(query: "deploy a node")

    expect(store).to have_received(:read_multi).at_least(:once)
    expect(store).not_to have_received(:read).with(/:embedding:/)
  end

  it "indexes tools through one generate_batch call, not one request per tool" do
    count = service.index_tools!

    expect(count).to be > 100
    expect(requests).to eq([ :generate_batch ])
  end
end
