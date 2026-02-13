# frozen_string_literal: true

FactoryBot.define do
  factory :ai_context_entry, class: "Ai::ContextEntry" do
    association :persistent_context, factory: :ai_persistent_context
    sequence(:entry_key) { |n| "entry_key_#{n}" }
    entry_type { "factual" }
    content { { "data" => Faker::Lorem.sentence } }
    content_text { Faker::Lorem.paragraph }
    memory_type { "factual" }
    confidence_score { 1.0 }
    importance_score { 0.5 }
    decay_rate { 0.0 }
    access_count { 0 }
    context_tags { [] }
    metadata { {} }

    trait :procedural do
      entry_type { "procedural" }
      memory_type { "procedural" }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :archived do
      archived_at { Time.current }
    end
  end
end
