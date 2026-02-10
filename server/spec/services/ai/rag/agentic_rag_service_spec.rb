# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Rag::AgenticRagService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  describe "#retrieve" do
    it "returns result structure with search history" do
      result = service.retrieve(query: "What is Ruby on Rails?")

      expect(result).to have_key(:answer)
      expect(result).to have_key(:sources)
      expect(result).to have_key(:search_history)
      expect(result).to have_key(:rounds_used)
      expect(result).to have_key(:total_results)
      expect(result[:rounds_used]).to be >= 1
    end

    it "records search history for each round" do
      result = service.retrieve(query: "test query", max_rounds: 2)

      expect(result[:search_history]).to be_an(Array)
      expect(result[:search_history].first).to have_key(:round)
      expect(result[:search_history].first).to have_key(:query)
      expect(result[:search_history].first).to have_key(:results_count)
    end

    it "limits max_rounds" do
      result = service.retrieve(query: "test query", max_rounds: 1)
      expect(result[:rounds_used]).to eq(1)
    end

    context "with document chunks available" do
      let(:kb) { create(:ai_knowledge_base, account: account) }
      let(:document) do
        Ai::Document.create!(
          knowledge_base: kb,
          name: "Ruby Guide",
          source_type: "upload",
          content: "Ruby is a dynamic programming language designed for productivity and simplicity. " \
                   "Ruby on Rails is a popular web framework written in Ruby. " \
                   "Rails follows the convention over configuration principle.",
          status: "indexed"
        )
      end

      before do
        embedding_service = Ai::Memory::EmbeddingService.new(account: account)

        ["Ruby is a dynamic programming language designed for productivity.",
         "Ruby on Rails is a popular web framework written in Ruby.",
         "Rails follows the convention over configuration principle."].each_with_index do |text, idx|
          chunk = Ai::DocumentChunk.create!(
            document: document,
            knowledge_base: kb,
            sequence_number: idx + 1,
            content: text,
            token_count: text.length / 4,
            start_offset: 0,
            end_offset: text.length
          )
          embedding = embedding_service.generate(text)
          chunk.set_embedding!(embedding, "text-embedding-3-small") if embedding
        end
      end

      it "retrieves relevant sources" do
        result = service.retrieve(query: "What is Ruby on Rails?")

        expect(result[:sources]).to be_an(Array)
        expect(result[:total_results]).to be >= 0
      end

      it "supports reranking option" do
        result = service.retrieve(
          query: "Ruby programming language",
          enable_reranking: true
        )

        expect(result).to have_key(:sources)
      end
    end
  end
end
