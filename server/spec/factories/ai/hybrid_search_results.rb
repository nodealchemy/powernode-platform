# frozen_string_literal: true

FactoryBot.define do
  factory :ai_hybrid_search_result, class: "Ai::HybridSearchResult" do
    account
    query_text { "test search query" }
    search_mode { "hybrid" }
    vector_results { [] }
    keyword_results { [] }
    graph_results { [] }
    merged_results { [] }
    result_count { 0 }
    fusion_method { "rrf" }
    reranked { false }
    metadata { {} }

    trait :vector_only do
      search_mode { "vector" }
    end

    trait :keyword_only do
      search_mode { "keyword" }
    end

    trait :graph_only do
      search_mode { "graph" }
    end

    trait :with_results do
      result_count { 5 }
      total_latency_ms { 150 }
      vector_score { 0.85 }
      keyword_score { 0.72 }
      graph_score { 0.68 }
    end
  end
end
