# frozen_string_literal: true

FactoryBot.define do
  factory :ai_document_chunk, class: "Ai::DocumentChunk" do
    association :document, factory: :ai_document
    association :knowledge_base, factory: :ai_knowledge_base
    content { Faker::Lorem.paragraph(sentence_count: 5) }
    sequence(:sequence_number)
    metadata { {} }
    token_count { 200 }
    start_offset { 0 }
    end_offset { 500 }

    trait :embedded do
      embedded_at { Time.current }
      embedding_model { "text-embedding-3-small" }
    end
  end
end
