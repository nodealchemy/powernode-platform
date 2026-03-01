# frozen_string_literal: true

FactoryBot.define do
  factory :ai_rag_query, class: "Ai::RagQuery" do
    account
    association :knowledge_base, factory: :ai_knowledge_base
    query_text { Faker::Lorem.question }
    status { "completed" }
    retrieval_strategy { "similarity" }
    search_mode { "vector" }
    similarity_threshold { 0.7 }
    top_k { 5 }
    chunks_retrieved { 3 }
    tokens_used { 500 }
    retrieved_chunks { [] }
    filters { {} }
    metadata { {} }

    trait :pending do
      status { "pending" }
    end

    trait :failed do
      status { "failed" }
    end

    trait :with_results do
      chunks_retrieved { 5 }
      avg_similarity_score { 0.85 }
      query_latency_ms { 120.5 }
    end
  end
end
