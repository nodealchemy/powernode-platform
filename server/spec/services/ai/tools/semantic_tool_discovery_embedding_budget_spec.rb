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

  let(:requests) { [] }
  let(:failing) { false }

  before do
    allow(Rails).to receive(:cache).and_return(store)
    allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedder)
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
end
