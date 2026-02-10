# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Rag::RerankingService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  let(:sample_results) do
    [
      { id: "1", content: "Ruby is a programming language focused on simplicity", score: 0.8, source: "vector" },
      { id: "2", content: "Python is used for data science and machine learning", score: 0.75, source: "vector" },
      { id: "3", content: "Ruby on Rails web framework was created by DHH", score: 0.7, source: "vector" },
      { id: "4", content: "JavaScript runs in web browsers", score: 0.65, source: "keyword" },
      { id: "5", content: "Rust programming language focuses on memory safety", score: 0.6, source: "keyword" }
    ]
  end

  describe "#rerank" do
    it "returns reranked results" do
      reranked = service.rerank(query: "Ruby programming", results: sample_results)

      expect(reranked).to be_an(Array)
      expect(reranked.size).to eq(5)
      expect(reranked.first).to have_key(:rerank_score)
    end

    it "returns empty array for empty input" do
      result = service.rerank(query: "test", results: [])
      expect(result).to eq([])
    end

    it "respects top_k parameter" do
      reranked = service.rerank(query: "Ruby programming", results: sample_results, top_k: 3)
      expect(reranked.size).to eq(3)
    end

    it "ranks Ruby-related content higher for Ruby query" do
      reranked = service.rerank(query: "Ruby programming language", results: sample_results)

      # Ruby-related results should be ranked higher
      ruby_results = reranked.first(3).select { |r| r[:content].include?("Ruby") }
      expect(ruby_results).not_to be_empty
    end

    it "uses heuristic reranking with keyword overlap scoring" do
      results = [
        { id: "a", content: "Ruby is great for web development", score: 0.5, source: "keyword" },
        { id: "b", content: "Java is used in enterprise applications", score: 0.9, source: "vector" }
      ]

      reranked = service.rerank(query: "Ruby web development", results: results)

      # The Ruby result should score well due to keyword overlap
      ruby_result = reranked.find { |r| r[:id] == "a" }
      expect(ruby_result[:rerank_score]).to be > 0
    end
  end
end
