# frozen_string_literal: true

require "rails_helper"

# D7 — platform.query_learnings returned nothing for any keyword query.
#
# Two stacked defects in the shared retrieval helper
# (CompoundLearningService#ranked_learning_candidates):
#
#   1. The keyword fallback fired ONLY when the query embedding was nil. An
#      embedding that SUCCEEDS but matches nothing above the similarity floor
#      (the normal state of a corpus whose rows were stored during an embedding
#      outage, i.e. embedding: nil — invisible to nearest_neighbors) returned an
#      empty set with no keyword attempt at all.
#   2. The helper called EmbeddingService#generate, which RAISES
#      (EmbeddingError) when the worker embedding service is down. So the nil
#      branch the fallback hung off was close to unreachable in the exact
#      outage it existed for: the raise escaped past it. #generate_or_nil is
#      the read-path wrapper for precisely this and is what the other search
#      surfaces use.
#
# Both arms are asserted for every branch: the branch that must run, and the
# branch that must NOT be consulted.
RSpec.describe Ai::Learning::CompoundLearningService, "recall fallback", type: :service do
  let(:account) { create(:account) }
  let(:embedding_service) { instance_double(Ai::Memory::EmbeddingService) }
  let(:service) { described_class.new(account: account) }
  let(:embedding) { Array.new(1536, 0.1) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:generate).and_return(nil)
    allow(embedding_service).to receive(:generate_or_nil).and_return(nil)
    # Spy on the private keyword branch so "was the fallback consulted?" is a
    # direct observation rather than an inference from the row set.
    allow(service).to receive(:keyword_search).and_call_original
  end

  let!(:learning) do
    create(:ai_compound_learning, account: account, status: "active",
           title: "Fabricated review detection",
           content: "A fabricated review is flagged by the ingest pipeline",
           importance_score: 0.8)
  end

  describe "semantic branch returns EMPTY" do
    before do
      allow(embedding_service).to receive(:generate_or_nil).and_return(embedding)
      allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([])
    end

    it "falls back to the keyword branch and returns its rows" do
      result = service.search_learnings(query: "fabricated review")

      expect(result[:learnings].map(&:id)).to include(learning.id)
      expect(result[:match_mode]).to eq("keyword")
      expect(service).to have_received(:keyword_search)
    end
  end

  describe "semantic branch returns HITS" do
    before do
      allow(embedding_service).to receive(:generate_or_nil).and_return(embedding)
      allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([ learning ])
    end

    it "returns the semantic rows and never consults the keyword branch" do
      result = service.search_learnings(query: "completely unrelated wording")

      expect(result[:learnings].map(&:id)).to eq([ learning.id ])
      expect(result[:match_mode]).to eq("semantic")
      expect(service).not_to have_received(:keyword_search)
    end
  end

  describe "no embedding available (nil)" do
    it "keeps the pre-existing keyword behaviour and skips semantic_search" do
      allow(Ai::CompoundLearning).to receive(:semantic_search).and_call_original

      result = service.search_learnings(query: "fabricated review")

      expect(result[:learnings].map(&:id)).to include(learning.id)
      expect(result[:match_mode]).to eq("keyword")
      expect(service).to have_received(:keyword_search)
      expect(Ai::CompoundLearning).not_to have_received(:semantic_search)
    end
  end

  describe "embedding service unreachable (raises)" do
    # Exercises the real #generate_or_nil rescue rather than stubbing it away:
    # the outage must degrade to keyword search, not escape as an exception.
    let(:real_embedding_service) { Ai::Memory::EmbeddingService.new(account: account) }

    before do
      allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(real_embedding_service)
      allow(real_embedding_service).to receive(:generate)
        .and_raise(Ai::Memory::EmbeddingService::EmbeddingError, "worker embedding service down")
    end

    it "still returns keyword results instead of raising" do
      result = nil
      expect { result = service.search_learnings(query: "fabricated review") }.not_to raise_error
      expect(result[:learnings].map(&:id)).to include(learning.id)
      expect(result[:match_mode]).to eq("keyword")
    end
  end

  describe "neither branch matches" do
    it "reports match_mode none with no rows" do
      result = service.search_learnings(query: "zzzz nonexistent phrase qqqq")

      expect(result[:learnings]).to be_empty
      expect(result[:match_mode]).to eq("none")
    end
  end

  describe "similarity threshold configuration" do
    # Captured rather than matched with `.with(...)`: RSpec's recorded-kwargs
    # comparison false-negatives on this call (identical args report as
    # "received 0 times") — the same trap already annotated in
    # compound_learning_service_spec.rb.
    let(:captured) { [] }

    before do
      allow(embedding_service).to receive(:generate_or_nil).and_return(embedding)
      allow(Ai::CompoundLearning).to receive(:semantic_search) do |_embedding, **kwargs|
        captured << kwargs
        [ learning ]
      end
    end

    it "defaults to DEFAULT_RECALL_SIMILARITY_THRESHOLD" do
      service.search_learnings(query: "anything")

      expect(captured.first[:threshold]).to eq(described_class::DEFAULT_RECALL_SIMILARITY_THRESHOLD)
    end

    it "honors the account-level ai_learning_recall_similarity_threshold override" do
      account.update!(settings: (account.settings || {}).merge("ai_learning_recall_similarity_threshold" => 0.8))

      described_class.new(account: account.reload).search_learnings(query: "anything")

      expect(captured.first[:threshold]).to eq(0.8)
      expect(captured.first[:threshold]).not_to eq(described_class::DEFAULT_RECALL_SIMILARITY_THRESHOLD)
    end
  end

  describe "the reported defect, end to end through the MCP tool" do
    let(:user) { create(:user, account: account) }
    let(:tool) { Ai::Tools::LearningTool.new(account: account, user: user) }

    before do
      # A learnings corpus with no embeddings: the query embedding succeeds,
      # nearest_neighbors matches nothing. This is the production state that
      # returned zero results for every keyword query.
      allow(embedding_service).to receive(:generate_or_nil).and_return(embedding)
      allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([])
    end

    it "query_learnings('fabricated review') returns the seeded learnings" do
      other = create(:ai_compound_learning, account: account, status: "verified",
                     title: "Review fabrication signals",
                     content: "Fabricated review clusters share a submission window")

      result = tool.send(:call, action: "query_learnings", query: "fabricated review")

      expect(result[:success]).to be true
      expect(result[:learnings].map { |l| l[:id] }).to include(learning.id, other.id)
      expect(result[:match_mode]).to eq("keyword")
    end

    it "labels the no-query browse path as a filter listing" do
      result = tool.send(:call, action: "query_learnings")

      expect(result[:success]).to be true
      expect(result[:match_mode]).to eq("filter")
    end
  end
end
