# frozen_string_literal: true

FactoryBot.define do
  factory :ai_knowledge_base, class: "Ai::KnowledgeBase" do
    account
    sequence(:name) { |n| "Knowledge Base #{n}" }
    description { "A test knowledge base" }
    status { "active" }
    embedding_model { "text-embedding-3-small" }
    embedding_provider { "openai" }
    embedding_dimensions { 1536 }
    chunking_strategy { "recursive" }
    chunk_size { 1000 }
    chunk_overlap { 200 }
    metadata_schema { {} }
    settings { {} }
    is_public { false }

    trait :public_base do
      is_public { true }
    end

    trait :indexing do
      status { "indexing" }
    end

    trait :archived do
      status { "archived" }
    end
  end
end
