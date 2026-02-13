# frozen_string_literal: true

FactoryBot.define do
  factory :ai_document, class: "Ai::Document" do
    association :knowledge_base, factory: :ai_knowledge_base
    sequence(:name) { |n| "Document #{n}" }
    content { Faker::Lorem.paragraphs(number: 3).join("\n\n") }
    source_type { "upload" }
    status { "pending" }
    content_type { "text/plain" }
    metadata { {} }
    extraction_config { {} }
    processing_errors { [] }
    chunk_count { 0 }
    token_count { 0 }

    trait :indexed do
      status { "indexed" }
      processed_at { Time.current }
      chunk_count { 5 }
      token_count { 1500 }
    end

    trait :processing do
      status { "processing" }
    end

    trait :failed do
      status { "failed" }
      processing_errors { [{ "error" => "Processing timeout" }] }
    end
  end
end
