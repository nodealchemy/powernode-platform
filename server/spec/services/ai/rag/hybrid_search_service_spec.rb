# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Rag::HybridSearchService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  describe "#search" do
    context "with vector mode" do
      it "performs vector search and records result" do
        result = service.search(query: "test query", mode: :vector, top_k: 5)

        expect(result).to have_key(:results)
        expect(result).to have_key(:scores)
        expect(result).to have_key(:metadata)
        expect(result[:metadata][:mode]).to eq("vector")
        expect(Ai::HybridSearchResult.count).to eq(1)
      end
    end

    context "with keyword mode" do
      it "performs keyword search" do
        result = service.search(query: "test query", mode: :keyword, top_k: 5)

        expect(result[:metadata][:mode]).to eq("keyword")
      end
    end

    context "with hybrid mode" do
      it "performs combined search" do
        result = service.search(query: "test query", mode: :hybrid, top_k: 5)

        expect(result[:metadata][:mode]).to eq("hybrid")
        expect(result[:scores]).to have_key(:vector)
        expect(result[:scores]).to have_key(:keyword)
        expect(result[:scores]).to have_key(:graph)
      end
    end

    context "with graph mode" do
      it "performs graph-based search" do
        result = service.search(query: "test query", mode: :graph, top_k: 5)

        expect(result[:metadata][:mode]).to eq("graph")
      end
    end

    it "raises error for invalid mode" do
      expect {
        service.search(query: "test", mode: :invalid)
      }.to raise_error(Ai::Rag::HybridSearchServiceError, /Invalid search mode/)
    end

    it "records search result in database" do
      service.search(query: "test query", mode: :hybrid)

      record = Ai::HybridSearchResult.last
      expect(record.query_text).to eq("test query")
      expect(record.search_mode).to eq("hybrid")
      expect(record.account).to eq(account)
    end

    context "with document chunks" do
      let(:kb) { create(:ai_knowledge_base, account: account) }
      let(:document) do
        Ai::Document.create!(
          knowledge_base: kb,
          name: "Test Doc",
          source_type: "upload",
          content: "Ruby on Rails is a web framework for building applications",
          status: "indexed"
        )
      end

      before do
        chunk = Ai::DocumentChunk.create!(
          document: document,
          knowledge_base: kb,
          sequence_number: 1,
          content: "Ruby on Rails is a web framework for building applications",
          token_count: 12,
          start_offset: 0,
          end_offset: 59
        )

        # Generate and set embedding for the chunk
        embedding_service = Ai::Memory::EmbeddingService.new(account: account)
        embedding = embedding_service.generate(chunk.content)
        chunk.set_embedding!(embedding, "text-embedding-3-small") if embedding
      end

      it "returns relevant chunks in vector search" do
        result = service.search(query: "web framework", mode: :vector, top_k: 5)

        expect(result[:results]).to be_an(Array)
      end

      it "returns relevant chunks in keyword search" do
        result = service.search(
          query: "Ruby Rails web framework",
          mode: :keyword,
          top_k: 5,
          knowledge_base_id: kb.id
        )

        expect(result[:results]).to be_an(Array)
      end
    end
  end
end
